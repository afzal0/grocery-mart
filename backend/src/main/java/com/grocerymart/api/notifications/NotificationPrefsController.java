package com.grocerymart.api.notifications;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/** FCM device-token registration + push preferences (Epic 7, Stories 7.5/7.6). */
@RestController
@RequestMapping("/api/v1/notifications")
@PreAuthorize("isAuthenticated()")
public class NotificationPrefsController {

    public record RegisterTokenRequest(@NotBlank String token, String platform, String appId) {}
    public record PreferenceRequest(@NotBlank String category, @NotNull Boolean pushEnabled) {}

    private final DeviceTokenService deviceTokens;
    private final PreferenceService preferences;

    public NotificationPrefsController(DeviceTokenService deviceTokens, PreferenceService preferences) {
        this.deviceTokens = deviceTokens;
        this.preferences = preferences;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @PostMapping("/devices")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void register(@org.springframework.web.bind.annotation.RequestBody RegisterTokenRequest req,
                         Authentication auth) {
        deviceTokens.register(uid(auth), req.token(), req.platform(), req.appId());
    }

    @GetMapping("/preferences")
    public List<Map<String, Object>> getPrefs(Authentication auth) {
        return preferences.get(uid(auth));
    }

    @PutMapping("/preferences")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void setPref(@RequestBody PreferenceRequest req, Authentication auth) {
        preferences.set(uid(auth), req.category(), req.pushEnabled());
    }
}
