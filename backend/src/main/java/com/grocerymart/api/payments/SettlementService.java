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
 */
@Service
public class SettlementService {

    private final JdbcTemplate jdbc;

    public SettlementService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** Write the single charge entry for a paid order. Safe to call again (no-op on redelivery). */
    public void recordCharge(UUID orderId, UUID storeId, BigDecimal orderTotal, BigDecimal gst, String currency) {
        insert(orderId, storeId, "charge", orderTotal, gst, currency);
    }

    /** Write the offsetting reversal entry on refund. Idempotent. */
    public void recordReversal(UUID orderId, UUID storeId, BigDecimal orderTotal, BigDecimal gst, String currency) {
        insert(orderId, storeId, "reversal", orderTotal.negate(), gst.negate(), currency);
    }

    private void insert(UUID orderId, UUID storeId, String type, BigDecimal total, BigDecimal gst, String currency) {
        try {
            jdbc.update("INSERT INTO settlement_ledger (order_id, store_id, entry_type, order_total, "
                + "gst_amount, platform_fee, currency) VALUES (?, ?, ?, ?, ?, 0, ?)",
                orderId, storeId, type, total, gst, currency);
        } catch (DuplicateKeyException dup) {
            // already recorded for this (order, type) — idempotent
        }
    }
}
