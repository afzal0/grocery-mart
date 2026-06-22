package com.grocerymart.api.account;

import java.util.LinkedHashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.audit.AuditService;

/**
 * Epic 9 (Story 9.8): scheduled, idempotent retention purge. Each table has its own TTL; financial
 * and settlement rows are explicitly excluded. A per-run summary (counts per table) is written to the
 * audit log — without the purge itself becoming an unbounded audit source (one summary row per run).
 */
@Service
public class RetentionService {

    private static final Logger log = LoggerFactory.getLogger(RetentionService.class);

    private final JdbcTemplate jdbc;
    private final AuditService audit;
    private final int locationRetentionHours;
    private final int auditDays;

    public RetentionService(JdbcTemplate jdbc, AuditService audit,
                            @Value("${grocerymart.delivery.location-retention-hours}") int locationRetentionHours,
                            @Value("${grocerymart.retention.audit-days}") int auditDays) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.locationRetentionHours = locationRetentionHours;
        this.auditDays = auditDays;
    }

    @Scheduled(fixedDelayString = "3600000")   // hourly
    public Map<String, Object> purge() {
        // driver GPS for completed deliveries past TTL
        int locations = jdbc.update(
            "DELETE FROM driver_location dl USING delivery d WHERE dl.order_id = d.order_id "
            + "AND d.state = 'delivered' AND d.delivered_at < now() - (? * interval '1 hour')", locationRetentionHours);
        // expired/consumed OTP challenges
        int otps = jdbc.update("DELETE FROM otp_challenge WHERE expires_at < now() OR consumed_at IS NOT NULL");
        // audit_log beyond its (longer) retention window
        int audits = jdbc.update("DELETE FROM audit_log WHERE created_at < now() - (? * interval '1 day') "
            + "AND action <> 'retention.purge'", auditDays);
        // NOTE: settlement_ledger, payout, orders, order_item are NEVER purged (legal/financial retention).

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("driverLocations", locations);
        summary.put("otpChallenges", otps);
        summary.put("auditRows", audits);
        if (locations + otps + audits > 0) {
            log.info("[retention] purged {}", summary);
            recordSummary(summary);
        }
        return summary;
    }

    @Transactional
    void recordSummary(Map<String, Object> summary) {
        audit.success(null, "retention.purge", "system", "scheduled", null, summary);
    }
}
