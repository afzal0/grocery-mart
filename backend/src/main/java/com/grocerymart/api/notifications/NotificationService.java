package com.grocerymart.api.notifications;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/**
 * In-app notifications. Delivery dual-notify (Epic 6) and review/order events (Epic 7) write here;
 * the FCM push transport is layered on in Epic 7. Customer/driver/shop read their own feed.
 */
@Service
public class NotificationService {

    private final JdbcTemplate jdbc;

    public NotificationService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void push(UUID userId, String type, String title, String body, UUID orderId) {
        jdbc.update("INSERT INTO notification (user_id, type, title, body, order_id) VALUES (?, ?, ?, ?, ?)",
            userId, type, title, body, orderId);
    }

    public List<Map<String, Object>> feed(UUID userId) {
        return jdbc.query("SELECT id, type, title, body, order_id, read_at, created_at FROM notification "
            + "WHERE user_id = ? ORDER BY created_at DESC LIMIT 100",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("id", rs.getObject("id").toString());
                m.put("type", rs.getString("type"));
                m.put("title", rs.getString("title"));
                m.put("body", rs.getString("body"));
                m.put("orderId", rs.getObject("order_id") == null ? null : rs.getObject("order_id").toString());
                m.put("read", rs.getTimestamp("read_at") != null);
                m.put("createdAt", rs.getTimestamp("created_at").toInstant().toString());
                return m;
            }, userId);
    }

    public void markRead(UUID userId) {
        jdbc.update("UPDATE notification SET read_at = now() WHERE user_id = ? AND read_at IS NULL", userId);
    }
}
