package com.grocerymart.api.payments;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Epic 5 (Story 5.8): releases stock for abandoned card checkouts — reservations that were
 * authorized but never captured before expiry. Returns the held stock to available and voids the
 * dangling authorization, leaving the order out of paid. Never touches captured reservations.
 */
@Service
public class ReservationSweeper {

    private static final Logger log = LoggerFactory.getLogger(ReservationSweeper.class);

    private final JdbcTemplate jdbc;
    private final StripeStubProvider stripe;

    public ReservationSweeper(JdbcTemplate jdbc, StripeStubProvider stripe) {
        this.jdbc = jdbc;
        this.stripe = stripe;
    }

    @Scheduled(fixedDelayString = "60000")   // every 60s
    @Transactional
    public void sweep() {
        int released = sweepExpired();
        if (released > 0) log.info("[reservation-sweeper] released {} expired reservation(s)", released);
    }

    /** Release every expired, still-'reserved' reservation. Returns the count. Idempotent. */
    @Transactional
    public int sweepExpired() {
        List<Map<String, Object>> expired = jdbc.query(
            "SELECT id, order_id, store_product_id, qty FROM stock_reservation "
            + "WHERE status = 'reserved' AND expires_at < now() FOR UPDATE SKIP LOCKED",
            (rs, i) -> Map.of(
                "id", (UUID) rs.getObject("id"),
                "order_id", (UUID) rs.getObject("order_id"),
                "sp", (UUID) rs.getObject("store_product_id"),
                "qty", rs.getInt("qty")));
        for (Map<String, Object> r : expired) {
            jdbc.update("UPDATE store_product SET stock = stock + ? WHERE id = ?", r.get("qty"), r.get("sp"));
            jdbc.update("UPDATE stock_reservation SET status = 'released' WHERE id = ?", r.get("id"));
            // Void the dangling authorization for the order's intent (only if still un-captured).
            String intentId = jdbc.query(
                "SELECT provider_intent_id FROM payment_intent WHERE order_id = ? AND purpose = 'order' "
                + "AND status = 'authorized' ORDER BY created_at DESC LIMIT 1",
                rs -> rs.next() ? rs.getString(1) : null, r.get("order_id"));
            if (intentId != null) {
                stripe.cancel(intentId);
                jdbc.update("UPDATE payment_intent SET status = 'canceled' WHERE provider_intent_id = ?", intentId);
            }
        }
        return expired.size();
    }
}
