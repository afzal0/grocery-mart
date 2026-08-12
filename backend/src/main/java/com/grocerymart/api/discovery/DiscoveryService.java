package com.grocerymart.api.discovery;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import com.grocerymart.api.common.PricingService;

/**
 * Epic 4: near-me store discovery (PostGIS) and the single-store storefront. Only canonically
 * linked, in-stock products are listed.
 *
 * <p>Storefront prices are NORMALIZED: what the customer sees is the highest price for that
 * product among the stores near them, never this store's own price when a dearer one exists
 * nearby. The store's real price stays server-side (it is what the vendor is settled at), so
 * this class must never put both numbers in the same response.
 */
@Service
public class DiscoveryService {

    private final JdbcTemplate jdbc;
    private final PricingService pricing;

    public DiscoveryService(JdbcTemplate jdbc, PricingService pricing) {
        this.jdbc = jdbc;
        this.pricing = pricing;
    }

    /** Active stores within radius (metres) of (lat,lng), optionally filtered by cuisine tag.
     *  Includes the store's aggregate rating so the customer home can show it on each card. */
    public List<Map<String, Object>> nearbyShops(double lat, double lng, double radiusMeters, String cuisine) {
        String sql = "SELECT s.id, s.name, s.cuisine_tags, s.address, "
            + "ST_Distance(s.location, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography) AS distance_m, "
            + "sra.avg_rating, sra.review_count "
            + "FROM shop s LEFT JOIN store_rating_aggregate sra ON sra.shop_id = s.id "
            + "WHERE s.status = 'active' AND s.location IS NOT NULL "
            + "AND ST_DWithin(s.location, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?) "
            + (cuisine != null ? "AND ? = ANY(s.cuisine_tags) " : "")
            + "ORDER BY distance_m";
        Object[] args = cuisine != null
            ? new Object[] { lng, lat, lng, lat, radiusMeters, cuisine }
            : new Object[] { lng, lat, lng, lat, radiusMeters };
        return jdbc.query(sql, (rs, i) -> {
            Map<String, Object> m = new HashMap<>();
            m.put("shopId", rs.getObject("id").toString());
            m.put("name", rs.getString("name"));
            m.put("address", rs.getString("address") == null ? "" : rs.getString("address"));
            m.put("cuisineTags", List.of((Object[]) rs.getArray("cuisine_tags").getArray()));
            m.put("distanceM", Math.round(rs.getDouble("distance_m")));
            java.math.BigDecimal avg = rs.getBigDecimal("avg_rating");
            m.put("rating", avg == null ? null : avg);
            m.put("reviewCount", rs.getInt("review_count"));
            return m;
        }, args);
    }

    /**
     * One store's in-stock, canonically-linked products with category and product rating.
     *
     * <p>{@code price} is the customer-facing display price when coordinates are supplied — the
     * maximum across stores in their radius, floored at this store's own price. Without
     * coordinates it degrades to the store's own price (nothing to normalize against).
     */
    public List<Map<String, Object>> storeProducts(UUID shopId, Double lat, Double lng) {
        List<Map<String, Object>> rows = jdbc.query(
            "SELECT sp.id AS store_product_id, sp.canonical_product_id, sp.raw_name, sp.raw_brand, "
            + "sp.raw_size, sp.price_amount, sp.currency, sp.stock, cp.category, "
            + "pra.avg_rating, pra.review_count "
            + "FROM store_product sp JOIN canonical_product cp ON cp.id = sp.canonical_product_id "
            + "LEFT JOIN product_rating_aggregate pra ON pra.canonical_product_id = sp.canonical_product_id "
            + "WHERE sp.shop_id = ? AND sp.match_status IN ('auto_linked','merged_confirmed') AND sp.stock > 0 "
            + "ORDER BY cp.category, sp.raw_name",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("storeProductId", rs.getObject("store_product_id").toString());
                m.put("canonicalProductId", rs.getObject("canonical_product_id").toString());
                m.put("name", rs.getString("raw_name"));
                m.put("brand", rs.getString("raw_brand"));
                m.put("size", rs.getString("raw_size"));
                m.put("price", rs.getBigDecimal("price_amount"));
                m.put("currency", rs.getString("currency"));
                m.put("stock", rs.getInt("stock"));
                m.put("category", rs.getString("category"));
                m.put("rating", rs.getBigDecimal("avg_rating"));
                m.put("reviewCount", rs.getInt("review_count"));
                return m;
            }, shopId);

        List<UUID> canonicalIds = new ArrayList<>();
        for (Map<String, Object> m : rows) {
            canonicalIds.add(UUID.fromString((String) m.get("canonicalProductId")));
        }
        Map<UUID, BigDecimal> maxima = pricing.displayPrices(canonicalIds, lat, lng);
        for (Map<String, Object> m : rows) {
            UUID cid = UUID.fromString((String) m.get("canonicalProductId"));
            // Overwrite in place: the store's own price must not leave the server.
            m.put("price", pricing.displayPrice((BigDecimal) m.get("price"), maxima.get(cid)));
        }
        return rows;
    }
}
