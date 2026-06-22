package com.grocerymart.api.delivery;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.delivery.DeliveryDtos.AddDriverRequest;
import com.grocerymart.api.delivery.DeliveryDtos.AssignRequest;
import com.grocerymart.api.delivery.DeliveryDtos.CreateSlotRequest;

import jakarta.validation.Valid;

/** Shop-side delivery ops: slots, driver roster, dispatch queue, manual assignment (Epic 6). */
@RestController
@RequestMapping("/api/v1")
@PreAuthorize("hasRole('SHOP_OWNER')")
public class ShopDispatchController {

    private final DeliveryService delivery;

    public ShopDispatchController(DeliveryService delivery) {
        this.delivery = delivery;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @PostMapping("/shops/me/slots")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> createSlot(@Valid @RequestBody CreateSlotRequest req, Authentication auth) {
        return delivery.createSlot(uid(auth), req.windowStart(), req.windowEnd(), req.capacity());
    }

    @PostMapping("/shops/me/drivers")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> addDriver(@Valid @RequestBody AddDriverRequest req, Authentication auth) {
        return delivery.addDriver(uid(auth), req.email(), req.password(), req.displayName());
    }

    @GetMapping("/shops/me/dispatch")
    public List<Map<String, Object>> dispatch(Authentication auth) {
        return delivery.dispatchQueue(uid(auth));
    }

    @PostMapping("/shops/me/orders/{orderId}/assign")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void assign(@PathVariable UUID orderId, @Valid @RequestBody AssignRequest req, Authentication auth) {
        delivery.assignDriver(uid(auth), orderId, UUID.fromString(req.driverId()));
    }
}
