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

import com.grocerymart.api.delivery.DeliveryService;
import com.grocerymart.api.identity.ApiException;
import com.grocerymart.api.ordering.OrderingDtos.CheckoutRequest;

/**
 * Epic 5 (Story 5.4): single-store checkout. Validates stock, rejects a closed store, snapshots
 * prices at placement, and creates exactly one order aggregate (no order_group) — idempotent on
 * the order:checkout key. Payment moves the order to paid via the wallet/card services. Also
 * creates the delivery aggregate + books any scheduled slot (Epic 6).
 */
@Service
public class OrderService {

    private final JdbcTemplate jdbc;
    private final CartService carts;
    private final DeliveryService delivery;

    public OrderService(JdbcTemplate jdbc, CartService carts, DeliveryService delivery) {
        this.jdbc = jdbc;
        this.carts = carts;
        this.delivery = delivery;
    }

    @Transactional
    public Map<String, Object> checkout(UUID customerId, UUID cartId, CheckoutRequest req, String idempotencyKey) {
        if (idempotencyKey == null || idempotencyKey.isBlank()) {
            throw ApiException.badRequest("Idempotency-Key header is required for checkout");
        }
        UUID existing = jdbc.query("SELECT id FROM orders WHERE idempotency_key = ?",
            rs -> rs.next() ? (UUID) rs.getObject("id") : null, idempotencyKey);
        if (existing != null) return orderView(customerId, existing);   // idempotent placement

        // Load + own the cart.
        Map<String, Object> cart = jdbc.query(
            "SELECT customer_id, store_id, currency FROM cart WHERE id = ?",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("customer_id", rs.getObject("customer_id"));
                m.put("store_id", rs.getObject("store_id"));
                m.put("currency", rs.getString("currency"));
                return m;
            }, cartId);
        if (cart == null) throw ApiException.notFound("cart not found");
        if (!customerId.equals(cart.get("customer_id"))) throw ApiException.forbidden("not your cart");
        UUID storeId = (UUID) cart.get("store_id");
        String currency = (String) cart.get("currency");

        // Store must be approved AND open at placement time.
        Map<String, Object> shop = jdbc.query(
            "SELECT status, is_open FROM shop WHERE id = ?",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("status", rs.getString("status"));
                m.put("is_open", rs.getBoolean("is_open"));
                return m;
            }, storeId);
        if (shop == null) throw ApiException.notFound("store not found");
        if (!"active".equals(shop.get("status")) || !Boolean.TRUE.equals(shop.get("is_open"))) {
            throw ApiException.unprocessable("store is closed");
        }

        // Re-validate stock and snapshot prices from the source of truth (store_product) at placement.
        List<Map<String, Object>> lines = jdbc.query(
            "SELECT cl.store_product_id, cl.canonical_product_id, cl.qty, sp.raw_name, sp.price_amount, "
            + "sp.currency, sp.stock FROM cart_line cl JOIN store_product sp ON sp.id = cl.store_product_id "
            + "WHERE cl.cart_id = ? ORDER BY cl.created_at",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("store_product_id", rs.getObject("store_product_id"));
                m.put("canonical_product_id", rs.getObject("canonical_product_id"));
                m.put("qty", rs.getInt("qty"));
                m.put("name", rs.getString("raw_name"));
                m.put("price", rs.getBigDecimal("price_amount"));
                m.put("currency", rs.getString("currency"));
                m.put("stock", rs.getInt("stock"));
                return m;
            }, cartId);
        if (lines.isEmpty()) throw ApiException.unprocessable("cart is empty");

        List<String> shortfalls = new ArrayList<>();
        BigDecimal subtotal = BigDecimal.ZERO;
        for (Map<String, Object> l : lines) {
            if (!currency.equalsIgnoreCase((String) l.get("currency"))) {
                throw ApiException.unprocessable("cross-currency line rejected");   // AR-12
            }
            int qty = (Integer) l.get("qty");
            if ((Integer) l.get("stock") < qty) shortfalls.add((String) l.get("name"));
            subtotal = subtotal.add(((BigDecimal) l.get("price")).multiply(BigDecimal.valueOf(qty)));
        }
        if (!shortfalls.isEmpty()) {
            throw ApiException.unprocessable("insufficient stock for: " + String.join(", ", shortfalls));
        }
        delivery.assertInRange(storeId, req.lat(), req.lng());   // Story 6.2: block out-of-range addresses

        Map<String, Object> totals = carts.totals(storeId, subtotal, currency, req.lat(), req.lng());
        UUID orderId = jdbc.queryForObject(
            "INSERT INTO orders (customer_id, store_id, currency, items_subtotal, delivery_fee, gst_amount, "
            + "grand_total, delivery_address, delivery_lat, delivery_lng, idempotency_key) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id",
            UUID.class, customerId, storeId, currency,
            totals.get("itemsSubtotal"), totals.get("deliveryFee"), totals.get("gstInclusive"),
            totals.get("grandTotal"), req.deliveryAddress(), req.lat(), req.lng(), idempotencyKey);

        for (Map<String, Object> l : lines) {
            jdbc.update("INSERT INTO order_item (order_id, store_product_id, canonical_product_id, "
                + "name_snapshot, qty, unit_price_amount, currency) VALUES (?, ?, ?, ?, ?, ?, ?)",
                orderId, l.get("store_product_id"), l.get("canonical_product_id"),
                l.get("name"), l.get("qty"), l.get("price"), currency);
        }

        // Create the delivery aggregate (+ book a scheduled slot atomically, Story 6.1).
        delivery.createForOrder(orderId, req.timing(), req.slotId() == null ? null : UUID.fromString(req.slotId()));

        jdbc.update("DELETE FROM cart WHERE id = ?", cartId);   // cart consumed by placement
        return orderView(customerId, orderId);
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> myOrders(UUID customerId) {
        return jdbc.query(
            "SELECT id, store_id, currency, payment_status, status, grand_total, created_at "
            + "FROM orders WHERE customer_id = ? ORDER BY created_at DESC",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("orderId", rs.getObject("id").toString());
                m.put("storeId", rs.getObject("store_id").toString());
                m.put("currency", rs.getString("currency"));
                m.put("paymentStatus", rs.getString("payment_status"));
                m.put("status", rs.getString("status"));
                m.put("grandTotal", rs.getBigDecimal("grand_total"));
                m.put("createdAt", rs.getTimestamp("created_at").toInstant().toString());
                return m;
            }, customerId);
    }

    @Transactional(readOnly = true)
    public Map<String, Object> getOrder(UUID customerId, UUID orderId) {
        return orderView(customerId, orderId);
    }

    Map<String, Object> orderView(UUID customerId, UUID orderId) {
        Map<String, Object> o = jdbc.query(
            "SELECT id, customer_id, store_id, currency, payment_status, status, items_subtotal, "
            + "delivery_fee, gst_amount, grand_total, delivery_address, payment_method, created_at "
            + "FROM orders WHERE id = ?",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("orderId", rs.getObject("id").toString());
                m.put("customerId", rs.getObject("customer_id"));
                m.put("storeId", rs.getObject("store_id").toString());
                m.put("currency", rs.getString("currency"));
                m.put("paymentStatus", rs.getString("payment_status"));
                m.put("status", rs.getString("status"));
                m.put("itemsSubtotal", rs.getBigDecimal("items_subtotal"));
                m.put("deliveryFee", rs.getBigDecimal("delivery_fee"));
                m.put("gstInclusive", rs.getBigDecimal("gst_amount"));
                m.put("grandTotal", rs.getBigDecimal("grand_total"));
                m.put("deliveryAddress", rs.getString("delivery_address"));
                m.put("paymentMethod", rs.getString("payment_method"));
                m.put("createdAt", rs.getTimestamp("created_at").toInstant().toString());
                return m;
            }, orderId);
        if (o == null) throw ApiException.notFound("order not found");
        if (customerId != null && !customerId.equals(o.get("customerId"))) {
            throw ApiException.forbidden("not your order");
        }
        o.remove("customerId");
        List<Map<String, Object>> items = jdbc.query(
            "SELECT name_snapshot, qty, unit_price_amount FROM order_item WHERE order_id = ?",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("name", rs.getString("name_snapshot"));
                m.put("qty", rs.getInt("qty"));
                m.put("unitPrice", rs.getBigDecimal("unit_price_amount"));
                return m;
            }, orderId);
        o.put("items", items);
        return o;
    }
}
