package com.grocerymart.api.identity;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.identity.AuthDtos.AuthResponse;

/** Phone-OTP sign-in (Story 2.2) over the identity tables. Uses JdbcTemplate to avoid
 *  coupling the auth flow to JPA entities at this stage. */
@Service
public class AuthService {

    private static final int MAX_ATTEMPTS = 5;

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

    @Transactional
    public void requestOtp(String phone) {
        String code = String.format("%06d", random.nextInt(1_000_000));
        jdbc.update(
            "INSERT INTO otp_challenge (phone, code_hash, expires_at) VALUES (?, ?, now() + interval '5 minutes')",
            phone, encoder.encode(code));
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
        int attempts = ((Number) row.get("attempts")).intValue();
        if (attempts >= MAX_ATTEMPTS) {
            throw ApiException.badRequest("Too many attempts. Please request a new OTP.");
        }
        if (!encoder.matches(code, (String) row.get("code_hash"))) {
            jdbc.update("UPDATE otp_challenge SET attempts = attempts + 1 WHERE id = ?", challengeId);
            throw ApiException.badRequest("Invalid code.");
        }
        jdbc.update("UPDATE otp_challenge SET consumed_at = now() WHERE id = ?", challengeId);

        UUID userId = findOrCreateCustomer(phone);
        List<String> roles = jdbc.queryForList("SELECT role FROM user_role WHERE user_id = ?", String.class, userId);
        String access = jwt.issueAccessToken(userId.toString(), roles);
        String refresh = issueRefreshToken(userId);
        return new AuthResponse(access, refresh, userId.toString(), phone, roles);
    }

    private UUID findOrCreateCustomer(String phone) {
        List<UUID> existing = jdbc.queryForList("SELECT id FROM app_user WHERE phone = ?", UUID.class, phone);
        if (!existing.isEmpty()) {
            return existing.get(0);
        }
        UUID id = jdbc.queryForObject("INSERT INTO app_user (phone) VALUES (?) RETURNING id", UUID.class, phone);
        jdbc.update("INSERT INTO user_role (user_id, role) VALUES (?, 'CUSTOMER')", id);
        return id;
    }

    private String issueRefreshToken(UUID userId) {
        byte[] buf = new byte[32];
        random.nextBytes(buf);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(buf);
        jdbc.update(
            "INSERT INTO refresh_token (user_id, token_hash, expires_at) VALUES (?, ?, now() + interval '30 days')",
            userId, sha256(token));
        return token;
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
