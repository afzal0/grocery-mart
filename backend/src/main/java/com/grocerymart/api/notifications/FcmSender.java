package com.grocerymart.api.notifications;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Dev stand-in for Firebase Cloud Messaging. Returns a delivery result so the consumer can prune
 * dead tokens (Story 7.8). In dev, a token containing "dead"/"unregistered" simulates an
 * UNREGISTERED response; everything else "delivers". Swap for the real FCM SDK in Epic 9.
 */
@Component
public class FcmSender {

    public enum Result { DELIVERED, UNREGISTERED, RETRYABLE_ERROR }

    private static final Logger log = LoggerFactory.getLogger(FcmSender.class);

    public Result send(String token, String title, String body) {
        if (token == null || token.isBlank()) return Result.UNREGISTERED;
        if (token.contains("dead") || token.contains("unregistered")) {
            log.info("[fcm-stub] token {} is UNREGISTERED", token);
            return Result.UNREGISTERED;
        }
        log.info("[fcm-stub] push to {}: {}", token, title);
        return Result.DELIVERED;
    }
}
