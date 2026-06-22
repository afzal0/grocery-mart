package com.grocerymart.api.reviews;

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
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.identity.ApiException;
import com.grocerymart.api.notifications.OutboxService;

/**
 * Epic 7 (Stories 7.1–7.3): purchase-gated reviews on canonical products. Create/update/delete
 * append a Review* outbox event in the same transaction so the rating read-model can recompute.
 */
@Service
public class ReviewService {

    private final JdbcTemplate jdbc;
    private final OutboxService outbox;

    public ReviewService(JdbcTemplate jdbc, OutboxService outbox) {
        this.jdbc = jdbc;
        this.outbox = outbox;
    }

    @Transactional
    public Map<String, Object> create(UUID customerId, UUID canonicalId, int rating, String body) {
        requirePurchase(customerId, canonicalId);
        UUID id;
        try {
            id = jdbc.queryForObject(
                "INSERT INTO reviews (canonical_product_id, customer_id, rating, body) VALUES (?, ?, ?, ?) RETURNING id",
                UUID.class, canonicalId, customerId, rating, body);
        } catch (DuplicateKeyException dup) {
            throw ApiException.conflict("you have already reviewed this product");
        }
        outbox.emit("review", canonicalId, "ReviewCreated", Map.of("canonicalProductId", canonicalId.toString()));
        return Map.of("reviewId", id.toString(), "rating", rating);
    }

    @Transactional
    public void update(UUID customerId, UUID reviewId, Integer rating, String body) {
        Map<String, Object> r = owned(customerId, reviewId);
        UUID canonicalId = (UUID) r.get("canonical_product_id");
        int newRating = rating != null ? rating : (Integer) r.get("rating");
        jdbc.update("UPDATE reviews SET rating = ?, body = COALESCE(?, body), updated_at = now() WHERE id = ?",
            newRating, body, reviewId);
        outbox.emit("review", canonicalId, "ReviewUpdated", Map.of("canonicalProductId", canonicalId.toString()));
    }

    @Transactional
    public void delete(UUID customerId, UUID reviewId) {
        Map<String, Object> r = owned(customerId, reviewId);
        UUID canonicalId = (UUID) r.get("canonical_product_id");
        jdbc.update("UPDATE reviews SET deleted_at = now() WHERE id = ?", reviewId);
        outbox.emit("review", canonicalId, "ReviewDeleted", Map.of("canonicalProductId", canonicalId.toString()));
    }

    /** Cursor-paginated, newest-first reviews for a canonical product (Story 7.3). */
    @Transactional(readOnly = true)
    public Map<String, Object> list(UUID canonicalId, String cursor, int limit) {
        int lim = Math.min(Math.max(limit, 1), 100);
        StringBuilder sql = new StringBuilder(
            "SELECT r.id, r.rating, r.body, r.created_at, u.display_name FROM reviews r "
            + "JOIN app_user u ON u.id = r.customer_id WHERE r.canonical_product_id = ? AND r.deleted_at IS NULL ");
        Object[] args;
        if (cursor != null && !cursor.isBlank()) {
            String[] p = new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8).split("\\|");
            Timestamp ct = Timestamp.from(Instant.ofEpochMilli(Long.parseLong(p[0])));
            UUID cid = UUID.fromString(p[1]);
            sql.append("AND (r.created_at, r.id) < (?, ?) ");
            args = new Object[] { canonicalId, ct, cid, lim + 1 };
        } else {
            args = new Object[] { canonicalId, lim + 1 };
        }
        sql.append("ORDER BY r.created_at DESC, r.id DESC LIMIT ?");
        List<Map<String, Object>> rows = jdbc.query(sql.toString(), (rs, i) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("reviewId", rs.getObject("id").toString());
            m.put("rating", rs.getInt("rating"));
            m.put("body", rs.getString("body"));
            m.put("author", mask(rs.getString("display_name")));
            m.put("createdAt", rs.getTimestamp("created_at").toInstant().toString());
            m.put("_ts", rs.getTimestamp("created_at").getTime());
            return m;
        }, args);

        String nextCursor = null;
        if (rows.size() > lim) {
            Map<String, Object> boundary = rows.get(lim - 1);
            nextCursor = Base64.getUrlEncoder().withoutPadding().encodeToString(
                (boundary.get("_ts") + "|" + boundary.get("reviewId")).getBytes(StandardCharsets.UTF_8));
            rows = rows.subList(0, lim);
        }
        rows.forEach(r -> r.remove("_ts"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("items", rows);
        out.put("nextCursor", nextCursor);
        return out;
    }

    // ---- helpers ---------------------------------------------------------------------------
    private void requirePurchase(UUID customerId, UUID canonicalId) {
        Integer ok = jdbc.query(
            "SELECT 1 FROM orders o JOIN order_item oi ON oi.order_id = o.id JOIN delivery d ON d.order_id = o.id "
            + "WHERE o.customer_id = ? AND oi.canonical_product_id = ? AND d.state = 'delivered' LIMIT 1",
            rs -> rs.next() ? 1 : null, customerId, canonicalId);
        if (ok == null) {
            throw new ApiException(org.springframework.http.HttpStatus.FORBIDDEN,
                "you can only review a product you have purchased and received");
        }
    }

    private Map<String, Object> owned(UUID customerId, UUID reviewId) {
        Map<String, Object> r = jdbc.query(
            "SELECT customer_id, canonical_product_id, rating FROM reviews WHERE id = ? AND deleted_at IS NULL",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("customer_id", rs.getObject("customer_id"));
                m.put("canonical_product_id", rs.getObject("canonical_product_id"));
                m.put("rating", rs.getInt("rating"));
                return m;
            }, reviewId);
        if (r == null) throw ApiException.notFound("review not found");
        if (!customerId.equals(r.get("customer_id"))) throw ApiException.forbidden("not your review");
        return r;
    }

    private static String mask(String name) {
        if (name == null || name.isBlank()) return "Anonymous";
        return name.substring(0, 1).toUpperCase() + "***";
    }
}
