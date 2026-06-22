package com.grocerymart.api.settlement;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.catalog.CatalogService;

/** Shop-facing settlement ledger, payouts (9.1), and catalog merge-outcome visibility (9.2). */
@RestController
@RequestMapping("/api/v1/shops/me")
@PreAuthorize("hasRole('SHOP_OWNER')")
public class ShopSettlementController {

    private final SettlementQueryService settlement;
    private final CatalogService catalog;

    public ShopSettlementController(SettlementQueryService settlement, CatalogService catalog) {
        this.settlement = settlement;
        this.catalog = catalog;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @GetMapping("/settlement")
    public Map<String, Object> ledger(@RequestParam(defaultValue = "50") int limit, Authentication auth) {
        return settlement.shopLedger(uid(auth), limit);
    }

    @GetMapping("/payouts")
    public List<Map<String, Object>> payouts(Authentication auth) {
        return settlement.shopPayouts(uid(auth));
    }

    @GetMapping("/catalog-outcomes")
    public List<Map<String, Object>> catalogOutcomes(Authentication auth) {
        return catalog.mergeOutcomes(uid(auth));
    }
}
