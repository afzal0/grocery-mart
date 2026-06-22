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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Approved-NGO donation discovery, claim, and collection (Epic 8, Stories 8.4–8.6). */
@RestController
@RequestMapping("/api/v1/ngo")
@PreAuthorize("hasRole('NGO')")
public class NgoController {

    private final DonationService donations;

    public NgoController(DonationService donations) {
        this.donations = donations;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @GetMapping("/donations")
    public List<Map<String, Object>> discover(@RequestParam double lat, @RequestParam double lng,
                                              @RequestParam(defaultValue = "10") double radiusKm, Authentication auth) {
        return donations.discover(uid(auth), lat, lng, radiusKm * 1000);
    }

    @GetMapping("/donations/mine")
    public List<Map<String, Object>> mine(Authentication auth) {
        return donations.myClaims(uid(auth));
    }

    @PostMapping("/donations/{id}/claim")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void claim(@PathVariable UUID id, Authentication auth) {
        donations.claim(uid(auth), id);
    }

    @PostMapping("/donations/{id}/collect")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void collect(@PathVariable UUID id, Authentication auth) {
        donations.collect(uid(auth), id);
    }
}
