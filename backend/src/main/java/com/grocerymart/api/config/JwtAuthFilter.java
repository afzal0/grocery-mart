package com.grocerymart.api.config;

import java.io.IOException;
import java.util.List;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import com.grocerymart.api.identity.JwtService;

import io.jsonwebtoken.Claims;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * Validates a {@code Authorization: Bearer <jwt>} access token and populates the
 * SecurityContext with the user id + role authorities. Invalid/absent tokens simply
 * leave the request unauthenticated (deny-by-default handles authorization).
 *
 * <p>L-2: a token is also rejected if it was issued before the user's {@code tokens_valid_from}
 * cutoff (bumped on logout / password reset / refresh-reuse), so those events immediately revoke
 * every outstanding stateless access token for that user.
 */
@Component
public class JwtAuthFilter extends OncePerRequestFilter {

    private final JwtService jwt;
    private final JdbcTemplate jdbc;

    public JwtAuthFilter(JwtService jwt, JdbcTemplate jdbc) {
        this.jwt = jwt;
        this.jdbc = jdbc;
    }

    @Override
    @SuppressWarnings("unchecked")
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            try {
                Claims claims = jwt.parse(header.substring(7));
                if (isRevoked(claims)) {
                    chain.doFilter(request, response);   // token revoked by logout/reset -> unauthenticated
                    return;
                }
                List<String> roles = claims.get("roles", List.class);
                var authorities = (roles == null ? List.<String>of() : roles).stream()
                    .map(r -> new SimpleGrantedAuthority("ROLE_" + r))
                    .toList();
                var authentication = new UsernamePasswordAuthenticationToken(claims.getSubject(), null, authorities);
                SecurityContextHolder.getContext().setAuthentication(authentication);
            } catch (Exception ignored) {
                // invalid/expired token -> remain unauthenticated
            }
        }
        chain.doFilter(request, response);
    }

    /** True if the token's issued-at predates the user's tokens_valid_from cutoff. Compares in epoch
     *  SECONDS (timezone-proof — no Timestamp binding) with 1s grace so a freshly-issued token is
     *  never falsely rejected while any token issued >1s before a logout/reset cutoff is revoked.
     *  Fails OPEN on a transient DB error (token already passed signature+expiry) so auth survives blips. */
    private boolean isRevoked(Claims claims) {
        try {
            UUID userId = UUID.fromString(claims.getSubject());
            long iatEpoch = claims.getIssuedAt() == null ? 0L : claims.getIssuedAt().toInstant().getEpochSecond();
            Integer valid = jdbc.query(
                "SELECT 1 FROM app_user WHERE id = ? AND extract(epoch from tokens_valid_from) <= ? + 1",
                rs -> rs.next() ? 1 : null, userId, iatEpoch);
            return valid == null;
        } catch (IllegalArgumentException e) {
            return true;    // non-UUID subject -> not a legitimate token
        } catch (Exception e) {
            return false;   // DB hiccup -> do not lock everyone out
        }
    }
}
