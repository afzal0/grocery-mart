package com.grocerymart.api.identity;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.List;

import javax.crypto.SecretKey;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

/** Issues and verifies HS256 access tokens. Secret comes from JWT_SECRET (>= 32 bytes). */
@Service
public class JwtService {

    private final SecretKey key;
    private final Duration accessTtl = Duration.ofMinutes(15);

    public JwtService(@Value("${JWT_SECRET:change-me-dev-only-not-for-production-please}") String secret) {
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
