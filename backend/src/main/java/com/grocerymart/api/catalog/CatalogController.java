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
 * Customer-facing catalog reads (the wedge): cross-store price comparison for a canonical
 * product, and canonical search. Any authenticated user.
 */
@RestController
@RequestMapping("/api/v1/catalog")
public class CatalogController {

    private final CatalogService catalog;

    public CatalogController(CatalogService catalog) {
        this.catalog = catalog;
    }

    /** Every active store's price for one canonical product, cheapest first. */
    @GetMapping("/canonical/{id}/offers")
    public List<Map<String, Object>> offers(@PathVariable UUID id) {
        return catalog.offers(id);
    }

    @GetMapping("/canonical/search")
    public List<Map<String, Object>> search(@RequestParam("q") String q) {
        return catalog.searchCanonical(q);
    }
}
