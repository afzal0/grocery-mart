package com.grocerymart.api.reviews;

import java.util.Map;
import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Aggregate rating reads for products and stores (Epic 7, Story 7.4). */
@RestController
@RequestMapping("/api/v1")
@PreAuthorize("isAuthenticated()")
public class RatingController {

    private final RatingService ratings;

    public RatingController(RatingService ratings) {
        this.ratings = ratings;
    }

    @GetMapping("/products/{canonicalId}/rating")
    public Map<String, Object> productRating(@PathVariable UUID canonicalId) {
        return ratings.productRating(canonicalId);
    }

    @GetMapping("/stores/{shopId}/rating")
    public Map<String, Object> storeRating(@PathVariable UUID shopId) {
        return ratings.storeRating(shopId);
    }
}
