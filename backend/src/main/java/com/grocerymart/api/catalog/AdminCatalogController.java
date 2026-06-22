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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Admin catalog governance (Stories 3.2, 3.7): shop approval + merge queue. */
@RestController
@RequestMapping("/api/v1/admin")
@PreAuthorize("hasRole('ADMIN')")
public class AdminCatalogController {

    private final CatalogService catalog;

    public AdminCatalogController(CatalogService catalog) {
        this.catalog = catalog;
    }

    @PostMapping("/shops/{id}/approve")
    public Map<String, Object> approve(@PathVariable UUID id) {
        catalog.setShopStatus(id, "active");
        return Map.of("shopId", id.toString(), "status", "active");
    }

    @PostMapping("/shops/{id}/reject")
    public Map<String, Object> reject(@PathVariable UUID id) {
        catalog.setShopStatus(id, "rejected");
        return Map.of("shopId", id.toString(), "status", "rejected");
    }

    @GetMapping("/merge-queue")
    public List<Map<String, Object>> mergeQueue() {
        return catalog.mergeQueue();
    }

    @PostMapping("/merge-queue/{candidateId}/confirm")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void confirm(@PathVariable long candidateId, Authentication auth) {
        catalog.confirmCandidate(candidateId, "admin:" + auth.getName());
    }
}
