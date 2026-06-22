package com.grocerymart.api.catalog;

import java.math.BigDecimal;
import java.util.List;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public final class CatalogDtos {
    private CatalogDtos() {}

    public record CreateShopRequest(
        @NotBlank String name,
        List<String> cuisineTags) {}

    public record CreateStoreProductRequest(
        @NotBlank String name,
        String brand,
        String size,
        @NotNull @DecimalMin("0.0") BigDecimal price,
        String currency,
        @Min(0) int stock) {}

    public record UpdateShopRequest(String name, List<String> cuisineTags, String description) {}

    public record UpdateProductRequest(
        @DecimalMin("0.0") BigDecimal price,
        @Min(0) Integer stock) {}
}
