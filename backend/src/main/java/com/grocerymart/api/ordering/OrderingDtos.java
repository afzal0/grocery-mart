package com.grocerymart.api.ordering;

import java.util.List;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Positive;

public final class OrderingDtos {
    private OrderingDtos() {}

    /** One basket item being resolved to a store line. A non-null substitute store_product means
     *  the customer accepted a substitution for this canonical item. */
    public record ResolveItem(
        @NotBlank String canonicalProductId,
        @Positive int quantity,
        String substituteStoreProductId) {}

    /** Resolve a compared basket into a single-store cart bound to the chosen winning store. */
    public record ResolveCartRequest(
        @NotBlank String storeId,
        @NotBlank String currency,
        @NotEmpty List<ResolveItem> items) {}

    public record UpdateLineRequest(@Positive int quantity) {}

    /** Place the order from a resolved, checkout-ready cart. timing defaults to immediate;
     *  a scheduled timing requires a slotId (Story 6.1). */
    public record CheckoutRequest(
        @NotBlank String deliveryAddress,
        Double lat,
        Double lng,
        String timing,
        String slotId) {}
}
