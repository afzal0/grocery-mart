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

import com.grocerymart.api.delivery.DeliveryDtos.ConsentRequest;
import com.grocerymart.api.delivery.DeliveryDtos.LocationPing;

import jakarta.validation.Valid;

/** Driver app endpoints: job offers, accept/reject, pickup/deliver, consent + GPS streaming (Epic 6). */
@RestController
@RequestMapping("/api/v1/driver")
@PreAuthorize("hasRole('DRIVER')")
public class DriverController {

    private final DeliveryService delivery;

    public DriverController(DeliveryService delivery) {
        this.delivery = delivery;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @GetMapping("/jobs")
    public List<Map<String, Object>> jobs(Authentication auth) {
        return delivery.driverJobs(uid(auth));
    }

    @PostMapping("/orders/{orderId}/accept")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void accept(@PathVariable UUID orderId, Authentication auth) {
        delivery.accept(uid(auth), orderId);
    }

    @PostMapping("/orders/{orderId}/reject")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void reject(@PathVariable UUID orderId, Authentication auth) {
        delivery.reject(uid(auth), orderId);
    }

    @PostMapping("/orders/{orderId}/pickup")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void pickup(@PathVariable UUID orderId, Authentication auth) {
        delivery.pickedUp(uid(auth), orderId);
    }

    @PostMapping("/orders/{orderId}/deliver")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deliver(@PathVariable UUID orderId, Authentication auth) {
        delivery.deliver(uid(auth), orderId);
    }

    @PostMapping("/orders/{orderId}/consent")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void consent(@PathVariable UUID orderId, @RequestBody ConsentRequest req, Authentication auth) {
        delivery.setConsent(uid(auth), orderId, req.consent());
    }

    @PostMapping("/orders/{orderId}/location")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void location(@PathVariable UUID orderId, @Valid @RequestBody LocationPing ping, Authentication auth) {
        delivery.ingestLocation(uid(auth), orderId, ping.lat(), ping.lng());
    }
}
