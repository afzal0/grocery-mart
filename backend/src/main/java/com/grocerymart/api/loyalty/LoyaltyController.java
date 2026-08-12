package com.grocerymart.api.loyalty;

import java.util.Map;
import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** The customer's loyalty credit balance and recent activity. */
@RestController
@RequestMapping("/api/v1/loyalty")
public class LoyaltyController {

    private final LoyaltyService loyalty;

    public LoyaltyController(LoyaltyService loyalty) {
        this.loyalty = loyalty;
    }

    /** Balance + last 50 entries. Returns the credit COUNT only — how it was derived stays server-side. */
    @GetMapping
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> summary(Authentication auth) {
        return loyalty.summary(UUID.fromString(auth.getName()));
    }
}
