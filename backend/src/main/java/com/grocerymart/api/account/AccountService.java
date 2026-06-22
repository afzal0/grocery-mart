package com.grocerymart.api.account;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.audit.AuditService;
import com.grocerymart.api.identity.ApiException;

/**
 * Epic 9 (Stories 9.5/9.6): in-app account deletion (anonymize PII, preserve financial records) and
 * APP-aligned data access/correction. Deletion blocks on in-flight orders, purges OTP + driver
 * locations + device tokens immediately, revokes sessions, and is audit-logged.
 */
@Service
public class AccountService {

    private final JdbcTemplate jdbc;
    private final AuditService audit;

    public AccountService(JdbcTemplate jdbc, AuditService audit) {
        this.jdbc = jdbc;
        this.audit = audit;
    }

    @Transactional
    public Map<String, Object> deleteAccount(UUID userId) {
        Integer active = jdbc.query(
            "SELECT 1 FROM orders WHERE customer_id = ? AND payment_status = 'paid' "
            + "AND status NOT IN ('delivered','cancelled') LIMIT 1", rs -> rs.next() ? 1 : null, userId);
        if (active != null) {
            audit.denied(userId, "account.delete", "user", userId.toString());
            throw ApiException.conflict("you have an in-flight order; deletion is blocked until it is delivered or cancelled");
        }

        String oldPhone = jdbc.query("SELECT phone FROM app_user WHERE id = ?",
            rs -> rs.next() ? rs.getString(1) : null, userId);

        // Anonymize/tombstone PII; financial rows (orders, settlement) keep the now-PII-free reference.
        jdbc.update("UPDATE app_user SET display_name = '[deleted]', email = NULL, phone = NULL, "
            + "password_hash = NULL, status = 'deactivated', anonymized = true, deleted_at = now() WHERE id = ?", userId);

        // Purge immediately: device tokens, sessions, OTP challenges, driver locations.
        jdbc.update("DELETE FROM device_tokens WHERE user_id = ?", userId);
        jdbc.update("UPDATE refresh_token SET revoked_at = now() WHERE user_id = ? AND revoked_at IS NULL", userId);
        if (oldPhone != null) jdbc.update("DELETE FROM otp_challenge WHERE phone = ?", oldPhone);
        jdbc.update("DELETE FROM driver_location WHERE driver_id = ?", userId);

        jdbc.update("INSERT INTO deletion_request (user_id, status, completed_at) VALUES (?, 'completed', now())", userId);
        audit.success(userId, "account.delete", "user", userId.toString(), null, Map.of("anonymized", true));
        return Map.of("status", "deleted", "anonymized", true);
    }

    /** Story 9.6 — machine-readable export of the requester's own personal data only. */
    @Transactional   // writes an audit row for the access request
    public Map<String, Object> exportData(UUID userId) {
        Map<String, Object> profile = jdbc.query(
            "SELECT display_name, email, phone, country_code, currency, locale, created_at FROM app_user WHERE id = ?",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("displayName", rs.getString("display_name"));
                m.put("email", rs.getString("email"));
                m.put("phone", rs.getString("phone"));
                m.put("country", rs.getString("country_code"));
                m.put("currency", rs.getString("currency"));
                m.put("locale", rs.getString("locale"));
                m.put("memberSince", rs.getTimestamp("created_at").toInstant().toString());
                return m;
            }, userId);
        if (profile == null) throw ApiException.notFound("account not found");
        List<Map<String, Object>> orders = jdbc.query(
            "SELECT id, store_id, grand_total, currency, status, delivery_address, created_at FROM orders "
            + "WHERE customer_id = ? ORDER BY created_at DESC", (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("orderId", rs.getObject("id").toString());
                m.put("total", rs.getBigDecimal("grand_total"));
                m.put("currency", rs.getString("currency"));
                m.put("status", rs.getString("status"));
                m.put("deliveryAddress", rs.getString("delivery_address"));
                m.put("placedAt", rs.getTimestamp("created_at").toInstant().toString());
                return m;
            }, userId);
        List<Map<String, Object>> reviews = jdbc.query(
            "SELECT rating, body, created_at FROM reviews WHERE customer_id = ? AND deleted_at IS NULL",
            (rs, i) -> Map.of("rating", rs.getInt("rating"), "body",
                rs.getString("body") == null ? "" : rs.getString("body"),
                "createdAt", rs.getTimestamp("created_at").toInstant().toString()), userId);
        audit.success(userId, "account.export", "user", userId.toString(), null, null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("profile", profile);
        out.put("orders", orders);
        out.put("reviews", reviews);
        out.put("addresses", orders.stream().map(o -> o.get("deliveryAddress")).filter(java.util.Objects::nonNull).distinct().toList());
        return out;
    }

    /** Story 9.6 — APP correction of an inaccurate profile field. */
    @Transactional
    public void correctProfile(UUID userId, String displayName, String country, String currency, String locale) {
        int n = jdbc.update("UPDATE app_user SET display_name = COALESCE(?, display_name), "
            + "country_code = COALESCE(?, country_code), currency = COALESCE(?, currency), "
            + "locale = COALESCE(?, locale) WHERE id = ? AND anonymized = false",
            displayName, country, currency, locale, userId);
        if (n == 0) throw ApiException.notFound("account not found");
        audit.success(userId, "account.correct", "user", userId.toString(), null,
            Map.of("displayName", displayName == null ? "" : displayName));
    }

    /** Story 9.6 — public privacy policy with effective date + collected-data categories. */
    public Map<String, Object> privacyPolicy() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("effectiveDate", "2026-06-22");
        out.put("policyUrl", "https://grocery-mart.example/privacy");
        out.put("termsUrl", "https://grocery-mart.example/terms");
        out.put("dataCategories", List.of(
            Map.of("category", "Identity", "data", "name, email, phone", "purpose", "account + authentication"),
            Map.of("category", "Location", "data", "delivery address, driver GPS", "purpose", "delivery + tracking"),
            Map.of("category", "Transactions", "data", "orders, payments, wallet", "purpose", "fulfilment + settlement"),
            Map.of("category", "Device", "data", "FCM token, platform", "purpose", "push notifications")));
        out.put("rights", List.of("access (export)", "correction", "deletion"));
        out.put("accountDeletion", "available in-app under Account → Delete Account (Story 9.5)");
        return out;
    }
}
