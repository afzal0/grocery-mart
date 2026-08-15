package com.grocerymart.api.discovery;

import java.util.List;
import java.util.Map;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Customer discovery (Epic 4). Any authenticated user. The explicit {@code @PreAuthorize}
 *  expresses authorization at the method layer too (defense in depth), so a future change to the
 *  global SecurityConfig cannot silently expose stock levels or store pricing to anonymous
 *  callers. */
@RestController
@RequestMapping("/api/v1")
@PreAuthorize("isAuthenticated()")
public class DiscoveryController {

    private final DiscoveryService discovery;

    public DiscoveryController(DiscoveryService discovery) {
        this.discovery = discovery;
    }

    /** Near-me stores (Stories 4.1/4.2). radiusKm default 10; optional cuisine filter. */
    @GetMapping("/discovery/shops")
    public List<Map<String, Object>> nearby(@RequestParam double lat, @RequestParam double lng,
                                            @RequestParam(defaultValue = "10") double radiusKm,
                                            @RequestParam(required = false) String cuisine) {
        return discovery.nearbyShops(lat, lng, radiusKm * 1000, cuisine);
    }

    /**
     * One store's in-stock, canonically-linked catalog — the storefront.
     *
     * <p>When the customer's coordinates are supplied, {@code price} is the normalized display
     * price for their area rather than this store's own price. Callers should always send them.
     */
    @GetMapping("/stores/{shopId}/products")
    public List<Map<String, Object>> storeProducts(@PathVariable java.util.UUID shopId,
                                                   @RequestParam(required = false) Double lat,
                                                   @RequestParam(required = false) Double lng) {
        return discovery.storeProducts(shopId, lat, lng);
    }
}
