package com.grocerymart.api.delivery;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Epic 6 scheduled jobs: surface scheduled orders in the dispatch queue as their slot nears, and
 * purge driver GPS fixes after the retention window (NFR-PRIV-01). Admin can also trigger these
 * via the ops endpoints in {@link DeliveryOpsController}.
 */
@Component
public class DeliverySchedules {

    private static final Logger log = LoggerFactory.getLogger(DeliverySchedules.class);

    private final DeliveryService delivery;
    private final int retentionHours;

    public DeliverySchedules(DeliveryService delivery,
                             @Value("${grocerymart.delivery.location-retention-hours}") int retentionHours) {
        this.delivery = delivery;
        this.retentionHours = retentionHours;
    }

    @Scheduled(fixedDelayString = "60000")   // every minute
    public void promoteScheduled() {
        int n = delivery.promoteScheduledToReady();
        if (n > 0) log.info("[delivery] promoted {} scheduled order(s) to ready", n);
    }

    @Scheduled(fixedDelayString = "3600000")   // hourly
    public void purgeLocations() {
        int n = delivery.purgeOldLocations(retentionHours);
        if (n > 0) log.info("[delivery] purged {} expired driver_location row(s)", n);
    }
}
