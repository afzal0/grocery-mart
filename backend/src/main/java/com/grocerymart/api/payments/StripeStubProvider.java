package com.grocerymart.api.payments;

import java.math.BigDecimal;
import java.util.concurrent.atomic.AtomicLong;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Dev stand-in for the Stripe SDK. Creates PaymentIntent ids and records capture/cancel/refund
 * intent; in dev there are no real Stripe keys, so the actual money-moves are driven by simulated
 * webhooks (the test harness signs them with the shared secret). Swap this for the real Stripe
 * client in Epic 9 — the rest of the payment code is unaffected.
 */
@Component
public class StripeStubProvider {

    private static final Logger log = LoggerFactory.getLogger(StripeStubProvider.class);
    private final AtomicLong seq = new AtomicLong(1000);

    /** Create a manual-capture PaymentIntent; returns the provider intent id. */
    public String createIntent(BigDecimal amount, String currency, String purpose) {
        String id = "pi_" + purpose + "_" + seq.incrementAndGet();
        log.info("[stripe-stub] created PaymentIntent {} for {} {} ({})", id, amount, currency, purpose);
        return id;
    }

    public void capture(String intentId) {
        log.info("[stripe-stub] capture requested for {}", intentId);
    }

    public void cancel(String intentId) {
        log.info("[stripe-stub] authorization voided for {}", intentId);
    }

    public String refund(String intentId, BigDecimal amount, String currency) {
        String id = "re_" + seq.incrementAndGet();
        log.info("[stripe-stub] refund {} of {} {} for {}", id, amount, currency, intentId);
        return id;
    }
}
