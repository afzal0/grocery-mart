package com.grocerymart.api.ordering;

import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;

public final class OrderingDtos {
    private OrderingDtos() {}

    /** One basket item being resolved to a store line. A non-null substitute store_product means
     *  the customer accepted a substitution for this canonical item. */
    public record ResolveItem(
        @NotBlank String canonicalProductId,
        @Positive int quantity,
        String substituteStoreProductId) {}

    /** Resolve a compared basket into a single-store cart bound to the chosen winning store.
     *  {@code @Valid} cascades validation into each {@link ResolveItem} so a non-positive quantity
     *  is rejected with 400 at the controller (instead of reaching the service / DB). */
    public record ResolveCartRequest(
        @NotBlank String storeId,
        @NotBlank @Pattern(regexp = "^[A-Z]{3}$", message = "currency must be a 3-letter ISO-4217 code") String currency,
        @NotEmpty @Valid List<ResolveItem> items) {}

    public record UpdateLineRequest(@Positive int quantity) {}

    /** Place the order from a resolved, checkout-ready cart. timing defaults to immediate;
     *  a scheduled timing requires a slotId (Story 6.1). Coordinates are required so the
     *  distance-based delivery fee / out-of-range check cannot be bypassed by omitting them. */
    public record CheckoutRequest(
        @NotBlank String deliveryAddress,
        @NotNull Double lat,
        @NotNull Double lng,
        String timing,
        String slotId) {}
}
