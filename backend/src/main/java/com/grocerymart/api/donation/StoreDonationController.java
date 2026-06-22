package com.grocerymart.api.donation;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.donation.DonationDtos.CreateDonationRequest;
import com.grocerymart.api.donation.DonationDtos.UpdateDonationRequest;

import jakarta.validation.Valid;

/** Store-side surplus donation listing (Epic 8, Story 8.2). store_id comes from the authenticated shop. */
@RestController
@RequestMapping("/api/v1")
@PreAuthorize("hasRole('SHOP_OWNER')")
public class StoreDonationController {

    private final DonationService donations;

    public StoreDonationController(DonationService donations) {
        this.donations = donations;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @PostMapping("/donations")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> create(@Valid @RequestBody CreateDonationRequest req, Authentication auth) {
        return donations.createDonation(uid(auth), req.productRef(), req.description(), req.quantity(), req.unit());
    }

    @PutMapping("/donations/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void update(@PathVariable UUID id, @Valid @RequestBody UpdateDonationRequest req, Authentication auth) {
        donations.updateDonation(uid(auth), id, req.quantity(), req.description());
    }

    @GetMapping("/shops/me/donations")
    public List<Map<String, Object>> mine(Authentication auth) {
        return donations.myDonations(uid(auth));
    }
}
