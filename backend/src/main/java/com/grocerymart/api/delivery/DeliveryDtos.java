package com.grocerymart.api.delivery;

import java.time.OffsetDateTime;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

public final class DeliveryDtos {
    private DeliveryDtos() {}

    public record CreateSlotRequest(
        @NotNull OffsetDateTime windowStart,
        @NotNull OffsetDateTime windowEnd,
        @Positive int capacity) {}

    public record QuoteRequest(@NotNull String storeId, Double lat, Double lng) {}

    public record AssignRequest(@NotNull String driverId) {}

    public record AddDriverRequest(String email, String password, String displayName) {}

    public record LocationPing(double lat, double lng) {}

    public record ConsentRequest(boolean consent) {}
}
