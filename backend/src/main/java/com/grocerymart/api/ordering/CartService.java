package com.grocerymart.api.ordering;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.common.PricingService;
import com.grocerymart.api.identity.ApiException;
import com.grocerymart.api.ordering.OrderingDtos.ResolveCartRequest;
import com.grocerymart.api.ordering.OrderingDtos.ResolveItem;

/**
 * Epic 5 (Stories 5.1–5.3): resolve a compared basket into a single-store cart, edit & re-validate
 * it against live availability, and compose a transparent total. A cart is bound to ONE store and
 * ONE currency; nothing here aggregates across currencies (AR-12).
 */
@Service
public class CartService {

    private static final List<String> LINKED = List.of("auto_linked", "merged_confirmed");

    private final JdbcTemplate jdbc;
    private final PricingService pricing;

    public CartService(JdbcTemplate jdbc, PricingService pricing) {
        this.jdbc = jdbc;
        this.pricing = pricing;
    }

    /** Story 5.1 — resolve to a single-store cart. Idempotent per (customer, store): re-resolving
     *  replaces the existing cart rather than spawning a duplicate. */
    @Transactional
    public Map<String, Object> resolveCart(UUID customerId, ResolveCartRequest req) {
        UUID storeId = UUID.fromString(req.storeId());
        String currency = req.currency().toUpperCase();

        Integer shopOk = jdbc.query("SELECT 1 FROM shop WHERE id = ? AND status = 'active'",
            rs -> rs.next() ? 1 : null, storeId);
        if (shopOk == null) throw ApiException.notFound("store not found or not active");

        // Refresh idempotently: drop any existing cart for this customer+store first.
        jdbc.update("DELETE FROM cart WHERE customer_id = ? AND store_id = ?", customerId, storeId);
        UUID cartId = jdbc.queryForObject(
            "INSERT INTO cart (customer_id, store_id, currency) VALUES (?, ?, ?) RETURNING id",
            UUID.class, customerId, storeId, currency);

        List<String> missing = new ArrayList<>();
        for (ResolveItem it : req.items()) {
            Map<String, Object> sp;
            boolean substitution = it.substituteStoreProductId() != null && !it.substituteStoreProductId().isBlank();
            if (substitution) {
                sp = loadStoreProduct(UUID.fromString(it.substituteStoreProductId()), storeId);
                if (sp == null) { missing.add(it.canonicalProductId()); continue; }
            } else {
                sp = loadStoreProductByCanonical(storeId, UUID.fromString(it.canonicalProductId()));
                if (sp == null) { missing.add(it.canonicalProductId()); continue; }   // not offered here
            }
            String spCurrency = (String) sp.get("currency");
            if (!spCurrency.equalsIgnoreCase(currency)) {
                throw ApiException.unprocessable("cross-currency basket rejected: line is " + spCurrency
                    + " but cart is " + currency);   // AR-12
            }
            jdbc.update("INSERT INTO cart_line (cart_id, store_product_id, canonical_product_id, qty, "
                + "unit_price_amount, currency, is_substitution) VALUES (?, ?, ?, ?, ?, ?, ?) "
                + "ON CONFLICT (cart_id, store_product_id) DO UPDATE SET qty = cart_line.qty + EXCLUDED.qty",
                cartId, sp.get("id"), sp.get("canonical_product_id"), it.quantity(),
                sp.get("price_amount"), spCurrency, substitution);
        }
        return cartView(customerId, cartId, missing);
    }

    @Transactional(readOnly = true)
    public Map<String, Object> getCart(UUID customerId, UUID cartId) {
        return cartView(customerId, cartId, List.of());
    }

    /** Story 5.2 — change quantity; re-validate against current stock. */
    @Transactional
    public Map<String, Object> updateLine(UUID customerId, UUID cartId, UUID lineId, int qty) {
        if (qty <= 0) throw ApiException.badRequest("quantity must be positive; remove the line to delete it");
        ownedCart(customerId, cartId);
        int n = jdbc.update("UPDATE cart_line SET qty = ? WHERE id = ? AND cart_id = ?", qty, lineId, cartId);
        if (n == 0) throw ApiException.notFound("cart line not found");
        touch(cartId);
        return cartView(customerId, cartId, List.of());
    }

    /** Story 5.2 — remove a line; an empty cart cannot be checked out. */
    @Transactional
    public Map<String, Object> removeLine(UUID customerId, UUID cartId, UUID lineId) {
        ownedCart(customerId, cartId);
        int n = jdbc.update("DELETE FROM cart_line WHERE id = ? AND cart_id = ?", lineId, cartId);
        if (n == 0) throw ApiException.notFound("cart line not found");
        touch(cartId);
        return cartView(customerId, cartId, List.of());
    }

    /** Story 5.3 — transparent total: items subtotal + distance delivery fee, with the
     *  tax-inclusive GST component, all in the cart's single active currency. */
    @Transactional(readOnly = true)
    public Map<String, Object> composeTotal(UUID customerId, UUID cartId, Double lat, Double lng) {
        Map<String, Object> cart = ownedCart(customerId, cartId);
        String currency = (String) cart.get("currency");
        UUID storeId = (UUID) cart.get("store_id");
        BigDecimal subtotal = jdbc.queryForObject(
            "SELECT COALESCE(SUM(unit_price_amount * qty), 0) FROM cart_line WHERE cart_id = ?",
            BigDecimal.class, cartId);
        return totals(storeId, subtotal, currency, lat, lng);
    }

    // ---- shared total composition (used by ordering too) -----------------------------------
    Map<String, Object> totals(UUID storeId, BigDecimal subtotal, String currency, Double lat, Double lng) {
        subtotal = subtotal.setScale(2, java.math.RoundingMode.HALF_UP);
        BigDecimal deliveryFee = pricing.deliveryFee(storeId, lat, lng);
        BigDecimal grand = subtotal.add(deliveryFee);
        BigDecimal gst = pricing.gstInclusive(grand);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("currency", currency);
        m.put("itemsSubtotal", subtotal);
        m.put("deliveryFee", deliveryFee);
        m.put("gstInclusive", gst);     // component already inside grandTotal, not added on top
        m.put("grandTotal", grand);
        return m;
    }

    // ---- helpers ---------------------------------------------------------------------------
    private Map<String, Object> loadStoreProduct(UUID storeProductId, UUID storeId) {
        return jdbc.query(
            "SELECT id, canonical_product_id, raw_name, price_amount, currency, stock FROM store_product "
            + "WHERE id = ? AND shop_id = ? AND stock > 0",
            rs -> rs.next() ? row(rs) : null, storeProductId, storeId);
    }

    private Map<String, Object> loadStoreProductByCanonical(UUID storeId, UUID canonicalId) {
        return jdbc.query(
            "SELECT id, canonical_product_id, raw_name, price_amount, currency, stock FROM store_product "
            + "WHERE shop_id = ? AND canonical_product_id = ? AND match_status IN ('auto_linked','merged_confirmed') "
            + "AND stock > 0 ORDER BY price_amount ASC LIMIT 1",
            rs -> rs.next() ? row(rs) : null, storeId, canonicalId);
    }

    private Map<String, Object> row(java.sql.ResultSet rs) throws java.sql.SQLException {
        Map<String, Object> m = new java.util.HashMap<>();
        m.put("id", rs.getObject("id"));
        m.put("canonical_product_id", rs.getObject("canonical_product_id"));
        m.put("raw_name", rs.getString("raw_name"));
        m.put("price_amount", rs.getBigDecimal("price_amount"));
        m.put("currency", rs.getString("currency"));
        m.put("stock", rs.getInt("stock"));
        return m;
    }

    private Map<String, Object> ownedCart(UUID customerId, UUID cartId) {
        Map<String, Object> cart = jdbc.query(
            "SELECT id, customer_id, store_id, currency FROM cart WHERE id = ?",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("id", rs.getObject("id"));
                m.put("customer_id", rs.getObject("customer_id"));
                m.put("store_id", rs.getObject("store_id"));
                m.put("currency", rs.getString("currency"));
                return m;
            }, cartId);
        if (cart == null) throw ApiException.notFound("cart not found");
        if (!customerId.equals(cart.get("customer_id"))) throw ApiException.forbidden("not your cart");
        return cart;
    }

    private void touch(UUID cartId) {
        jdbc.update("UPDATE cart SET updated_at = now() WHERE id = ?", cartId);
    }

    /** Cart view with per-line availability re-validation and a checkout-ready flag. */
    private Map<String, Object> cartView(UUID customerId, UUID cartId, List<String> missing) {
        Map<String, Object> cart = ownedCart(customerId, cartId);
        String currency = (String) cart.get("currency");
        UUID storeId = (UUID) cart.get("store_id");

        List<Map<String, Object>> lines = jdbc.query(
            "SELECT cl.id, cl.store_product_id, cl.canonical_product_id, cl.qty, cl.unit_price_amount, "
            + "cl.is_substitution, sp.raw_name, sp.stock FROM cart_line cl "
            + "JOIN store_product sp ON sp.id = cl.store_product_id WHERE cl.cart_id = ? ORDER BY cl.created_at",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                int qty = rs.getInt("qty");
                int stock = rs.getInt("stock");
                m.put("lineId", rs.getObject("id").toString());
                m.put("storeProductId", rs.getObject("store_product_id").toString());
                m.put("name", rs.getString("raw_name"));
                m.put("qty", qty);
                m.put("unitPrice", rs.getBigDecimal("unit_price_amount"));
                m.put("lineTotal", rs.getBigDecimal("unit_price_amount").multiply(BigDecimal.valueOf(qty)));
                m.put("isSubstitution", rs.getBoolean("is_substitution"));
                m.put("available", stock >= qty);
                m.put("stock", stock);
                return m;
            }, cartId);

        boolean allAvailable = lines.stream().allMatch(l -> (Boolean) l.get("available"));
        boolean checkoutReady = !lines.isEmpty() && allAvailable;
        BigDecimal subtotal = lines.stream()
            .map(l -> (BigDecimal) l.get("lineTotal"))
            .reduce(BigDecimal.ZERO, BigDecimal::add)
            .setScale(2, java.math.RoundingMode.HALF_UP);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("cartId", cartId.toString());
        out.put("storeId", storeId.toString());
        out.put("currency", currency);
        out.put("lines", lines);
        out.put("itemsSubtotal", subtotal);
        out.put("missingItems", missing);
        out.put("checkoutReady", checkoutReady);
        return out;
    }
}
