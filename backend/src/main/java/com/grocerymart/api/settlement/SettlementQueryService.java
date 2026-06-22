package com.grocerymart.api.settlement;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.audit.AuditService;
import com.grocerymart.api.identity.ApiException;

/**
 * Epic 9: settlement read for shops (9.1), cross-shop reconciliation for finance admins (9.3,
 * privileged + audited), manual payouts (9.4, balance-checked + idempotent + audited), and disputes.
 * Reads the ledger written by the order/payment flow; adds no new financial writes beyond payouts.
 */
@Service
public class SettlementQueryService {

    private final JdbcTemplate jdbc;
    private final AuditService audit;

    public SettlementQueryService(JdbcTemplate jdbc, AuditService audit) {
        this.jdbc = jdbc;
        this.audit = audit;
    }

    // ---- Shop settlement (Story 9.1) -------------------------------------------------------
    @Transactional(readOnly = true)
    public Map<String, Object> shopLedger(UUID ownerId, int limit) {
        UUID shopId = ownShop(ownerId);
        int lim = Math.min(Math.max(limit, 1), 200);
        List<Map<String, Object>> entries = jdbc.query(
            "SELECT order_id, entry_type, order_total, gst_amount, platform_fee, currency, created_at "
            + "FROM settlement_ledger WHERE store_id = ? ORDER BY created_at DESC LIMIT ?",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("orderId", rs.getObject("order_id").toString());
                m.put("entryType", rs.getString("entry_type"));
                m.put("amount", rs.getBigDecimal("order_total"));
                m.put("gst", rs.getBigDecimal("gst_amount"));
                m.put("commission", rs.getBigDecimal("platform_fee"));
                m.put("currency", rs.getString("currency"));
                m.put("createdAt", rs.getTimestamp("created_at").toInstant().toString());
                return m;
            }, shopId, lim);
        Map<String, Object> fin = financials(shopId, null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("entries", entries);
        out.putAll(fin);
        return out;
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> shopPayouts(UUID ownerId) {
        UUID shopId = ownShop(ownerId);
        return jdbc.query(
            "SELECT amount, currency, period_start, period_end, status, reason, paid_at FROM payout "
            + "WHERE shop_id = ? ORDER BY created_at DESC", (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("amount", rs.getBigDecimal("amount"));
                m.put("currency", rs.getString("currency"));
                m.put("periodStart", rs.getDate("period_start") == null ? null : rs.getDate("period_start").toString());
                m.put("periodEnd", rs.getDate("period_end") == null ? null : rs.getDate("period_end").toString());
                m.put("status", rs.getString("status"));
                m.put("reason", rs.getString("reason"));   // non-sensitive (no Stripe internals)
                m.put("paidAt", rs.getTimestamp("paid_at") == null ? null : rs.getTimestamp("paid_at").toInstant().toString());
                return m;
            }, shopId);
    }

    // ---- Admin reconciliation (Story 9.3) --------------------------------------------------
    @Transactional   // writes an audit row for the privileged cross-tenant read
    public Map<String, Object> reconciliation(UUID adminId, LocalDate asOf) {
        audit.success(adminId, "settlement.reconciliation.read", "settlement", asOf == null ? "all" : asOf.toString(),
            null, Map.of("asOf", asOf == null ? "all" : asOf.toString()));   // privileged cross-tenant read

        List<UUID> shops = jdbc.queryForList("SELECT DISTINCT store_id FROM settlement_ledger", UUID.class);
        List<Map<String, Object>> perShop = new java.util.ArrayList<>();
        BigDecimal tGross = BigDecimal.ZERO, tComm = BigDecimal.ZERO, tRef = BigDecimal.ZERO,
                   tNet = BigDecimal.ZERO, tPaid = BigDecimal.ZERO;
        for (UUID shopId : shops) {
            Map<String, Object> f = financials(shopId, asOf);
            String name = jdbc.queryForObject("SELECT name FROM shop WHERE id = ?", String.class, shopId);
            BigDecimal gross = (BigDecimal) f.get("gross"), comm = (BigDecimal) f.get("commission"),
                       ref = (BigDecimal) f.get("refunds"), net = (BigDecimal) f.get("net"),
                       paid = (BigDecimal) f.get("paidOut");
            BigDecimal expectedNet = gross.subtract(comm).subtract(ref);
            BigDecimal variance = net.subtract(expectedNet);
            Map<String, Object> row = new LinkedHashMap<>(f);
            row.put("shopId", shopId.toString());
            row.put("shopName", name);
            row.put("variance", variance);
            row.put("flagged", variance.signum() != 0);   // surface, don't silently sum
            perShop.add(row);
            tGross = tGross.add(gross); tComm = tComm.add(comm); tRef = tRef.add(ref);
            tNet = tNet.add(net); tPaid = tPaid.add(paid);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("totalGross", tGross);
        out.put("totalCommission", tComm);
        out.put("totalRefunds", tRef);
        out.put("totalNetOwed", tNet.subtract(tPaid));
        out.put("totalPaidOut", tPaid);
        out.put("perShop", perShop);
        return out;
    }

    // ---- Manual payout (Story 9.4) ---------------------------------------------------------
    @Transactional
    public Map<String, Object> recordManualPayout(UUID adminId, UUID shopId, BigDecimal amount,
                                                  String currency, String reference, String note) {
        if (amount == null || amount.signum() <= 0) throw ApiException.badRequest("amount must be positive");
        // Idempotent on reference: replay returns the existing payout, no new row.
        UUID existing = jdbc.query("SELECT id FROM payout WHERE reference = ?",
            rs -> rs.next() ? (UUID) rs.getObject("id") : null, reference);
        if (existing != null) return Map.of("payoutId", existing.toString(), "status", "manual", "idempotent", true);

        Map<String, Object> f = financials(shopId, null);
        BigDecimal netOwedBefore = (BigDecimal) f.get("netOwed");
        if (amount.compareTo(netOwedBefore) > 0) {
            audit.denied(adminId, "payout.manual.create", "shop", shopId.toString());
            throw ApiException.unprocessable("payout exceeds outstanding net owed (" + netOwedBefore + " " + currency + ")");
        }
        UUID id;
        try {
            id = jdbc.queryForObject("INSERT INTO payout (shop_id, amount, currency, status, reference, note, paid_at) "
                + "VALUES (?, ?, ?, 'manual', ?, ?, now()) RETURNING id",
                UUID.class, shopId, amount, currency, reference, note);
        } catch (DuplicateKeyException dup) {
            UUID e = jdbc.queryForObject("SELECT id FROM payout WHERE reference = ?", UUID.class, reference);
            return Map.of("payoutId", e.toString(), "status", "manual", "idempotent", true);
        }
        BigDecimal netOwedAfter = netOwedBefore.subtract(amount);
        audit.success(adminId, "payout.manual.create", "shop", shopId.toString(),
            Map.of("netOwed", netOwedBefore.toString()), Map.of("netOwed", netOwedAfter.toString(), "amount", amount.toString()));
        return Map.of("payoutId", id.toString(), "status", "manual", "netOwed", netOwedAfter);
    }

    @Transactional   // writes an audit row for the privileged read
    public List<Map<String, Object>> disputes(UUID adminId) {
        audit.success(adminId, "dispute.list.read", "dispute", "all", null, null);
        return jdbc.query(
            "SELECT d.id, d.order_id, d.shop_id, s.name AS shop_name, d.amount, d.currency, d.status, d.evidence_due "
            + "FROM dispute d LEFT JOIN shop s ON s.id = d.shop_id ORDER BY d.created_at DESC", (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("disputeId", rs.getObject("id").toString());
                m.put("orderId", rs.getObject("order_id") == null ? null : rs.getObject("order_id").toString());
                m.put("shop", rs.getString("shop_name"));
                m.put("amount", rs.getBigDecimal("amount"));
                m.put("currency", rs.getString("currency"));
                m.put("status", rs.getString("status"));
                m.put("evidenceDue", rs.getTimestamp("evidence_due") == null ? null
                    : rs.getTimestamp("evidence_due").toInstant().toString());
                return m;
            });
    }

    // ---- shared financial computation ------------------------------------------------------
    private Map<String, Object> financials(UUID shopId, LocalDate asOf) {
        String dateFilter = asOf != null ? "AND created_at::date <= ? " : "";
        Object[] args = asOf != null ? new Object[] { shopId, java.sql.Date.valueOf(asOf) } : new Object[] { shopId };
        Map<String, Object> led = jdbc.query(
            "SELECT COALESCE(SUM(order_total) FILTER (WHERE entry_type='charge'),0) AS gross, "
            + "COALESCE(-SUM(order_total) FILTER (WHERE entry_type='reversal'),0) AS refunds, "
            + "COALESCE(SUM(platform_fee),0) AS commission "
            + "FROM settlement_ledger WHERE store_id = ? " + dateFilter,
            rs -> {
                rs.next();
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("gross", rs.getBigDecimal("gross"));
                m.put("refunds", rs.getBigDecimal("refunds"));
                m.put("commission", rs.getBigDecimal("commission"));
                return m;
            }, args);
        BigDecimal paidOut = jdbc.queryForObject(
            "SELECT COALESCE(SUM(amount),0) FROM payout WHERE shop_id = ? AND status IN ('paid','manual')",
            BigDecimal.class, shopId);
        BigDecimal gross = (BigDecimal) led.get("gross"), refunds = (BigDecimal) led.get("refunds"),
                   commission = (BigDecimal) led.get("commission");
        BigDecimal net = gross.subtract(commission).subtract(refunds);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("gross", gross);
        out.put("commission", commission);
        out.put("refunds", refunds);
        out.put("net", net);
        out.put("paidOut", paidOut);
        out.put("netOwed", net.subtract(paidOut));
        return out;
    }

    private UUID ownShop(UUID ownerId) {
        UUID id = jdbc.query("SELECT id FROM shop WHERE owner_id = ?",
            rs -> rs.next() ? (UUID) rs.getObject("id") : null, ownerId);
        if (id == null) throw ApiException.notFound("you do not own a shop");
        return id;
    }
}
