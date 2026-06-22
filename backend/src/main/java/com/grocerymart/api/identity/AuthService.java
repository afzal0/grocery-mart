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

import com.grocerymart.api.identity.AuthDtos.AuthResponse;

/** Identity flows (Epic 2): phone OTP, portal email+password, registration, and
 *  refresh-token rotation with reuse detection. JdbcTemplate over the identity tables. */
@Service
public class AuthService {

    private static final Logger log = LoggerFactory.getLogger(AuthService.class);
    private static final int MAX_ATTEMPTS = 5;
    /** Roles a member of the public may self-register as. Never ADMIN/STAFF/DRIVER/NGO. */
    private static final Set<String> SELF_REGISTERABLE = Set.of("CUSTOMER", "SHOP_OWNER");

    private final JdbcTemplate jdbc;
    private final PasswordEncoder encoder;
    private final OtpSender otpSender;
    private final JwtService jwt;
    private final SecureRandom random = new SecureRandom();

    public AuthService(JdbcTemplate jdbc, PasswordEncoder encoder, OtpSender otpSender, JwtService jwt) {
        this.jdbc = jdbc;
        this.encoder = encoder;
        this.otpSender = otpSender;
        this.jwt = jwt;
    }

    // ---- Story 2.2: phone OTP -------------------------------------------------

    @Transactional
    public void requestOtp(String phone) {
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

    @Transactional
    public AuthResponse portalLogin(String email, String password) {
        List<Map<String, Object>> rows = jdbc.queryForList(
            "SELECT id, password_hash FROM app_user WHERE email = ? AND status = 'active'", email);
        if (rows.isEmpty() || rows.get(0).get("password_hash") == null
                || !encoder.matches(password, (String) rows.get(0).get("password_hash"))) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Invalid email or password.");
        }
        return issueTokensFor((UUID) rows.get(0).get("id"));
    }

    @Transactional
    public void requestPasswordReset(String email) {
        List<UUID> rows = jdbc.queryForList("SELECT id FROM app_user WHERE email = ?", UUID.class, email);
        if (!rows.isEmpty()) {
            String token = randomToken();
            jdbc.update("INSERT INTO password_reset (user_id, token_hash, expires_at) "
                + "VALUES (?, ?, now() + interval '30 minutes')", rows.get(0), sha256(token));
            log.warn("DEV password reset for {}: token {}  (dev-only)", email, token);
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
        jdbc.update("UPDATE app_user SET password_hash = ? WHERE id = ?", encoder.encode(newPassword), userId);
        jdbc.update("UPDATE password_reset SET consumed_at = now() WHERE id = ?", rows.get(0).get("id"));
        // Force re-login everywhere after a password change.
        jdbc.update("UPDATE refresh_token SET revoked_at = now() WHERE user_id = ? AND revoked_at IS NULL", userId);
    }

    // ---- Story 2.7: restricted registration -----------------------------------

    @Transactional
    public AuthResponse register(String email, String password, String role, String displayName) {
        String r = (role == null || role.isBlank()) ? "CUSTOMER" : role.toUpperCase();
        if (!SELF_REGISTERABLE.contains(r)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "You cannot self-register as " + r + ".");
        }
        if (!jdbc.queryForList("SELECT 1 FROM app_user WHERE email = ?", email).isEmpty()) {
            throw ApiException.badRequest("Email already registered.");
        }
        UUID id = jdbc.queryForObject(
            "INSERT INTO app_user (email, display_name, password_hash) VALUES (?, ?, ?) RETURNING id",
            UUID.class, email, displayName, encoder.encode(password));
        jdbc.update("INSERT INTO user_role (user_id, role) VALUES (?, ?)", id, r);
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
            // A revoked token presented again == replay/theft. Revoke the whole session family.
            jdbc.update("UPDATE refresh_token SET revoked_at = now() WHERE user_id = ? AND revoked_at IS NULL", userId);
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
        jdbc.update("UPDATE refresh_token SET revoked_at = now() WHERE token_hash = ? AND revoked_at IS NULL",
            sha256(rawToken));
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
