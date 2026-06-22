package com.grocerymart.api.catalog;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.identity.ApiException;

/**
 * Epic 3 core: store onboarding, free-create store products, the exact/fuzzy matching
 * pipeline to a shared canonical catalog, the human merge queue, and the cross-store
 * price comparison (the wedge). Matching bands (R12/R17): >= 0.95 auto-link,
 * 0.75-0.95 -> human candidate, < 0.75 -> new canonical.
 */
@Service
public class CatalogService {

    private static final double AUTO = 0.95;
    private static final double FUZZY = 0.75;

    private final JdbcTemplate jdbc;

    public CatalogService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    // ---- Stories 3.1 / 3.2: onboarding + approval ----

    @Transactional
    public UUID createShop(UUID ownerId, String name, List<String> cuisineTags) {
        String[] tags = cuisineTags == null ? new String[0] : cuisineTags.toArray(String[]::new);
        return jdbc.queryForObject(
            "INSERT INTO shop (owner_id, name, cuisine_tags) VALUES (?, ?, ?) RETURNING id",
            UUID.class, ownerId, name, tags);
    }

    @Transactional
    public void setShopStatus(UUID shopId, String status) {
        int n = jdbc.update("UPDATE shop SET status = ? WHERE id = ?", status, shopId);
        if (n == 0) {
            throw ApiException.badRequest("Shop not found.");
        }
    }

    // ---- Stories 3.4 / 3.5: free-create + matching ----

    @Transactional
    public Map<String, Object> createStoreProduct(UUID ownerId, String rawName, String rawBrand,
                                                   String rawSize, BigDecimal price, String currency, int stock) {
        UUID shopId = jdbc.query(
            "SELECT id FROM shop WHERE owner_id = ? AND status = 'active' ORDER BY created_at LIMIT 1",
            rs -> rs.next() ? (UUID) rs.getObject("id") : null, ownerId);
        if (shopId == null) {
            throw new ApiException(HttpStatus.FORBIDDEN, "You have no approved store yet.");
        }
        UUID storeProductId = jdbc.queryForObject(
            "INSERT INTO store_product (shop_id, raw_name, raw_brand, raw_size, price_amount, currency, stock) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id",
            UUID.class, shopId, rawName, rawBrand, rawSize, price, currency == null ? "AUD" : currency, stock);

        String key = normalize(rawBrand, rawName, rawSize);
        return runMatching(storeProductId, key, rawName, rawBrand, rawSize);
    }

    private Map<String, Object> runMatching(UUID storeProductId, String key,
                                            String rawName, String rawBrand, String rawSize) {
        // 1. exact normalized match
        UUID exact = jdbc.query("SELECT id FROM canonical_product WHERE match_key = ?",
            rs -> rs.next() ? (UUID) rs.getObject("id") : null, key);
        if (exact != null) {
            return link(storeProductId, exact, "auto_linked", 1.0, "system:exact", "auto_link");
        }
        // 2. fuzzy: best trigram match
        Map<String, Object> best = jdbc.query(
            "SELECT id, similarity(match_key, ?) AS sim FROM canonical_product ORDER BY sim DESC LIMIT 1",
            rs -> {
                if (!rs.next()) return null;
                return Map.of("id", rs.getObject("id"), "sim", rs.getDouble("sim"));
            }, key);
        if (best != null) {
            double sim = (Double) best.get("sim");
            UUID canonicalId = (UUID) best.get("id");
            if (sim >= AUTO) {
                return link(storeProductId, canonicalId, "auto_linked", sim, "system:fuzzy", "auto_link");
            }
            if (sim >= FUZZY) {
                jdbc.update("INSERT INTO product_match_candidate (store_product_id, canonical_product_id, similarity) "
                    + "VALUES (?, ?, ?)", storeProductId, canonicalId, sim);
                jdbc.update("UPDATE store_product SET match_status = 'candidate' WHERE id = ?", storeProductId);
                return Map.of("storeProductId", storeProductId.toString(), "matchStatus", "candidate",
                    "candidateCanonicalId", canonicalId.toString(), "similarity", round(sim));
            }
        }
        // 3. no good match -> new canonical
        UUID newCanonical = jdbc.queryForObject(
            "INSERT INTO canonical_product (name, brand, size_label, match_key) VALUES (?, ?, ?, ?) RETURNING id",
            UUID.class, rawName, rawBrand, rawSize, key);
        return link(storeProductId, newCanonical, "auto_linked", 1.0, "system:new", "auto_link");
    }

    private Map<String, Object> link(UUID storeProductId, UUID canonicalId, String matchStatus,
                                     double sim, String actor, String action) {
        jdbc.update("UPDATE store_product SET canonical_product_id = ?, match_status = ?, updated_at = now() WHERE id = ?",
            canonicalId, matchStatus, storeProductId);
        jdbc.update("INSERT INTO product_merge_log (store_product_id, canonical_product_id, action, similarity, actor) "
            + "VALUES (?, ?, ?, ?, ?)", storeProductId, canonicalId, action, sim, actor);
        return Map.of("storeProductId", storeProductId.toString(), "canonicalProductId", canonicalId.toString(),
            "matchStatus", matchStatus, "similarity", round(sim));
    }

    // ---- Story 3.7: admin merge queue ----

    public List<Map<String, Object>> mergeQueue() {
        return jdbc.queryForList(
            "SELECT c.id AS candidate_id, c.similarity, "
            + "sp.id AS store_product_id, sp.raw_brand, sp.raw_name, sp.raw_size, s.name AS shop_name, "
            + "cp.id AS canonical_id, cp.brand AS canonical_brand, cp.name AS canonical_name, cp.size_label AS canonical_size "
            + "FROM product_match_candidate c "
            + "JOIN store_product sp ON sp.id = c.store_product_id "
            + "JOIN shop s ON s.id = sp.shop_id "
            + "JOIN canonical_product cp ON cp.id = c.canonical_product_id "
            + "WHERE c.status = 'open' ORDER BY c.created_at");
    }

    @Transactional
    public void confirmCandidate(long candidateId, String actor) {
        Map<String, Object> c = jdbc.query(
            "SELECT store_product_id, canonical_product_id, similarity FROM product_match_candidate "
            + "WHERE id = ? AND status = 'open'",
            rs -> rs.next() ? Map.of(
                "sp", rs.getObject("store_product_id"),
                "cp", rs.getObject("canonical_product_id"),
                "sim", rs.getDouble("similarity")) : null, candidateId);
        if (c == null) {
            throw ApiException.badRequest("Candidate not found or already resolved.");
        }
        link((UUID) c.get("sp"), (UUID) c.get("cp"), "merged_confirmed", (Double) c.get("sim"), actor, "confirm_candidate");
        jdbc.update("UPDATE product_match_candidate SET status = 'confirmed' WHERE id = ?", candidateId);
    }

    // ---- The wedge: cross-store comparison + search ----

    public List<Map<String, Object>> offers(UUID canonicalId) {
        return jdbc.queryForList(
            "SELECT s.id AS shop_id, s.name AS shop_name, sp.price_amount, sp.currency, sp.stock "
            + "FROM store_product sp JOIN shop s ON s.id = sp.shop_id "
            + "WHERE sp.canonical_product_id = ? AND sp.match_status IN ('auto_linked','merged_confirmed') "
            + "AND s.status = 'active' ORDER BY sp.price_amount ASC", canonicalId);
    }

    public List<Map<String, Object>> searchCanonical(String q) {
        String key = normalize(q);
        return jdbc.queryForList(
            "SELECT id, brand, name, size_label, similarity(match_key, ?) AS sim FROM canonical_product "
            + "WHERE match_key % ? OR match_key ILIKE '%' || ? || '%' ORDER BY sim DESC LIMIT 20", key, key, key);
    }

    // ---- helpers ----

    private static String normalize(String... parts) {
        String joined = String.join(" ", Arrays.stream(parts).filter(Objects::nonNull).toList());
        return joined.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]+", " ").trim().replaceAll("\\s+", " ");
    }

    private static double round(double d) {
        return Math.round(d * 1000.0) / 1000.0;
    }
}
