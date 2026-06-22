package com.grocerymart.api.notifications;

import java.util.Map;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Admin/ops trigger for device-token hygiene (also runs on a timer). Epic 7, Story 7.8. */
@RestController
@RequestMapping("/api/v1/notifications")
@PreAuthorize("hasRole('ADMIN')")
public class NotificationOpsController {

    private final DeviceTokenService deviceTokens;

    public NotificationOpsController(DeviceTokenService deviceTokens) {
        this.deviceTokens = deviceTokens;
    }

    @PostMapping("/_sweep-tokens")
    public Map<String, Object> sweep() {
        return Map.of("expired", deviceTokens.sweepStale());
    }
}
