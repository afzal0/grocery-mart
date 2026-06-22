package com.grocerymart.api.reviews;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Epic 7 (Story 7.4): rating read-model. Recompute is idempotent — derived from current reviews
 * rows, not incremental deltas — so at-least-once outbox redelivery yields the same aggregate.
 */
@Service
public class RatingService {

    private final JdbcTemplate jdbc;

    public RatingService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** Recompute the product aggregate and every store aggregate that stocks this canonical. */
    @Transactional
    public void recompute(UUID canonicalId) {
        jdbc.update(
            "INSERT INTO product_rating_aggregate (canonical_product_id, avg_rating, review_count, updated_at) "
            + "SELECT ?, COALESCE(ROUND(AVG(rating)::numeric, 1), 0), COUNT(*), now() "
            + "FROM reviews WHERE canonical_product_id = ? AND deleted_at IS NULL "
            + "ON CONFLICT (canonical_product_id) DO UPDATE SET avg_rating = EXCLUDED.avg_rating, "
            + "review_count = EXCLUDED.review_count, updated_at = now()",
            canonicalId, canonicalId);

        List<UUID> shops = jdbc.queryForList(
            "SELECT DISTINCT shop_id FROM store_product WHERE canonical_product_id = ?", UUID.class, canonicalId);
        for (UUID shopId : shops) {
            jdbc.update(
                "INSERT INTO store_rating_aggregate (shop_id, avg_rating, review_count, updated_at) "
                + "SELECT ?, COALESCE(ROUND(AVG(r.rating)::numeric, 1), 0), COUNT(*), now() "
                + "FROM store_product sp JOIN reviews r ON r.canonical_product_id = sp.canonical_product_id "
                + "AND r.deleted_at IS NULL WHERE sp.shop_id = ? "
                + "ON CONFLICT (shop_id) DO UPDATE SET avg_rating = EXCLUDED.avg_rating, "
                + "review_count = EXCLUDED.review_count, updated_at = now()",
                shopId, shopId);
        }
    }

    @Transactional(readOnly = true)
    public Map<String, Object> productRating(UUID canonicalId) {
        return read("SELECT avg_rating, review_count FROM product_rating_aggregate WHERE canonical_product_id = ?",
            canonicalId);
    }

    @Transactional(readOnly = true)
    public Map<String, Object> storeRating(UUID shopId) {
        return read("SELECT avg_rating, review_count FROM store_rating_aggregate WHERE shop_id = ?", shopId);
    }

    private Map<String, Object> read(String sql, UUID id) {
        Map<String, Object> agg = jdbc.query(sql, rs -> {
            if (!rs.next()) return null;
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("avgRating", rs.getBigDecimal("avg_rating"));
            m.put("reviewCount", rs.getInt("review_count"));
            return m;
        }, id);
        if (agg == null || (Integer) agg.get("reviewCount") == 0) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("avgRating", null);
            m.put("reviewCount", 0);
            m.put("message", "no ratings yet");
            return m;
        }
        return agg;
    }
}
