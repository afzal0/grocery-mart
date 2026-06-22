package com.grocerymart.api.payments;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.delivery.DeliveryService;
import com.grocerymart.api.identity.ApiException;

/**
 * Epic 5 wallet: top-up via Stripe (Story 5.5, credited only by verified webhook) and pay-with-
 * wallet (Story 5.6, atomic FOR UPDATE debit, CHECK(balance>=0), idempotent per order). Append-only
 * ledger; never aggregates across currencies (AR-12).
 */
@Service
public class WalletService {

    private final JdbcTemplate jdbc;
    private final StripeStubProvider stripe;
    private final SettlementService settlement;
    private final DeliveryService delivery;

    public WalletService(JdbcTemplate jdbc, StripeStubProvider stripe, SettlementService settlement,
                         DeliveryService delivery) {
        this.jdbc = jdbc;
        this.stripe = stripe;
        this.settlement = settlement;
        this.delivery = delivery;
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> balances(UUID customerId) {
        return jdbc.query("SELECT currency, balance_amount FROM wallet WHERE customer_id = ? ORDER BY currency",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("currency", rs.getString("currency"));
                m.put("balance", rs.getBigDecimal("balance_amount"));
                return m;
            }, customerId);
    }

    /** Story 5.5 — start a top-up. Creates a Stripe PaymentIntent; balance is NOT credited yet. */
    @Transactional
    public Map<String, Object> startTopup(UUID customerId, BigDecimal amount, String currency) {
        if (amount == null || amount.signum() <= 0) throw ApiException.badRequest("amount must be positive");
        currency = currency.toUpperCase();
        getOrCreateWallet(customerId, currency);   // ensure the target balance row exists
        String intentId = stripe.createIntent(amount, currency, "topup");
        jdbc.update("INSERT INTO payment_intent (order_id, customer_id, purpose, provider_intent_id, "
            + "amount, currency, capture_method, status) VALUES (NULL, ?, 'wallet_topup', ?, ?, ?, "
            + "'automatic', 'requires_payment')",
            customerId, intentId, amount, currency);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("paymentIntentId", intentId);
        out.put("clientSecret", intentId + "_secret_dev");
        out.put("amount", amount);
        out.put("currency", currency);
        out.put("status", "requires_payment");
        return out;
    }

    /** Story 5.5 — webhook-driven credit. Called only by the verified, idempotent webhook handler. */
    @Transactional
    public void creditFromWebhook(String providerIntentId, String stripeEventId) {
        Map<String, Object> pi = jdbc.query(
            "SELECT customer_id, amount, currency, status FROM payment_intent "
            + "WHERE provider_intent_id = ? AND purpose = 'wallet_topup'",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("customer_id", rs.getObject("customer_id"));
                m.put("amount", rs.getBigDecimal("amount"));
                m.put("currency", rs.getString("currency"));
                m.put("status", rs.getString("status"));
                return m;
            }, providerIntentId);
        if (pi == null) return;                              // unknown intent — ignore safely
        if ("succeeded".equals(pi.get("status"))) return;    // already credited

        UUID customerId = (UUID) pi.get("customer_id");
        String currency = (String) pi.get("currency");
        BigDecimal amount = (BigDecimal) pi.get("amount");
        UUID walletId = getOrCreateWallet(customerId, currency);
        jdbc.update("INSERT INTO wallet_transaction (wallet_id, customer_id, type, amount, currency, reason, "
            + "stripe_event_id) VALUES (?, ?, 'credit', ?, ?, 'topup', ?)",
            walletId, customerId, amount, currency, stripeEventId);
        jdbc.update("UPDATE wallet SET balance_amount = balance_amount + ?, updated_at = now() WHERE id = ?",
            amount, walletId);
        jdbc.update("UPDATE payment_intent SET status = 'succeeded' WHERE provider_intent_id = ?", providerIntentId);
    }

    /** Story 5.6 — pay an order from the wallet: atomic, lock-serialized, idempotent. */
    @Transactional
    public Map<String, Object> payOrder(UUID customerId, UUID orderId) {
        Map<String, Object> order = lockableOrder(customerId, orderId);
        String status = (String) order.get("payment_status");
        if ("paid".equals(status)) return order;             // idempotent — already paid
        if (!"pending_payment".equals(status)) throw ApiException.unprocessable("order not payable");

        String currency = (String) order.get("currency");
        BigDecimal total = (BigDecimal) order.get("grand_total");
        UUID storeId = (UUID) order.get("store_id");

        UUID walletId = getOrCreateWallet(customerId, currency);
        BigDecimal balance = jdbc.queryForObject(
            "SELECT balance_amount FROM wallet WHERE id = ? FOR UPDATE", BigDecimal.class, walletId);
        if (balance.compareTo(total) < 0) {
            throw ApiException.unprocessable("insufficient wallet funds: have " + balance + " " + currency
                + ", need " + total);
        }

        // Re-validate + decrement stock under the same transaction.
        List<Map<String, Object>> items = jdbc.query(
            "SELECT store_product_id, qty FROM order_item WHERE order_id = ?",
            (rs, i) -> Map.of("sp", rs.getObject("store_product_id"), "qty", rs.getInt("qty")), orderId);
        for (Map<String, Object> it : items) {
            int updated = jdbc.update("UPDATE store_product SET stock = stock - ? WHERE id = ? AND stock >= ?",
                it.get("qty"), it.get("sp"), it.get("qty"));
            if (updated == 0) throw ApiException.unprocessable("insufficient stock at payment time");
        }

        try {
            jdbc.update("INSERT INTO wallet_transaction (wallet_id, customer_id, type, amount, currency, "
                + "reason, order_id) VALUES (?, ?, 'debit', ?, ?, 'order_payment', ?)",
                walletId, customerId, total, currency, orderId);
        } catch (DuplicateKeyException dup) {
            return lockableOrder(customerId, orderId);       // concurrent duplicate — already debited
        }
        jdbc.update("UPDATE wallet SET balance_amount = balance_amount - ?, updated_at = now() WHERE id = ?",
            total, walletId);
        jdbc.update("UPDATE orders SET payment_status = 'paid', payment_method = 'wallet', updated_at = now() "
            + "WHERE id = ?", orderId);
        settlement.recordCharge(orderId, storeId, total, (BigDecimal) order.get("gst_amount"), currency);
        delivery.onOrderPaid(orderId);   // immediate deliveries enter the dispatch queue
        return lockableOrder(customerId, orderId);
    }

    UUID getOrCreateWallet(UUID customerId, String currency) {
        UUID id = jdbc.query("SELECT id FROM wallet WHERE customer_id = ? AND currency = ?",
            rs -> rs.next() ? (UUID) rs.getObject("id") : null, customerId, currency);
        if (id != null) return id;
        try {
            return jdbc.queryForObject(
                "INSERT INTO wallet (customer_id, currency) VALUES (?, ?) RETURNING id",
                UUID.class, customerId, currency);
        } catch (DuplicateKeyException dup) {
            return jdbc.queryForObject("SELECT id FROM wallet WHERE customer_id = ? AND currency = ?",
                UUID.class, customerId, currency);
        }
    }

    private Map<String, Object> lockableOrder(UUID customerId, UUID orderId) {
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
        if (!customerId.equals(o.get("customer_id"))) throw ApiException.forbidden("not your order");
        return o;
    }
}
