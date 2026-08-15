package com.grocerymart.api.payments;

import java.math.BigDecimal;
import java.util.UUID;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/**
 * Epic 5 (Story 5.9): per-store settlement ledger. Exactly one 'charge' entry is written when an
 * order becomes paid and exactly one 'reversal' on refund — both idempotent via the UNIQUE
 * (order_id, entry_type) index. Every entry stays in its own order currency (AR-12).
 *
 * <p>{@code platform_fee} is the platform's total take on the order:
 * <pre>(items_subtotal − store_items_subtotal) + orders.platform_fee</pre>
 * i.e. the price-normalization margin plus the flat service fee. It is derived here, from the
 * order row, rather than passed in by each caller — one derivation means the wallet, card and
 * refund paths cannot drift apart. Downstream reporting already treats this column as commission,
 * so the existing identity holds: {@code net = gross − platform_fee − refunds}, leaving the vendor
 * their own prices plus the delivery fee.
 */
@Service
public class SettlementService {

    private final JdbcTemplate jdbc;

    public SettlementService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** Write the single charge entry for a paid order. Safe to call again (no-op on redelivery). */
    public void recordCharge(UUID orderId, UUID storeId, BigDecimal orderTotal, BigDecimal gst, String currency) {
        insert(orderId, storeId, "charge", orderTotal, gst, platformTake(orderId), currency);
    }

    /** Write the offsetting reversal entry on refund. Idempotent. */
    public void recordReversal(UUID orderId, UUID storeId, BigDecimal orderTotal, BigDecimal gst, String currency) {
        insert(orderId, storeId, "reversal", orderTotal.negate(), gst.negate(), platformTake(orderId).negate(),
            currency);
    }

    /** Normalization margin + flat service fee for this order; zero if the order vanished. */
    private BigDecimal platformTake(UUID orderId) {
        BigDecimal take = jdbc.query(
            "SELECT (items_subtotal - store_items_subtotal) + platform_fee FROM orders WHERE id = ?",
            rs -> rs.next() ? rs.getBigDecimal(1) : null, orderId);
        return take == null ? BigDecimal.ZERO : take.setScale(2, java.math.RoundingMode.HALF_UP);
    }

    private void insert(UUID orderId, UUID storeId, String type, BigDecimal total, BigDecimal gst,
                        BigDecimal platformFee, String currency) {
        try {
            jdbc.update("INSERT INTO settlement_ledger (order_id, store_id, entry_type, order_total, "
                + "gst_amount, platform_fee, currency) VALUES (?, ?, ?, ?, ?, ?, ?)",
                orderId, storeId, type, total, gst, platformFee, currency);
        } catch (DuplicateKeyException dup) {
            // already recorded for this (order, type) — idempotent
        }
    }
}
