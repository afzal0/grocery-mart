package com.grocerymart.api.catalog;

import java.math.BigDecimal;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.catalog.CatalogDtos.CreateShopRequest;
import com.grocerymart.api.catalog.CatalogDtos.CreateStoreProductRequest;

import jakarta.validation.Valid;

/** Shop-owner catalog endpoints (Stories 3.1, 3.4). */
@RestController
@RequestMapping("/api/v1")
@PreAuthorize("hasRole('SHOP_OWNER')")
public class ShopController {

    private final CatalogService catalog;

    public ShopController(CatalogService catalog) {
        this.catalog = catalog;
    }

    @PostMapping("/shops")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> createShop(@Valid @RequestBody CreateShopRequest req, Authentication auth) {
        UUID shopId = catalog.createShop(UUID.fromString(auth.getName()), req.name(), req.cuisineTags());
        return Map.of("shopId", shopId.toString(), "status", "pending");
    }

    @PostMapping("/store-products")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> createStoreProduct(@Valid @RequestBody CreateStoreProductRequest req,
                                                  Authentication auth) {
        BigDecimal price = req.price();
        return catalog.createStoreProduct(UUID.fromString(auth.getName()),
            req.name(), req.brand(), req.size(), price, req.currency(), req.stock());
    }
}
