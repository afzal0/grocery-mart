package com.grocerymart.api.donation;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;

public final class DonationDtos {
    private DonationDtos() {}

    public record CreateNgoRequest(@NotBlank String name, String contactEmail, Double lat, Double lng) {}

    public record AddNgoManagerRequest(@NotBlank String email, @NotBlank String password, String displayName) {}

    public record CreateDonationRequest(
        String productRef,
        String description,
        @Positive int quantity,
        String unit) {}

    public record UpdateDonationRequest(@Positive Integer quantity, String description) {}
}
