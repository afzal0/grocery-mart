package com.grocerymart.api.catalog;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.catalog.CatalogDtos.CreateShopRequest;
import com.grocerymart.api.catalog.CatalogDtos.CreateStoreProductRequest;
import com.grocerymart.api.catalog.CatalogDtos.UpdateProductRequest;
import com.grocerymart.api.catalog.CatalogDtos.UpdateShopRequest;

import jakarta.validation.Valid;

/** Shop-owner catalog endpoints (Stories 3.1, 3.3, 3.4, 3.9, 3.10). */
@RestController
@RequestMapping("/api/v1")
@PreAuthorize("hasRole('SHOP_OWNER')")
public class ShopController {

    private final CatalogService catalog;

    public ShopController(CatalogService catalog) {
        this.catalog = catalog;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @PostMapping("/shops")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> createShop(@Valid @RequestBody CreateShopRequest req, Authentication auth) {
        UUID shopId = catalog.createShop(uid(auth), req.name(), req.cuisineTags());
        return Map.of("shopId", shopId.toString(), "status", "pending");
    }

    @GetMapping("/shops/me")
    public Map<String, Object> myShop(Authentication auth) {
        return catalog.getMyShop(uid(auth));
    }

    @PutMapping("/shops/me")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void updateShop(@RequestBody UpdateShopRequest req, Authentication auth) {
        catalog.updateMyShop(uid(auth), req.name(), req.cuisineTags(), req.description(),
            req.address(), req.lat(), req.lng());
    }

    @GetMapping("/shops/me/products")
    public List<Map<String, Object>> myProducts(Authentication auth) {
        return catalog.listMyProducts(uid(auth));
    }

    @PostMapping("/store-products")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> createStoreProduct(@Valid @RequestBody CreateStoreProductRequest req, Authentication auth) {
        return catalog.createStoreProduct(uid(auth), req.name(), req.brand(), req.size(), req.price(), req.currency(), req.stock());
    }

    @PutMapping("/store-products/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void updateStoreProduct(@PathVariable UUID id, @Valid @RequestBody UpdateProductRequest req, Authentication auth) {
        catalog.updateStoreProduct(uid(auth), id, req.price(), req.stock());
    }

    /** Bulk price/stock upload (Story 3.10). Body is CSV: name,brand,size,price,stock per line. */
    @PostMapping(value = "/store-products/bulk", consumes = "text/csv")
    public Map<String, Object> bulkUpload(@RequestBody String csv, Authentication auth) {
        return catalog.bulkUploadCsv(uid(auth), csv);
    }
}
