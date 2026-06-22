package com.grocerymart.api.ordering;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.ordering.OrderingDtos.CheckoutRequest;
import com.grocerymart.api.ordering.OrderingDtos.ResolveCartRequest;
import com.grocerymart.api.ordering.OrderingDtos.UpdateLineRequest;

import jakarta.validation.Valid;

/** Customer cart + ordering endpoints (Epic 5). CUSTOMER role. */
@RestController
@RequestMapping("/api/v1")
@PreAuthorize("hasRole('CUSTOMER')")
public class CartController {

    private final CartService carts;
    private final OrderService orders;

    public CartController(CartService carts, OrderService orders) {
        this.carts = carts;
        this.orders = orders;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @PostMapping("/cart/resolve")
    public Map<String, Object> resolve(@Valid @RequestBody ResolveCartRequest req, Authentication auth) {
        return carts.resolveCart(uid(auth), req);
    }

    @GetMapping("/carts/{id}")
    public Map<String, Object> getCart(@PathVariable UUID id, Authentication auth) {
        return carts.getCart(uid(auth), id);
    }

    @PatchMapping("/carts/{id}/lines/{lineId}")
    public Map<String, Object> updateLine(@PathVariable UUID id, @PathVariable UUID lineId,
                                          @Valid @RequestBody UpdateLineRequest req, Authentication auth) {
        return carts.updateLine(uid(auth), id, lineId, req.quantity());
    }

    @DeleteMapping("/carts/{id}/lines/{lineId}")
    public Map<String, Object> removeLine(@PathVariable UUID id, @PathVariable UUID lineId, Authentication auth) {
        return carts.removeLine(uid(auth), id, lineId);
    }

    @GetMapping("/carts/{id}/total")
    public Map<String, Object> total(@PathVariable UUID id,
                                     @RequestParam(required = false) Double lat,
                                     @RequestParam(required = false) Double lng, Authentication auth) {
        return carts.composeTotal(uid(auth), id, lat, lng);
    }

    @PostMapping("/carts/{id}/checkout")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> checkout(@PathVariable UUID id, @Valid @RequestBody CheckoutRequest req,
                                        @RequestHeader(value = "Idempotency-Key", required = false) String key,
                                        Authentication auth) {
        return orders.checkout(uid(auth), id, req, key);
    }

    @GetMapping("/orders")
    public List<Map<String, Object>> myOrders(Authentication auth) {
        return orders.myOrders(uid(auth));
    }

    @GetMapping("/orders/{id}")
    public Map<String, Object> getOrder(@PathVariable UUID id, Authentication auth) {
        return orders.getOrder(uid(auth), id);
    }
}
