package com.grocerymart.api.discovery;

import java.util.List;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

public final class DiscoveryDtos {
    private DiscoveryDtos() {}

    public record BasketItem(@NotBlank String canonicalProductId, int quantity) {}

    public record BasketCompareRequest(
        double lat,
        double lng,
        Double radiusKm,
        @NotEmpty List<BasketItem> items) {}
}
