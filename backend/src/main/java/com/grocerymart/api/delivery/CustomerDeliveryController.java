package com.grocerymart.api.delivery;

import java.util.Map;
import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.delivery.DeliveryDtos.QuoteRequest;

import jakarta.validation.Valid;

/** Customer delivery surfaces: available slots, fee quote, and live order tracking (Epic 6). */
@RestController
@RequestMapping("/api/v1")
public class CustomerDeliveryController {

    private final DeliveryService delivery;

    public CustomerDeliveryController(DeliveryService delivery) {
        this.delivery = delivery;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @GetMapping("/stores/{storeId}/slots")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> slots(@PathVariable UUID storeId) {
        return delivery.availableSlots(storeId);
    }

    @PostMapping("/delivery/quote")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> quote(@Valid @RequestBody QuoteRequest req) {
        return delivery.quote(UUID.fromString(req.storeId()), req.lat(), req.lng());
    }

    /** Tracking is access-controlled in the service (customer/driver/shop-owner/admin only). */
    @GetMapping("/orders/{orderId}/tracking")
    @PreAuthorize("isAuthenticated()")
    public Map<String, Object> tracking(@PathVariable UUID orderId, Authentication auth) {
        boolean isAdmin = auth.getAuthorities().stream()
            .map(GrantedAuthority::getAuthority).anyMatch("ROLE_ADMIN"::equals);
        return delivery.tracking(uid(auth), isAdmin, orderId);
    }
}
