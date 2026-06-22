package com.grocerymart.api.reviews;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class ReviewDtos {
    private ReviewDtos() {}

    public record CreateReviewRequest(
        @NotNull @Min(1) @Max(5) Integer rating,
        @Size(max = 2000) String body) {}

    public record UpdateReviewRequest(
        @Min(1) @Max(5) Integer rating,
        @Size(max = 2000) String body) {}
}
