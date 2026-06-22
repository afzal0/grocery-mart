package com.grocerymart.api.notifications;

import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.identity.ApiException;

/**
 * Epic 7 (Stories 7.5/7.8): FCM device-token lifecycle. Upsert on register, mark UNREGISTERED
 * tokens expired so they are never targeted again, and sweep tokens unseen past the retention window.
 */
@Service
public class DeviceTokenService {

    private final JdbcTemplate jdbc;
    private final int retentionDays;

    public DeviceTokenService(JdbcTemplate jdbc,
                              @Value("${grocerymart.notifications.token-retention-days}") int retentionDays) {
        this.jdbc = jdbc;
        this.retentionDays = retentionDays;
    }

    @Transactional
    public void register(UUID userId, String token, String platform, String appId) {
        if (token == null || token.isBlank()) throw ApiException.badRequest("fcm token is required");
        jdbc.update(
            "INSERT INTO device_tokens (user_id, fcm_token, platform, app_id, status, last_seen_at) "
            + "VALUES (?, ?, ?, ?, 'active', now()) "
            + "ON CONFLICT (fcm_token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, "
            + "app_id = EXCLUDED.app_id, status = 'active', last_seen_at = now()",
            userId, token, platform, appId);
        // FCM rotated the token for this device: supersede the prior active token so the user
        // is not double-targeted (Story 7.5.2). Keyed by (user, app_id) when an appId is given.
        if (appId != null && !appId.isBlank()) {
            jdbc.update("UPDATE device_tokens SET status = 'expired' WHERE user_id = ? AND app_id = ? "
                + "AND fcm_token <> ? AND status = 'active'", userId, appId, token);
        }
    }

    public void expire(String token) {
        jdbc.update("UPDATE device_tokens SET status = 'expired' WHERE fcm_token = ?", token);
    }

    /** Sweep dead/stale tokens (Story 7.8). Returns the number expired. */
    @Transactional
    public int sweepStale() {
        return jdbc.update("UPDATE device_tokens SET status = 'expired' "
            + "WHERE status = 'active' AND last_seen_at < now() - (? * interval '1 day')", retentionDays);
    }
}
