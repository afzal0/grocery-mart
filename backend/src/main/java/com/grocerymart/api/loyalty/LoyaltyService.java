package com.grocerymart.api.loyalty;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.audit.AuditService;

/**
 * Loyalty credits: a promotional balance earned on every paid order, equal to that order's
 * {@code loyalty_credits} (computed at checkout from the spread between the price the customer was
 * charged and the price the fulfilling vendor is settled at).
 *
 * <p>Deliberately NOT the wallet — the wallet holds real money funded by verified Stripe webhooks
 * and can pay for orders. Credits currently have no spend path; redemption waits on a conversion
 * rate. Awards are idempotent via {@code ux_loyalty_txn_order_type}, matching the guarantee the
 * wallet gets from {@code ux_wallet_txn_order_reason}, so a redelivered webhook cannot double-credit.
 */
@Service
public class LoyaltyService {

    private final JdbcTemplate jdbc;
    private final AuditService audit;

    public LoyaltyService(JdbcTemplate jdbc, AuditService audit) {
        this.jdbc = jdbc;
        this.audit = audit;
    }

    /** Award an order's credits once it is paid. No-op when the order earned nothing. */
    @Transactional
    public void award(UUID orderId) {
        Map<String, Object> order = orderCredits(orderId);
        if (order == null) return;
        BigDecimal credits = (BigDecimal) order.get("credits");
        if (credits == null || credits.compareTo(BigDecimal.ZERO) <= 0) return;
        UUID customerId = (UUID) order.get("customer_id");

        UUID accountId = getOrCreateAccount(customerId);
        try {
            jdbc.update("INSERT INTO loyalty_transaction (account_id, customer_id, order_id, type, credits) "
                + "VALUES (?, ?, ?, 'earn', ?)", accountId, customerId, orderId, credits);
        } catch (DuplicateKeyException dup) {
            return;   // already awarded for this order — idempotent under webhook redelivery
        }
        jdbc.update("UPDATE loyalty_account SET balance_credits = balance_credits + ?, updated_at = now() "
            + "WHERE id = ?", credits, accountId);
        audit.log(customerId, "loyalty.award", "order", orderId.toString(), null,
            Map.of("credits", credits), "success");
    }

    /** Claw the credits back when an order is refunded. Idempotent; floors the balance at zero. */
    @Transactional
    public void reverse(UUID orderId) {
        Map<String, Object> order = orderCredits(orderId);
        if (order == null) return;
        BigDecimal credits = (BigDecimal) order.get("credits");
        if (credits == null || credits.compareTo(BigDecimal.ZERO) <= 0) return;
        UUID customerId = (UUID) order.get("customer_id");

        UUID accountId = getOrCreateAccount(customerId);
        try {
            jdbc.update("INSERT INTO loyalty_transaction (account_id, customer_id, order_id, type, credits) "
                + "VALUES (?, ?, ?, 'reverse', ?)", accountId, customerId, orderId, credits);
        } catch (DuplicateKeyException dup) {
            return;   // already reversed
        }
        // GREATEST keeps the CHECK (balance_credits >= 0) satisfied if credits were already spent
        // by a future redemption path; without it the refund would fail on a constraint violation.
        jdbc.update("UPDATE loyalty_account SET balance_credits = GREATEST(balance_credits - ?, 0), "
            + "updated_at = now() WHERE id = ?", credits, accountId);
        audit.log(customerId, "loyalty.reverse", "order", orderId.toString(), null,
            Map.of("credits", credits), "success");
    }

    /** Balance plus recent activity for the customer's rewards screen. */
    @Transactional(readOnly = true)
    public Map<String, Object> summary(UUID customerId) {
        BigDecimal balance = jdbc.query(
            "SELECT balance_credits FROM loyalty_account WHERE customer_id = ?",
            rs -> rs.next() ? rs.getBigDecimal(1) : BigDecimal.ZERO, customerId);

        List<Map<String, Object>> entries = jdbc.query(
            "SELECT order_id, type, credits, created_at FROM loyalty_transaction "
            + "WHERE customer_id = ? ORDER BY created_at DESC LIMIT 50",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("orderId", rs.getObject("order_id").toString());
                m.put("type", rs.getString("type"));
                m.put("credits", rs.getBigDecimal("credits"));
                m.put("createdAt", rs.getTimestamp("created_at").toInstant().toString());
                return m;
            }, customerId);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("balanceCredits", balance == null ? BigDecimal.ZERO : balance);
        out.put("redeemable", false);   // no conversion rate set yet
        out.put("entries", entries);
        return out;
    }

    private Map<String, Object> orderCredits(UUID orderId) {
        return jdbc.query("SELECT customer_id, loyalty_credits FROM orders WHERE id = ?",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("customer_id", rs.getObject("customer_id"));
                m.put("credits", rs.getBigDecimal("loyalty_credits"));
                return m;
            }, orderId);
    }

    UUID getOrCreateAccount(UUID customerId) {
        UUID id = jdbc.query("SELECT id FROM loyalty_account WHERE customer_id = ?",
            rs -> rs.next() ? (UUID) rs.getObject("id") : null, customerId);
        if (id != null) return id;
        try {
            return jdbc.queryForObject("INSERT INTO loyalty_account (customer_id) VALUES (?) RETURNING id",
                UUID.class, customerId);
        } catch (DuplicateKeyException dup) {
            return jdbc.queryForObject("SELECT id FROM loyalty_account WHERE customer_id = ?",
                UUID.class, customerId);
        }
    }
}
