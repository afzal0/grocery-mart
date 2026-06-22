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

import com.grocerymart.api.discovery.DiscoveryDtos.BasketItem;

/**
 * Epic 4: near-me store discovery (PostGIS) + whole-basket price comparison ranked by
 * cheapest fully-available store. Only canonically-linked, in-stock products count.
 */
@Service
public class DiscoveryService {

    private final JdbcTemplate jdbc;

    public DiscoveryService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** Active stores within radius (metres) of (lat,lng), optionally filtered by cuisine tag. */
    public List<Map<String, Object>> nearbyShops(double lat, double lng, double radiusMeters, String cuisine) {
        String sql = "SELECT id, name, cuisine_tags, address, "
            + "ST_Distance(location, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography) AS distance_m "
            + "FROM shop WHERE status = 'active' AND location IS NOT NULL "
            + "AND ST_DWithin(location, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?) "
            + (cuisine != null ? "AND ? = ANY(cuisine_tags) " : "")
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
            return m;
        }, args);
    }

    /** Compute each nearby store's total for the basket; rank cheapest fully-available first. */
    public Map<String, Object> compareBasket(double lat, double lng, double radiusMeters, List<BasketItem> items) {
        LinkedHashMap<UUID, Integer> qty = new LinkedHashMap<>();
        for (BasketItem it : items) {
            qty.merge(UUID.fromString(it.canonicalProductId()), Math.max(1, it.quantity()), Integer::sum);
        }
        int basketSize = qty.size();
        String idsCsv = String.join(",", qty.keySet().stream().map(UUID::toString).toList());

        List<Map<String, Object>> stores = new ArrayList<>();
        for (Map<String, Object> shop : nearbyShops(lat, lng, radiusMeters, null)) {
            UUID shopId = UUID.fromString((String) shop.get("shopId"));
            Map<UUID, BigDecimal> priceByCanonical = new HashMap<>();
            jdbc.query(
                "SELECT canonical_product_id, price_amount FROM store_product "
                + "WHERE shop_id = ? AND canonical_product_id = ANY(string_to_array(?, ',')::uuid[]) "
                + "AND match_status IN ('auto_linked','merged_confirmed') AND stock > 0",
                rs -> { priceByCanonical.put((UUID) rs.getObject("canonical_product_id"), rs.getBigDecimal("price_amount")); },
                shopId, idsCsv);

            BigDecimal total = BigDecimal.ZERO;
            int missing = 0;
            for (Map.Entry<UUID, Integer> e : qty.entrySet()) {
                BigDecimal price = priceByCanonical.get(e.getKey());
                if (price == null) {
                    missing++;
                } else {
                    total = total.add(price.multiply(BigDecimal.valueOf(e.getValue())));
                }
            }
            boolean fully = missing == 0;
            Map<String, Object> row = new HashMap<>();
            row.put("shopId", shopId.toString());
            row.put("shopName", shop.get("name"));
            row.put("distanceM", shop.get("distanceM"));
            row.put("itemsAvailable", basketSize - missing);
            row.put("itemsTotal", basketSize);
            row.put("fullyAvailable", fully);
            row.put("missingCount", missing);
            row.put("basketTotal", fully ? total.toString() : null);   // items-only total (R11)
            stores.add(row);
        }

        // Rank: fully-available first, then cheapest; incomplete stores by most-available.
        stores.sort((a, b) -> {
            boolean fa = (Boolean) a.get("fullyAvailable");
            boolean fb = (Boolean) b.get("fullyAvailable");
            if (fa != fb) return fa ? -1 : 1;
            if (fa) return new BigDecimal((String) a.get("basketTotal")).compareTo(new BigDecimal((String) b.get("basketTotal")));
            return Integer.compare((Integer) b.get("itemsAvailable"), (Integer) a.get("itemsAvailable"));
        });

        Map<String, Object> result = new HashMap<>();
        result.put("basketItems", basketSize);
        result.put("stores", stores);
        return result;
    }
}
