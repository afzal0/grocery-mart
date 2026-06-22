package com.grocerymart.api.delivery;

import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Admin/ops triggers for the delivery scheduled jobs (also run on timers). Epic 6. */
@RestController
@RequestMapping("/api/v1/delivery")
@PreAuthorize("hasRole('ADMIN')")
public class DeliveryOpsController {

    private final DeliveryService delivery;
    private final int retentionHours;

    public DeliveryOpsController(DeliveryService delivery,
                                 @Value("${grocerymart.delivery.location-retention-hours}") int retentionHours) {
        this.delivery = delivery;
        this.retentionHours = retentionHours;
    }

    @PostMapping("/_promote-scheduled")
    public Map<String, Object> promote() {
        return Map.of("promoted", delivery.promoteScheduledToReady());
    }

    @PostMapping("/_purge-locations")
    public Map<String, Object> purge() {
        return Map.of("purged", delivery.purgeOldLocations(retentionHours));
    }
}
