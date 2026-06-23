package com.grocerymart.api.identity;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.audit.AuditService;
import com.grocerymart.api.identity.AuthDtos.AuthResponse;

/** Identity flows (Epic 2): phone OTP, portal email+password, registration, and
 *  refresh-token rotation with reuse detection. JdbcTemplate over the identity tables. */
@Service
public class AuthService {

    private static final Logger log = LoggerFactory.getLogger(AuthService.class);
    private static final int MAX_ATTEMPTS = 5;
    /** L-1: lock an account after this many consecutive failed portal logins, for this long. */
    private static final int MAX_LOGIN_FAILURES = 5;
    private static final String LOCKOUT_INTERVAL = "15 minutes";
    /** I-2: cap OTP requests per phone in a sliding window to curb SMS-flood / cost abuse. */
    private static final int MAX_OTP_PER_WINDOW = 3;
    private static final String OTP_WINDOW = "10 minutes";
    /** Roles a member of the public may self-register as. CUSTOMER only — SHOP_OWNER/ADMIN/STAFF/
     *  DRIVER/NGO are provisioned by an admin/invite flow (self-registering SHOP_OWNER let anyone
     *  reach the shop-owner API unvetted). */
    private static final Set<String> SELF_REGISTERABLE = Set.of("CUSTOMER");

    private final JdbcTemplate jdbc;
    private final PasswordEncoder encoder;
    private final OtpSender otpSender;
    private final JwtService jwt;
    private final AuditService audit;
    private final SecureRandom random = new SecureRandom();
    /** Dev-only: when true, OTP codes / reset tokens are logged so a local developer can retrieve
     *  them. MUST remain false in any deployed environment (defaults false). */
    private final boolean logSecrets;

    public AuthService(JdbcTemplate jdbc, PasswordEncoder encoder, OtpSender otpSender, JwtService jwt,
            AuditService audit,
            @org.springframework.beans.factory.annotation.Value("${grocerymart.dev.log-secrets:false}") boolean logSecrets) {
        this.jdbc = jdbc;
        this.encoder = encoder;
        this.otpSender = otpSender;
        this.jwt = jwt;
        this.audit = audit;
        this.logSecrets = logSecrets;
    }

    // ---- Story 2.2: phone OTP -------------------------------------------------

    @Transactional
    public void requestOtp(String phone) {
        // I-2: per-phone sliding-window cap (DB-backed, immune to IP rotation). Uniform behavior —
        // do not reveal that the cap was hit (no enumeration / no oracle).
        Integer recent = jdbc.queryForObject(
            "SELECT count(*) FROM otp_challenge WHERE phone = ? AND created_at > now() - interval '" + OTP_WINDOW + "'",
            Integer.class, phone);
        if (recent != null && recent >= MAX_OTP_PER_WINDOW) {
            log.warn("OTP request throttled for a phone (per-phone window cap reached)");
            return;   // silently accept the request without sending another code
        }
        String code = String.format("%06d", random.nextInt(1_000_000));
        jdbc.update("INSERT INTO otp_challenge (phone, code_hash, expires_at) "
            + "VALUES (?, ?, now() + interval '5 minutes')", phone, encoder.encode(code));
        otpSender.send(phone, code);
    }

    @Transactional
    public AuthResponse verifyOtp(String phone, String code) {
        List<Map<String, Object>> rows = jdbc.queryForList(
            "SELECT id, code_hash, attempts FROM otp_challenge "
            + "WHERE phone = ? AND consumed_at IS NULL AND expires_at > now() "
            + "ORDER BY created_at DESC LIMIT 1", phone);
        if (rows.isEmpty()) {
            throw ApiException.badRequest("No valid code. Please request a new OTP.");
        }
        Map<String, Object> row = rows.get(0);
        UUID challengeId = (UUID) row.get("id");
        if (((Number) row.get("attempts")).intValue() >= MAX_ATTEMPTS) {
            throw ApiException.badRequest("Too many attempts. Please request a new OTP.");
        }
        if (!encoder.matches(code, (String) row.get("code_hash"))) {
            jdbc.update("UPDATE otp_challenge SET attempts = attempts + 1 WHERE id = ?", challengeId);
            throw ApiException.badRequest("Invalid code.");
        }
        jdbc.update("UPDATE otp_challenge SET consumed_at = now() WHERE id = ?", challengeId);
        return issueTokensFor(findOrCreateCustomer(phone));
    }

    // ---- Story 2.4: portal email + password + reset ---------------------------

    // NOT @Transactional: the failed-login bookkeeping (lockout counter) must COMMIT even though the
    // method then throws 401 — a single ambient transaction would roll the counter back on the throw.
    // Each statement auto-commits; audit calls are REQUIRES_NEW.
    public AuthResponse portalLogin(String email, String password) {
        List<Map<String, Object>> rows = jdbc.queryForList(
            "SELECT id, password_hash, failed_login_count, (locked_until IS NOT NULL AND locked_until > now()) AS locked "
            + "FROM app_user WHERE email = ? AND status = 'active'", email);
        // Enumeration-safe: unknown email, wrong password, AND a locked account all return the SAME
        // generic 401 — a locked account does not even reach the password check.
        if (rows.isEmpty() || rows.get(0).get("password_hash") == null) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Invalid email or password.");
        }
        Map<String, Object> u = rows.get(0);
        UUID userId = (UUID) u.get("id");
        if (Boolean.TRUE.equals(u.get("locked"))) {
            audit.denied(userId, "auth.login.locked", "user", userId.toString());
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Invalid email or password.");
        }
        if (!encoder.matches(password, (String) u.get("password_hash"))) {
            int failures = ((Number) u.get("failed_login_count")).intValue() + 1;
            if (failures >= MAX_LOGIN_FAILURES) {
                jdbc.update("UPDATE app_user SET failed_login_count = 0, locked_until = now() + interval '"
                    + LOCKOUT_INTERVAL + "' WHERE id = ?", userId);
            } else {
                jdbc.update("UPDATE app_user SET failed_login_count = ? WHERE id = ?", failures, userId);
            }
            audit.denied(userId, "auth.login.failed", "user", userId.toString());
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Invalid email or password.");
        }
        // Success: clear the failure counter / lock.
        jdbc.update("UPDATE app_user SET failed_login_count = 0, locked_until = NULL WHERE id = ?", userId);
        audit.success(userId, "auth.login", "user", userId.toString(), null, null);
        return issueTokensFor(userId);
    }

    @Transactional
    public void requestPasswordReset(String email) {
        List<UUID> rows = jdbc.queryForList("SELECT id FROM app_user WHERE email = ?", UUID.class, email);
        if (!rows.isEmpty()) {
            String token = randomToken();
            jdbc.update("INSERT INTO password_reset (user_id, token_hash, expires_at) "
                + "VALUES (?, ?, now() + interval '30 minutes')", rows.get(0), sha256(token));
            // SECURITY: never log a live reset token in a deployed environment. Dev-only when
            // grocerymart.dev.log-secrets=true; production must deliver via the (future) email channel.
            if (logSecrets) {
                log.warn("DEV password reset token for {}: {}  (dev-only)", email, token);
            }
        }
        // Always succeed regardless of whether the email exists (no enumeration).
    }

    @Transactional
    public void confirmPasswordReset(String token, String newPassword) {
        List<Map<String, Object>> rows = jdbc.queryForList(
            "SELECT id, user_id FROM password_reset "
            + "WHERE token_hash = ? AND consumed_at IS NULL AND expires_at > now() "
            + "ORDER BY created_at DESC LIMIT 1", sha256(token));
        if (rows.isEmpty()) {
            throw ApiException.badRequest("Invalid or expired reset token.");
        }
        UUID userId = (UUID) rows.get(0).get("user_id");
        // Clear any lockout, reset the password, and revoke BOTH refresh tokens and outstanding
        // access tokens (tokens_valid_from = now()) so a password change logs every session out.
        jdbc.update("UPDATE app_user SET password_hash = ?, failed_login_count = 0, locked_until = NULL, "
            + "tokens_valid_from = now() WHERE id = ?", encoder.encode(newPassword), userId);
        jdbc.update("UPDATE password_reset SET consumed_at = now() WHERE id = ?", rows.get(0).get("id"));
        jdbc.update("UPDATE refresh_token SET revoked_at = now() WHERE user_id = ? AND revoked_at IS NULL", userId);
        audit.success(userId, "auth.password_reset", "user", userId.toString(), null, null);
    }

    // ---- Story 2.7: restricted registration -----------------------------------

    @Transactional
    public AuthResponse register(String email, String password, String role, String displayName) {
        String r = (role == null || role.isBlank()) ? "CUSTOMER" : role.toUpperCase();
        if (!SELF_REGISTERABLE.contains(r)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "You cannot self-register as " + r + ".");
        }
        if (!jdbc.queryForList("SELECT 1 FROM app_user WHERE email = ?", email).isEmpty()) {
            // Generic message — do not confirm that the email is already registered (enumeration).
            throw ApiException.badRequest("Registration could not be completed.");
        }
        UUID id = jdbc.queryForObject(
            "INSERT INTO app_user (email, display_name, password_hash) VALUES (?, ?, ?) RETURNING id",
            UUID.class, email, displayName, encoder.encode(password));
        jdbc.update("INSERT INTO user_role (user_id, role) VALUES (?, ?)", id, r);
        audit.success(id, "auth.register", "user", id.toString(), null, Map.of("role", r));
        return issueTokensFor(id);
    }

    // ---- Story 2.6: refresh rotation + reuse detection ------------------------

    @Transactional
    public AuthResponse refresh(String rawToken) {
        List<Map<String, Object>> rows = jdbc.queryForList(
            "SELECT id, user_id, (revoked_at IS NOT NULL) AS revoked, (expires_at < now()) AS expired "
            + "FROM refresh_token WHERE token_hash = ?", sha256(rawToken));
        if (rows.isEmpty()) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Invalid refresh token.");
        }
        Map<String, Object> row = rows.get(0);
        UUID userId = (UUID) row.get("user_id");
        if (Boolean.TRUE.equals(row.get("revoked"))) {
            // A revoked token presented again == replay/theft. Revoke the whole session family AND
            // invalidate outstanding access tokens; persist the security event (I-1).
            jdbc.update("UPDATE refresh_token SET revoked_at = now() WHERE user_id = ? AND revoked_at IS NULL", userId);
            jdbc.update("UPDATE app_user SET tokens_valid_from = now() WHERE id = ?", userId);
            audit.denied(userId, "auth.refresh.reuse_detected", "user", userId.toString());
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Refresh token reuse detected; all sessions revoked. Sign in again.");
        }
        if (Boolean.TRUE.equals(row.get("expired"))) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Refresh token expired. Sign in again.");
        }
        jdbc.update("UPDATE refresh_token SET revoked_at = now() WHERE id = ?", row.get("id"));
        return issueTokensFor(userId);
    }

    @Transactional
    public void logout(String rawToken) {
        // Revoke the refresh token AND invalidate outstanding access tokens for that user (L-2):
        // tokens_valid_from = now() makes JwtAuthFilter reject any access token issued before logout.
        List<UUID> owner = jdbc.queryForList(
            "SELECT user_id FROM refresh_token WHERE token_hash = ?", UUID.class, sha256(rawToken));
        jdbc.update("UPDATE refresh_token SET revoked_at = now() WHERE token_hash = ? AND revoked_at IS NULL",
            sha256(rawToken));
        if (!owner.isEmpty()) {
            jdbc.update("UPDATE app_user SET tokens_valid_from = now() WHERE id = ?", owner.get(0));
        }
    }

    // ---- helpers --------------------------------------------------------------

    private UUID findOrCreateCustomer(String phone) {
        List<UUID> existing = jdbc.queryForList("SELECT id FROM app_user WHERE phone = ?", UUID.class, phone);
        if (!existing.isEmpty()) {
            return existing.get(0);
        }
        UUID id = jdbc.queryForObject("INSERT INTO app_user (phone) VALUES (?) RETURNING id", UUID.class, phone);
        jdbc.update("INSERT INTO user_role (user_id, role) VALUES (?, 'CUSTOMER')", id);
        return id;
    }

    private AuthResponse issueTokensFor(UUID userId) {
        List<String> roles = jdbc.queryForList("SELECT role FROM user_role WHERE user_id = ?", String.class, userId);
        String access = jwt.issueAccessToken(userId.toString(), roles);
        String refresh = issueRefreshToken(userId);
        return new AuthResponse(access, refresh, userId.toString(), roles);
    }

    private String issueRefreshToken(UUID userId) {
        String token = randomToken();
        jdbc.update("INSERT INTO refresh_token (user_id, token_hash, expires_at) "
            + "VALUES (?, ?, now() + interval '30 days')", userId, sha256(token));
        return token;
    }

    private String randomToken() {
        byte[] buf = new byte[32];
        random.nextBytes(buf);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(buf);
    }

    private static String sha256(String s) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
