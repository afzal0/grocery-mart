package com.grocerymart.api.catalog;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Customer-facing catalog reads: canonical product search. Any authenticated user.
 *
 * <p>The per-product cross-store offers endpoint was removed with the single-storefront pivot —
 * it listed every store's own price with no geographic filter, which is exactly what price
 * normalization exists to prevent. Customers now see one price per product, from
 * {@code GET /stores/{shopId}/products}.
 */
@RestController
@RequestMapping("/api/v1/catalog")
public class CatalogController {

    private final CatalogService catalog;

    public CatalogController(CatalogService catalog) {
        this.catalog = catalog;
    }

    @GetMapping("/canonical/search")
    public List<Map<String, Object>> search(@RequestParam("q") String q) {
        return catalog.searchCanonical(q);
    }
}
