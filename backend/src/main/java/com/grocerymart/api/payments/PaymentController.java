package com.grocerymart.api.payments;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.payments.PaymentDtos.TopupRequest;

import jakarta.validation.Valid;

/** Wallet, card payment, refund, the Stripe webhook, and the reservation sweep trigger (Epic 5). */
@RestController
@RequestMapping("/api/v1")
public class PaymentController {

    private final WalletService wallet;
    private final CardPaymentService card;
    private final RefundService refund;
    private final WebhookService webhook;
    private final ReservationSweeper sweeper;

    public PaymentController(WalletService wallet, CardPaymentService card, RefundService refund,
                             WebhookService webhook, ReservationSweeper sweeper) {
        this.wallet = wallet;
        this.card = card;
        this.refund = refund;
        this.webhook = webhook;
        this.sweeper = sweeper;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    // ---- wallet (Stories 5.5, 5.6) ---------------------------------------------------------
    @GetMapping("/wallet")
    @PreAuthorize("hasRole('CUSTOMER')")
    public List<Map<String, Object>> wallet(Authentication auth) {
        return wallet.balances(uid(auth));
    }

    @PostMapping("/wallet/topup")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> topup(@Valid @RequestBody TopupRequest req, Authentication auth) {
        return wallet.startTopup(uid(auth), req.amount(), req.currency());
    }

    @PostMapping("/orders/{id}/pay/wallet")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> payWallet(@PathVariable UUID id, Authentication auth) {
        wallet.payOrder(uid(auth), id);
        return Map.of("orderId", id.toString(), "paymentStatus", "paid", "method", "wallet");
    }

    // ---- card (Story 5.7) ------------------------------------------------------------------
    @PostMapping("/orders/{id}/pay/card")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> payCard(@PathVariable UUID id, Authentication auth) {
        return card.startCardPayment(uid(auth), id);
    }

    // ---- refund (Story 5.10) ---------------------------------------------------------------
    @PostMapping("/orders/{id}/refund")
    @PreAuthorize("hasAnyRole('CUSTOMER','ADMIN')")
    public Map<String, Object> refundOrder(@PathVariable UUID id, Authentication auth) {
        boolean isAdmin = auth.getAuthorities().stream()
            .map(GrantedAuthority::getAuthority).anyMatch("ROLE_ADMIN"::equals);
        return refund.refund(uid(auth), isAdmin, id);
    }

    // ---- the single verified webhook (Story 5.8) — public, signature-gated -----------------
    @PostMapping("/payments/webhook")
    public Map<String, Object> stripeWebhook(@RequestBody String body,
                                             @RequestHeader(value = "Stripe-Signature", required = false) String sig) {
        return Map.of("result", webhook.handle(body, sig));
    }

    // ---- ops/test: force the reservation sweep now -----------------------------------------
    @PostMapping("/payments/_sweep")
    @PreAuthorize("hasRole('ADMIN')")
    public Map<String, Object> sweep() {
        return Map.of("released", sweeper.sweepExpired());
    }
}
