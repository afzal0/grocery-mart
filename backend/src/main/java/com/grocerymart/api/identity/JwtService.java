package com.grocerymart.api.identity;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.List;

import javax.crypto.SecretKey;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

/**
 * Issues and verifies HS512 access tokens. The signing key comes from {@code JWT_SECRET}
 * (>= 32 bytes; >= 64 recommended for HS512). If {@code JWT_SECRET} is unset or still the old
 * placeholder, the service signs with a RANDOM, ephemeral per-boot key rather than a publicly-known
 * value — so a misconfigured environment fails safe (tokens just don't survive a restart) instead of
 * being forgeable with the committed default.
 */
@Service
public class JwtService {

    private static final Logger log = LoggerFactory.getLogger(JwtService.class);

    private final SecretKey key;
    private final Duration accessTtl = Duration.ofMinutes(15);

    public JwtService(@Value("${JWT_SECRET:}") String secret) {
        if (secret == null || secret.isBlank() || secret.contains("change-me")) {
            byte[] ephemeral = new byte[64];
            new SecureRandom().nextBytes(ephemeral);
            this.key = Keys.hmacShaKeyFor(ephemeral);
            log.warn("JWT_SECRET is not configured; signing with a random ephemeral key (DEV ONLY). "
                + "Set a >= 64-byte JWT_SECRET in any real environment.");
            return;
        }
        if (secret.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException(
                "JWT_SECRET is too short; provide at least 32 bytes (>= 64 recommended for HS512).");
        }
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
    }

    public String issueAccessToken(String userId, List<String> roles) {
        Instant now = Instant.now();
        return Jwts.builder()
            .subject(userId)
            .claim("roles", roles)
            .issuedAt(Date.from(now))
            .expiration(Date.from(now.plus(accessTtl)))
            .signWith(key)
            .compact();
    }

    /** Verifies signature + expiry; throws JwtException if invalid. */
    public Claims parse(String token) {
        return Jwts.parser().verifyWith(key).build().parseSignedClaims(token).getPayload();
    }
}
