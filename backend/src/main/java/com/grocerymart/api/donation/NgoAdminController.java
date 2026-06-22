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
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.donation.DonationDtos.AddNgoManagerRequest;
import com.grocerymart.api.donation.DonationDtos.CreateNgoRequest;

import jakarta.validation.Valid;

/** NGO management + donation oversight, inside the admin portal — no sixth client (Epic 8). */
@RestController
@RequestMapping("/api/v1/admin")
@PreAuthorize("hasRole('ADMIN')")
public class NgoAdminController {

    private final DonationService donations;

    public NgoAdminController(DonationService donations) {
        this.donations = donations;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @PostMapping("/ngos")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> createNgo(@Valid @RequestBody CreateNgoRequest req) {
        return donations.createNgo(req.name(), req.contactEmail(), req.lat(), req.lng());
    }

    @GetMapping("/ngos")
    public List<Map<String, Object>> listNgos() {
        return donations.listNgos();
    }

    @PostMapping("/ngos/{id}/approve")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void approve(@PathVariable UUID id, Authentication auth) {
        donations.approveNgo(uid(auth), id);
    }

    @PostMapping("/ngos/{id}/suspend")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void suspend(@PathVariable UUID id) {
        donations.suspendNgo(id);
    }

    @PostMapping("/ngos/{id}/managers")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> addManager(@PathVariable UUID id, @Valid @RequestBody AddNgoManagerRequest req) {
        return donations.addNgoManager(id, req.email(), req.password(), req.displayName());
    }

    @GetMapping("/donations")
    public List<Map<String, Object>> allDonations() {
        return donations.allDonations();
    }

    @GetMapping("/donations/metrics")
    public Map<String, Object> metrics() {
        return donations.metrics();
    }
}
