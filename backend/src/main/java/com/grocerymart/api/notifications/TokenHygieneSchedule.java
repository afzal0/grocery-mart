package com.grocerymart.api.notifications;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Periodically expire device tokens unseen past the retention window (Epic 7, Story 7.8). */
@Component
public class TokenHygieneSchedule {

    private static final Logger log = LoggerFactory.getLogger(TokenHygieneSchedule.class);

    private final DeviceTokenService deviceTokens;

    public TokenHygieneSchedule(DeviceTokenService deviceTokens) {
        this.deviceTokens = deviceTokens;
    }

    @Scheduled(fixedDelayString = "3600000")   // hourly
    public void sweep() {
        int n = deviceTokens.sweepStale();
        if (n > 0) log.info("[token-hygiene] expired {} stale device token(s)", n);
    }
}
