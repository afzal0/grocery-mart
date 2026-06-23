package com.grocerymart.api.config;

import java.util.List;
import java.util.UUID;
import java.util.regex.Pattern;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.MessagingException;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.stereotype.Component;

import com.grocerymart.api.identity.JwtService;

import io.jsonwebtoken.Claims;

/**
 * Authenticates the STOMP {@code CONNECT} frame with a Bearer JWT and authorizes each
 * {@code SUBSCRIBE} so only the order's customer, assigned driver, owning shop owner, or an
 * admin may receive live driver GPS on {@code /topic/orders/{orderId}/tracking}. Without this,
 * the tracking topic is anonymously subscribable (driver-GPS / address disclosure). Mirrors the
 * REST authorization in {@code DeliveryService.tracking()}. Uses JdbcTemplate directly (not
 * DeliveryService) to avoid a bean cycle with the broker's messaging template.
 */
@Component
public class StompAuthChannelInterceptor implements ChannelInterceptor {

    private static final Pattern TRACK =
        Pattern.compile("^/topic/orders/([0-9a-fA-F-]{36})/tracking$");

    private final JwtService jwt;
    private final JdbcTemplate jdbc;

    public StompAuthChannelInterceptor(JwtService jwt, JdbcTemplate jdbc) {
        this.jwt = jwt;
        this.jdbc = jdbc;
    }

    @Override
    public Message<?> preSend(Message<?> message, MessageChannel channel) {
        StompHeaderAccessor acc = MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);
        if (acc == null || acc.getCommand() == null) return message;

        switch (acc.getCommand()) {
            case CONNECT -> {
                UsernamePasswordAuthenticationToken auth = authenticate(acc);
                if (auth == null) throw new MessagingException("Unauthorized: missing or invalid token");
                acc.setUser(auth);
            }
            case SUBSCRIBE -> {
                if (!(acc.getUser() instanceof UsernamePasswordAuthenticationToken auth)) {
                    throw new MessagingException("Unauthorized");
                }
                String dest = acc.getDestination();
                var m = dest == null ? null : TRACK.matcher(dest);
                if (m == null || !m.matches()) {
                    throw new MessagingException("Forbidden: subscription destination not allowed");
                }
                if (!canTrack(auth, UUID.fromString(m.group(1)))) {
                    throw new MessagingException("Forbidden: not allowed to track this order");
                }
            }
            default -> { /* SEND/DISCONNECT/etc. — no extra checks */ }
        }
        return message;
    }

    private UsernamePasswordAuthenticationToken authenticate(StompHeaderAccessor acc) {
        List<String> headers = acc.getNativeHeader("Authorization");
        String header = (headers == null || headers.isEmpty()) ? null : headers.get(0);
        if (header == null || !header.startsWith("Bearer ")) return null;
        try {
            Claims claims = jwt.parse(header.substring(7));
            @SuppressWarnings("unchecked")
            List<String> roles = claims.get("roles", List.class);
            var authorities = (roles == null ? List.<String>of() : roles).stream()
                .map(r -> new SimpleGrantedAuthority("ROLE_" + r))
                .toList();
            return new UsernamePasswordAuthenticationToken(claims.getSubject(), null, authorities);
        } catch (Exception e) {
            return null;
        }
    }

    /** True if the principal is an admin, or the order's customer / assigned driver / owning shop. */
    private boolean canTrack(UsernamePasswordAuthenticationToken auth, UUID orderId) {
        boolean isAdmin = auth.getAuthorities().stream()
            .anyMatch(a -> "ROLE_ADMIN".equals(a.getAuthority()));
        if (isAdmin) return true;
        UUID uid;
        try {
            uid = UUID.fromString(auth.getName());
        } catch (IllegalArgumentException e) {
            return false;
        }
        Integer ok = jdbc.query(
            "SELECT 1 FROM orders o "
            + "LEFT JOIN delivery d ON d.order_id = o.id "
            + "LEFT JOIN shop s ON s.id = d.shop_id "
            + "WHERE o.id = ? AND (o.customer_id = ? OR d.driver_id = ? OR s.owner_id = ?) LIMIT 1",
            rs -> rs.next() ? 1 : null, orderId, uid, uid, uid);
        return ok != null;
    }
}
