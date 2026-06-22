package com.grocerymart.api.settlement;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.audit.AuditService;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/** Admin finance: cross-shop reconciliation (9.3), manual payouts + disputes (9.4), audit log (9.11). */
@RestController
@RequestMapping("/api/v1/admin")
@PreAuthorize("hasRole('ADMIN')")
public class AdminSettlementController {

    public record ManualPayoutRequest(@NotNull @Positive BigDecimal amount, @NotBlank String currency,
                                       @NotBlank String reference, String note) {}

    private final SettlementQueryService settlement;
    private final AuditService audit;

    public AdminSettlementController(SettlementQueryService settlement, AuditService audit) {
        this.settlement = settlement;
        this.audit = audit;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @GetMapping("/settlement/reconciliation")
    public Map<String, Object> reconciliation(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate asOf,
            Authentication auth) {
        return settlement.reconciliation(uid(auth), asOf);
    }

    @PostMapping("/shops/{shopId}/payouts")
    public Map<String, Object> manualPayout(@PathVariable UUID shopId,
            @jakarta.validation.Valid @RequestBody ManualPayoutRequest req, Authentication auth) {
        return settlement.recordManualPayout(uid(auth), shopId, req.amount(), req.currency(), req.reference(), req.note());
    }

    @GetMapping("/disputes")
    public List<Map<String, Object>> disputes(Authentication auth) {
        return settlement.disputes(uid(auth));
    }

    @GetMapping("/audit")
    public List<Map<String, Object>> audit(@RequestParam(required = false) String actor,
                                           @RequestParam(required = false) String action,
                                           @RequestParam(required = false) Integer limit, Authentication auth) {
        // Access to the audit log is itself audited (Story 9.11).
        audit.success(uid(auth), "audit.read", "audit_log", "query", null,
            Map.of("actor", actor == null ? "" : actor, "action", action == null ? "" : action));
        return audit.query(actor, action, limit);
    }
}
