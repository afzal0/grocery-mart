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

import com.grocerymart.api.identity.ApiException;

/**
 * Epic 5 (Story 5.10): full refund/cancel — refund by the original method, reverse settlement, and
 * restock. Wallet refunds complete synchronously; card refunds are finalized by the verified webhook
 * (idempotent on the Stripe event id). All idempotent; never converts across currencies (AR-12).
 */
@Service
public class RefundService {

    private final JdbcTemplate jdbc;
    private final StripeStubProvider stripe;
    private final WalletService wallet;
    private final SettlementService settlement;

    public RefundService(JdbcTemplate jdbc, StripeStubProvider stripe, WalletService wallet,
                         SettlementService settlement) {
        this.jdbc = jdbc;
        this.stripe = stripe;
        this.wallet = wallet;
        this.settlement = settlement;
    }

    /** Customer (own order) or admin initiates a full refund/cancel. */
    @Transactional
    public Map<String, Object> refund(UUID actorId, boolean isAdmin, UUID orderId) {
        Map<String, Object> o = order(orderId);
        if (!isAdmin && !actorId.equals(o.get("customer_id"))) throw ApiException.forbidden("not your order");

        String paymentStatus = (String) o.get("payment_status");
        if ("refunded".equals(paymentStatus)) return view(orderId);                 // idempotent
        if (!"paid".equals(paymentStatus)) {
            throw ApiException.unprocessable("order is not in a refundable (paid) state");
        }
        String method = (String) o.get("payment_method");
        BigDecimal total = (BigDecimal) o.get("grand_total");
        String currency = (String) o.get("currency");

        if ("wallet".equals(method)) {
            UUID walletId = wallet.getOrCreateWallet((UUID) o.get("customer_id"), currency);
            try {
                jdbc.update("INSERT INTO wallet_transaction (wallet_id, customer_id, type, amount, currency, "
                    + "reason, order_id) VALUES (?, ?, 'credit', ?, ?, 'refund', ?)",
                    walletId, o.get("customer_id"), total, currency, orderId);
            } catch (DuplicateKeyException dup) {
                return view(orderId);                                               // already refunded
            }
            jdbc.update("UPDATE wallet SET balance_amount = balance_amount + ?, updated_at = now() WHERE id = ?",
                total, walletId);
            restockAndReverse(orderId, o, total, currency);
            return view(orderId);
        }

        // Card: ask Stripe for a refund; the verified webhook finalizes restock/reversal/state.
        var pi = jdbc.query("SELECT provider_intent_id FROM payment_intent WHERE order_id = ? AND purpose = 'order' "
            + "AND status = 'captured' ORDER BY created_at DESC LIMIT 1",
            rs -> rs.next() ? rs.getString(1) : null, orderId);
        if (pi == null) throw ApiException.unprocessable("no captured card payment to refund");
        stripe.refund(pi, total, currency);
        Map<String, Object> out = view(orderId);
        out.put("refund", "pending_webhook");
        return out;
    }

    /** Webhook `charge.refunded` for a card order: restock + reverse settlement + mark refunded. */
    @Transactional
    public void finalizeCardRefund(String providerIntentId) {
        UUID orderId = jdbc.query("SELECT order_id FROM payment_intent WHERE provider_intent_id = ? AND purpose = 'order'",
            rs -> rs.next() ? (UUID) rs.getObject("order_id") : null, providerIntentId);
        if (orderId == null) return;
        Map<String, Object> o = order(orderId);
        if ("refunded".equals(o.get("payment_status"))) return;                    // idempotent
        if (!"paid".equals(o.get("payment_status"))) return;
        restockAndReverse(orderId, o, (BigDecimal) o.get("grand_total"), (String) o.get("currency"));
    }

    private void restockAndReverse(UUID orderId, Map<String, Object> o, BigDecimal total, String currency) {
        List<Map<String, Object>> items = jdbc.query(
            "SELECT store_product_id, qty FROM order_item WHERE order_id = ?",
            (rs, i) -> Map.of("sp", (UUID) rs.getObject("store_product_id"), "qty", rs.getInt("qty")), orderId);
        for (Map<String, Object> it : items) {
            jdbc.update("UPDATE store_product SET stock = stock + ? WHERE id = ?", it.get("qty"), it.get("sp"));
        }
        jdbc.update("UPDATE stock_reservation SET status = 'released' WHERE order_id = ? AND status <> 'released'", orderId);
        settlement.recordReversal(orderId, (UUID) o.get("store_id"), total, (BigDecimal) o.get("gst_amount"), currency);
        jdbc.update("UPDATE orders SET payment_status = 'refunded', status = 'cancelled', updated_at = now() "
            + "WHERE id = ?", orderId);
    }

    private Map<String, Object> order(UUID orderId) {
        Map<String, Object> o = jdbc.query(
            "SELECT customer_id, store_id, currency, payment_status, payment_method, grand_total, gst_amount "
            + "FROM orders WHERE id = ?",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("customer_id", rs.getObject("customer_id"));
                m.put("store_id", rs.getObject("store_id"));
                m.put("currency", rs.getString("currency"));
                m.put("payment_status", rs.getString("payment_status"));
                m.put("payment_method", rs.getString("payment_method"));
                m.put("grand_total", rs.getBigDecimal("grand_total"));
                m.put("gst_amount", rs.getBigDecimal("gst_amount"));
                return m;
            }, orderId);
        if (o == null) throw ApiException.notFound("order not found");
        return o;
    }

    private Map<String, Object> view(UUID orderId) {
        Map<String, Object> o = order(orderId);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("orderId", orderId.toString());
        out.put("paymentStatus", o.get("payment_status"));
        out.put("status", jdbc.queryForObject("SELECT status FROM orders WHERE id = ?", String.class, orderId));
        return out;
    }
}
