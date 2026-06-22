package com.grocerymart.api.notifications;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.reviews.RatingService;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

/**
 * Epic 7 (Stories 7.4, 7.7, 7.8): the single outbox relay. Polls unpublished outbox_event rows and
 * dispatches at-least-once: Review* events recompute the rating read-model (idempotent); notification
 * events create a deduped in-app row and, subject to opt-out, send an FCM push — pruning dead tokens
 * and retrying transient failures up to a bounded limit so nothing loops forever.
 */
@Component
public class NotificationConsumer {

    private static final Logger log = LoggerFactory.getLogger(NotificationConsumer.class);

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final RatingService ratings;
    private final NotificationService notifications;
    private final PreferenceService preferences;
    private final DeviceTokenService deviceTokens;
    private final FcmSender fcm;
    private final int maxAttempts;

    public NotificationConsumer(JdbcTemplate jdbc, ObjectMapper mapper, RatingService ratings,
                                NotificationService notifications, PreferenceService preferences,
                                DeviceTokenService deviceTokens, FcmSender fcm,
                                @Value("${grocerymart.notifications.push-max-attempts}") int maxAttempts) {
        this.jdbc = jdbc;
        this.mapper = mapper;
        this.ratings = ratings;
        this.notifications = notifications;
        this.preferences = preferences;
        this.deviceTokens = deviceTokens;
        this.fcm = fcm;
        this.maxAttempts = maxAttempts;
    }

    @Scheduled(fixedDelayString = "1500")
    public void poll() {
        List<Map<String, Object>> batch = jdbc.query(
            "SELECT id, event_id, type, payload, attempts FROM outbox_event WHERE published_at IS NULL "
            + "ORDER BY occurred_at LIMIT 100",
            (rs, i) -> Map.of("id", rs.getLong("id"), "event_id", (UUID) rs.getObject("event_id"),
                "type", rs.getString("type"), "payload", rs.getString("payload"), "attempts", rs.getInt("attempts")));
        for (Map<String, Object> e : batch) {
            long id = (Long) e.get("id");
            try {
                dispatch((UUID) e.get("event_id"), (String) e.get("type"), (String) e.get("payload"),
                    (Integer) e.get("attempts"));
                jdbc.update("UPDATE outbox_event SET published_at = now() WHERE id = ?", id);
            } catch (RetryablePush retry) {
                int attempts = (Integer) e.get("attempts") + 1;
                if (attempts >= maxAttempts) {
                    jdbc.update("UPDATE outbox_event SET attempts = ?, published_at = now() WHERE id = ?", attempts, id);
                    log.warn("[outbox] event {} push failed after {} attempts; marking done (failed)", id, attempts);
                } else {
                    jdbc.update("UPDATE outbox_event SET attempts = ? WHERE id = ?", attempts, id);
                }
            } catch (Exception ex) {
                log.error("[outbox] event {} dispatch error: {}", id, ex.getMessage());
                jdbc.update("UPDATE outbox_event SET attempts = attempts + 1, published_at = now() WHERE id = ?", id);
            }
        }
    }

    @Transactional
    void dispatch(UUID eventId, String type, String payloadJson, int attempts) {
        JsonNode p = mapper.readTree(payloadJson);
        if (type.startsWith("Review")) {
            ratings.recompute(UUID.fromString(p.path("canonicalProductId").asText()));
            return;
        }
        // notification event
        UUID recipient = UUID.fromString(p.path("recipientId").asText());
        String category = p.path("category").asText("orders");
        String title = p.path("title").asText("");
        String body = p.path("body").asText(null);
        UUID orderId = p.hasNonNull("orderId") ? UUID.fromString(p.path("orderId").asText()) : null;

        boolean created = notifications.createDeduped(recipient, eventId, type, category, title, body, payloadJson, orderId);
        boolean shouldPush = created || attempts > 0;   // first processing, or a retry of a failed push
        if (!shouldPush || !preferences.pushAllowed(recipient, category)) return;

        List<String> tokens = jdbc.queryForList(
            "SELECT fcm_token FROM device_tokens WHERE user_id = ? AND status = 'active'", String.class, recipient);
        boolean transientFailure = false;
        for (String token : tokens) {
            FcmSender.Result r = fcm.send(token, title, body);
            if (r == FcmSender.Result.UNREGISTERED) {
                deviceTokens.expire(token);   // prune dead token (Story 7.8)
            } else if (r == FcmSender.Result.RETRYABLE_ERROR) {
                transientFailure = true;
            }
        }
        if (transientFailure) throw new RetryablePush();
    }

    private static final class RetryablePush extends RuntimeException {}
}
