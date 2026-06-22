package com.grocerymart.api.notifications;

import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/**
 * In-app notification store. The Epic 7 outbox consumer creates rows here (deduped on the outbox
 * event id) and reads/marks the per-user inbox with keyset pagination + unread count.
 */
@Service
public class NotificationService {

    private final JdbcTemplate jdbc;

    public NotificationService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** Synchronous in-app push (used where no outbox event exists). */
    public void push(UUID userId, String type, String title, String body, UUID orderId) {
        jdbc.update("INSERT INTO notification (user_id, type, title, body, order_id) VALUES (?, ?, ?, ?, ?)",
            userId, type, title, body, orderId);
    }

    /** Outbox-driven create, idempotent on (user, eventId). Returns true if newly created. */
    public boolean createDeduped(UUID userId, UUID eventId, String type, String category,
                                 String title, String body, String dataJson, UUID orderId) {
        try {
            jdbc.update("INSERT INTO notification (user_id, event_id, type, category, title, body, data_json, order_id) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?::jsonb, ?)",
                userId, eventId, type, category, title, body, dataJson, orderId);
            return true;
        } catch (DuplicateKeyException dup) {
            return false;   // already created for this event (at-least-once redelivery)
        }
    }

    /** Keyset (created_at, id) inbox, newest-first, with unread count. */
    public Map<String, Object> inbox(UUID userId, String cursor, int limit) {
        int lim = Math.min(Math.max(limit, 1), 100);
        StringBuilder sql = new StringBuilder(
            "SELECT id, type, title, body, order_id, category, read_at, created_at FROM notification WHERE user_id = ? ");
        Object[] args;
        Timestamp ct = null; UUID cid = null;
        if (cursor != null && !cursor.isBlank()) {
            String[] parts = new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8).split("\\|");
            ct = Timestamp.from(Instant.ofEpochMilli(Long.parseLong(parts[0])));
            cid = UUID.fromString(parts[1]);
            sql.append("AND (created_at, id) < (?, ?) ");
            args = new Object[] { userId, ct, cid, lim + 1 };
        } else {
            args = new Object[] { userId, lim + 1 };
        }
        sql.append("ORDER BY created_at DESC, id DESC LIMIT ?");
        List<Map<String, Object>> rows = jdbc.query(sql.toString(), (rs, i) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", rs.getObject("id").toString());
            m.put("type", rs.getString("type"));
            m.put("title", rs.getString("title"));
            m.put("body", rs.getString("body"));
            m.put("category", rs.getString("category"));
            m.put("orderId", rs.getObject("order_id") == null ? null : rs.getObject("order_id").toString());
            m.put("read", rs.getTimestamp("read_at") != null);
            m.put("createdAt", rs.getTimestamp("created_at").toInstant().toString());
            m.put("_ts", rs.getTimestamp("created_at").getTime());
            return m;
        }, args);

        String nextCursor = null;
        if (rows.size() > lim) {
            Map<String, Object> boundary = rows.get(lim - 1);   // last item we actually return
            nextCursor = Base64.getUrlEncoder().withoutPadding().encodeToString(
                (boundary.get("_ts") + "|" + boundary.get("id")).getBytes(StandardCharsets.UTF_8));
            rows = rows.subList(0, lim);
        }
        rows.forEach(r -> r.remove("_ts"));
        Integer unread = jdbc.queryForObject(
            "SELECT count(*) FROM notification WHERE user_id = ? AND read_at IS NULL", Integer.class, userId);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("items", rows);
        out.put("nextCursor", nextCursor);
        out.put("unreadCount", unread);
        return out;
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

    public void markAllRead(UUID userId) {
        jdbc.update("UPDATE notification SET read_at = now() WHERE user_id = ? AND read_at IS NULL", userId);
    }

    public void markOneRead(UUID userId, UUID notificationId) {
        jdbc.update("UPDATE notification SET read_at = now() WHERE id = ? AND user_id = ? AND read_at IS NULL",
            notificationId, userId);
    }
}
