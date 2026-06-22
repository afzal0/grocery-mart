package com.grocerymart.api.payments;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import com.grocerymart.api.identity.ApiException;

/**
 * Epic 5 (Story 5.8): the ONE webhook handler. Signature-verified (rejects invalid/missing with no
 * side effects) and idempotent on the Stripe event id (UNIQUE processed_stripe_event). Every handled
 * sub-operation is independently idempotent, so a redelivery changes nothing. This is the only path
 * by which a payment is finalized — there is no client-asserted confirmation endpoint (NFR-SEC-04).
 */
@Service
public class WebhookService {

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final String secret;
    private final WalletService wallet;
    private final CardPaymentService card;
    private final RefundService refund;

    public WebhookService(JdbcTemplate jdbc, ObjectMapper mapper,
                          @Value("${grocerymart.payments.stripe-webhook-secret}") String secret,
                          WalletService wallet, CardPaymentService card, RefundService refund) {
        this.jdbc = jdbc;
        this.mapper = mapper;
        this.secret = secret;
        this.wallet = wallet;
        this.card = card;
        this.refund = refund;
    }

    public String handle(String rawBody, String sigHeader) {
        if (!StripeSignature.verify(rawBody, sigHeader, secret)) {
            throw ApiException.badRequest("invalid Stripe signature");   // no side effects (NFR-SEC-04)
        }
        JsonNode event;
        try {
            event = mapper.readTree(rawBody);
        } catch (Exception e) {
            throw ApiException.badRequest("malformed webhook body");
        }
        String eventId = event.path("id").asText(null);
        String type = event.path("type").asText("");
        String objectId = event.path("data").path("object").path("id").asText(null);
        if (eventId == null || objectId == null) throw ApiException.badRequest("missing event id / object id");

        try {
            if (!markProcessed(eventId, type)) return "duplicate";   // already processed — no-op
        } catch (DuplicateKeyException race) {
            return "duplicate";                                      // concurrent redelivery
        }

        switch (type) {
            case "payment_intent.amount_capturable_updated" -> card.authorizeAndReserve(objectId);
            case "payment_intent.succeeded" -> {
                if (isWalletTopup(objectId)) wallet.creditFromWebhook(objectId, eventId);
                else card.finalizeCapture(objectId);
            }
            case "charge.refunded" -> refund.finalizeCardRefund(objectId);
            default -> { /* unhandled/out-of-order: acknowledged safely, no state change */ }
        }
        return "ok";
    }

    @Transactional
    boolean markProcessed(String eventId, String type) {
        Integer exists = jdbc.query("SELECT 1 FROM processed_stripe_event WHERE stripe_event_id = ?",
            rs -> rs.next() ? 1 : null, eventId);
        if (exists != null) return false;
        jdbc.update("INSERT INTO processed_stripe_event (stripe_event_id, event_type) VALUES (?, ?)", eventId, type);
        return true;
    }

    private boolean isWalletTopup(String providerIntentId) {
        String purpose = jdbc.query("SELECT purpose FROM payment_intent WHERE provider_intent_id = ?",
            rs -> rs.next() ? rs.getString(1) : null, providerIntentId);
        return "wallet_topup".equals(purpose);
    }
}
