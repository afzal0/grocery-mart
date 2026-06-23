package com.grocerymart.api.config;

import java.io.IOException;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * Epic 9 (Story 9.13): per-principal/IP sliding-window rate limit. Over the limit returns 429 with
 * an RFC 9457 problem+json body and no internals. Keyed by the JWT subject when present, else client IP.
 */
@Component
@Order(1)
public class RateLimitFilter extends OncePerRequestFilter {

    private final int limit;
    private final Map<String, Deque<Long>> hits = new ConcurrentHashMap<>();

    public RateLimitFilter(@Value("${grocerymart.ratelimit.requests-per-minute}") int limit) {
        this.limit = limit;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String key = principalKey(request);
        long now = System.currentTimeMillis();
        Deque<Long> q = hits.computeIfAbsent(key, k -> new ArrayDeque<>());
        synchronized (q) {
            while (!q.isEmpty() && now - q.peekFirst() > 60_000) q.pollFirst();
            if (q.size() >= limit) {
                response.setStatus(429);
                response.setContentType("application/problem+json");
                response.getWriter().write(
                    "{\"type\":\"about:blank\",\"title\":\"Too Many Requests\",\"status\":429,"
                    + "\"detail\":\"rate limit exceeded; retry later\"}");
                return;
            }
            q.addLast(now);
        }
        chain.doFilter(request, response);
    }

    private String principalKey(HttpServletRequest req) {
        String h = req.getHeader("Authorization");
        if (h != null && h.startsWith("Bearer ")) {
            try {
                String payload = h.substring(7).split("\\.")[1];
                byte[] json = java.util.Base64.getUrlDecoder().decode(payload);
                int i = new String(json).indexOf("\"sub\":\"");
                if (i >= 0) return "u:" + new String(json).substring(i + 7, new String(json).indexOf('"', i + 7));
            } catch (Exception ignored) { /* fall through to IP */ }
        }
        return "ip:" + clientIp(req);
    }

    /**
     * Resolves the client IP for rate-limiting. A reverse proxy (Render's edge) APPENDS the real
     * peer to X-Forwarded-For, so the proxy-added value is the LAST entry; the leftmost entries are
     * attacker-controllable. Taking the last entry prevents the trivial "rotate X-Forwarded-For to
     * get a fresh bucket per request" brute-force bypass. Falls back to the TCP peer when no XFF.
     */
    private String clientIp(HttpServletRequest req) {
        String fwd = req.getHeader("X-Forwarded-For");
        if (fwd == null || fwd.isBlank()) return req.getRemoteAddr();
        String[] parts = fwd.split(",");
        return parts[parts.length - 1].trim();
    }
}
