package com.grocerymart.api.reviews;

import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.reviews.ReviewDtos.CreateReviewRequest;
import com.grocerymart.api.reviews.ReviewDtos.UpdateReviewRequest;

import jakarta.validation.Valid;

/** Reviews on canonical products (Epic 7). Reads are open to any authenticated user. */
@RestController
@RequestMapping("/api/v1")
public class ReviewController {

    private final ReviewService reviews;

    public ReviewController(ReviewService reviews) {
        this.reviews = reviews;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @PostMapping("/products/{canonicalId}/reviews")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> create(@PathVariable UUID canonicalId,
                                      @Valid @RequestBody CreateReviewRequest req, Authentication auth) {
        return reviews.create(uid(auth), canonicalId, req.rating(), req.body());
    }

    @GetMapping("/products/{canonicalId}/reviews")
    @PreAuthorize("isAuthenticated()")
    public Map<String, Object> list(@PathVariable UUID canonicalId,
                                    @RequestParam(required = false) String cursor,
                                    @RequestParam(defaultValue = "20") int limit) {
        return reviews.list(canonicalId, cursor, limit);
    }

    @PatchMapping("/reviews/{reviewId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("hasRole('CUSTOMER')")
    public void update(@PathVariable UUID reviewId, @Valid @RequestBody UpdateReviewRequest req, Authentication auth) {
        reviews.update(uid(auth), reviewId, req.rating(), req.body());
    }

    @DeleteMapping("/reviews/{reviewId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("hasRole('CUSTOMER')")
    public void delete(@PathVariable UUID reviewId, Authentication auth) {
        reviews.delete(uid(auth), reviewId);
    }
}
