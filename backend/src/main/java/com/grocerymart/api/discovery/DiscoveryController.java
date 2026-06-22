package com.grocerymart.api.discovery;

import java.util.List;
import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.discovery.DiscoveryDtos.BasketCompareRequest;

import jakarta.validation.Valid;

/** Customer discovery + basket comparison (Epic 4). Any authenticated user. */
@RestController
@RequestMapping("/api/v1")
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

    /** One store's in-stock, canonically-linked catalog — the store "restaurant page". */
    @GetMapping("/stores/{shopId}/products")
    public List<Map<String, Object>> storeProducts(@org.springframework.web.bind.annotation.PathVariable
                                                    java.util.UUID shopId) {
        return discovery.storeProducts(shopId);
    }

    /** Whole-basket comparison across nearby stores (Stories 4.3/4.4). */
    @PostMapping("/basket/compare")
    public Map<String, Object> compare(@Valid @RequestBody BasketCompareRequest req) {
        double radiusMeters = (req.radiusKm() != null ? req.radiusKm() : 10) * 1000;
        return discovery.compareBasket(req.lat(), req.lng(), radiusMeters, req.items());
    }
}
