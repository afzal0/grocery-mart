package com.grocerymart.api.payments;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.delivery.DeliveryService;
import com.grocerymart.api.identity.ApiException;

/**
 * Epic 5 (Story 5.7): card payment with manual capture — authorize → reserve stock → capture.
 * State only advances via the verified webhook (NFR-SEC-04); there is no client-asserted confirm.
 * If stock can't be reserved after authorization, the auth is voided and the customer is not charged.
 */
@Service
public class CardPaymentService {

    private final JdbcTemplate jdbc;
    private final StripeStubProvider stripe;
    private final SettlementService settlement;
    private final DeliveryService delivery;
    private final int reservationTtlMinutes;

    public CardPaymentService(JdbcTemplate jdbc, StripeStubProvider stripe, SettlementService settlement,
                              DeliveryService delivery,
                              @Value("${grocerymart.payments.reservation-ttl-minutes}") int reservationTtlMinutes) {
        this.jdbc = jdbc;
        this.stripe = stripe;
        this.settlement = settlement;
        this.delivery = delivery;
        this.reservationTtlMinutes = reservationTtlMinutes;
    }

    /** Start a card payment: create a manual-capture PaymentIntent (Stripe-hosted entry). */
    @Transactional
    public Map<String, Object> startCardPayment(UUID customerId, UUID orderId) {
        Map<String, Object> order = order(orderId);
        if (!customerId.equals(order.get("customer_id"))) throw ApiException.forbidden("not your order");
        if (!"pending_payment".equals(order.get("payment_status"))) {
            throw ApiException.unprocessable("order not payable");
        }
        BigDecimal total = (BigDecimal) order.get("grand_total");
        String currency = (String) order.get("currency");
        String intentId = stripe.createIntent(total, currency, "order");
        jdbc.update("INSERT INTO payment_intent (order_id, customer_id, purpose, provider_intent_id, amount, "
            + "currency, capture_method, status) VALUES (?, ?, 'order', ?, ?, ?, 'manual', 'requires_payment')",
            orderId, customerId, intentId, total, currency);
        jdbc.update("UPDATE orders SET payment_method = 'card', updated_at = now() WHERE id = ?", orderId);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("paymentIntentId", intentId);
        out.put("clientSecret", intentId + "_secret_dev");
        out.put("amount", total);
        out.put("currency", currency);
        out.put("status", "requires_payment");
        return out;
    }

    /** Webhook `amount_capturable_updated`: authorization succeeded → reserve stock, then request capture.
     *  If reservation fails (sold out since checkout), void the authorization — no capture, no charge. */
    @Transactional
    public void authorizeAndReserve(String providerIntentId) {
        Map<String, Object> pi = intent(providerIntentId);
        if (pi == null || !"order".equals(pi.get("purpose"))) return;
        UUID orderId = (UUID) pi.get("order_id");
        if (!"requires_payment".equals(pi.get("status"))) return;   // already authorized/captured/voided
        Map<String, Object> order = order(orderId);
        if (!"pending_payment".equals(order.get("payment_status"))) return;

        List<Map<String, Object>> items = jdbc.query(
            "SELECT store_product_id, qty FROM order_item WHERE order_id = ?",
            (rs, i) -> Map.of("sp", (UUID) rs.getObject("store_product_id"), "qty", rs.getInt("qty")), orderId);

        List<Map<String, Object>> reserved = new ArrayList<>();
        boolean ok = true;
        for (Map<String, Object> it : items) {
            int n = jdbc.update("UPDATE store_product SET stock = stock - ? WHERE id = ? AND stock >= ?",
                it.get("qty"), it.get("sp"), it.get("qty"));
            if (n == 0) { ok = false; break; }
            reserved.add(it);
        }
        if (!ok) {
            for (Map<String, Object> it : reserved) {   // undo partial decrements
                jdbc.update("UPDATE store_product SET stock = stock + ? WHERE id = ?", it.get("qty"), it.get("sp"));
            }
            stripe.cancel(providerIntentId);
            jdbc.update("UPDATE payment_intent SET status = 'canceled' WHERE provider_intent_id = ?", providerIntentId);
            return;   // not charged; order stays pending_payment
        }

        OffsetDateTime expires = OffsetDateTime.now().plusMinutes(reservationTtlMinutes);
        for (Map<String, Object> it : items) {
            jdbc.update("INSERT INTO stock_reservation (order_id, store_product_id, qty, status, expires_at) "
                + "VALUES (?, ?, ?, 'reserved', ?)", orderId, it.get("sp"), it.get("qty"), expires);
        }
        jdbc.update("UPDATE payment_intent SET status = 'authorized' WHERE provider_intent_id = ?", providerIntentId);
        stripe.capture(providerIntentId);   // request capture; Stripe will emit payment_intent.succeeded
    }

    /** Webhook `payment_intent.succeeded`: capture confirmed → finalize the order (paid) + settlement. */
    @Transactional
    public void finalizeCapture(String providerIntentId) {
        Map<String, Object> pi = intent(providerIntentId);
        if (pi == null || !"order".equals(pi.get("purpose"))) return;
        if ("canceled".equals(pi.get("status"))) return;            // auth was voided; nothing to capture
        UUID orderId = (UUID) pi.get("order_id");
        Map<String, Object> order = order(orderId);
        if ("paid".equals(order.get("payment_status"))) return;     // idempotent

        jdbc.update("UPDATE stock_reservation SET status = 'captured' WHERE order_id = ? AND status = 'reserved'", orderId);
        jdbc.update("UPDATE payment_intent SET status = 'captured' WHERE provider_intent_id = ?", providerIntentId);
        jdbc.update("UPDATE orders SET payment_status = 'paid', payment_method = 'card', updated_at = now() "
            + "WHERE id = ?", orderId);
        settlement.recordCharge(orderId, (UUID) order.get("store_id"),
            (BigDecimal) order.get("grand_total"), (BigDecimal) order.get("gst_amount"), (String) order.get("currency"));
        delivery.onOrderPaid(orderId);   // immediate deliveries enter the dispatch queue
    }

    // ---- helpers ---------------------------------------------------------------------------
    Map<String, Object> intent(String providerIntentId) {
        return jdbc.query("SELECT order_id, customer_id, purpose, status FROM payment_intent "
            + "WHERE provider_intent_id = ?",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("order_id", rs.getObject("order_id"));
                m.put("customer_id", rs.getObject("customer_id"));
                m.put("purpose", rs.getString("purpose"));
                m.put("status", rs.getString("status"));
                return m;
            }, providerIntentId);
    }

    private Map<String, Object> order(UUID orderId) {
        Map<String, Object> o = jdbc.query(
            "SELECT customer_id, store_id, currency, payment_status, grand_total, gst_amount FROM orders WHERE id = ?",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("customer_id", rs.getObject("customer_id"));
                m.put("store_id", rs.getObject("store_id"));
                m.put("currency", rs.getString("currency"));
                m.put("payment_status", rs.getString("payment_status"));
                m.put("grand_total", rs.getBigDecimal("grand_total"));
                m.put("gst_amount", rs.getBigDecimal("gst_amount"));
                return m;
            }, orderId);
        if (o == null) throw ApiException.notFound("order not found");
        return o;
    }
}
