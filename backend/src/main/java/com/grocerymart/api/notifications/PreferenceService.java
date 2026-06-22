package com.grocerymart.api.notifications;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/**
 * Epic 7 (Story 7.6): per-user, per-category push opt-out. Absence of a row means opted-in.
 * A "global" category row disables push for every category.
 */
@Service
public class PreferenceService {

    static final List<String> CATEGORIES = List.of("orders", "delivery", "promotions", "reviews", "shop", "global");

    private final JdbcTemplate jdbc;

    public PreferenceService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Map<String, Object>> get(UUID userId) {
        Map<String, Boolean> overrides = new java.util.HashMap<>();
        jdbc.query("SELECT category, push_enabled FROM notification_preferences WHERE user_id = ?",
            rs -> { overrides.put(rs.getString("category"), rs.getBoolean("push_enabled")); }, userId);
        return CATEGORIES.stream().map(c -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("category", c);
            m.put("pushEnabled", overrides.getOrDefault(c, true));   // default opted-in
            return m;
        }).toList();
    }

    public void set(UUID userId, String category, boolean pushEnabled) {
        jdbc.update("INSERT INTO notification_preferences (user_id, category, push_enabled, updated_at) "
            + "VALUES (?, ?, ?, now()) ON CONFLICT (user_id, category) DO UPDATE SET push_enabled = EXCLUDED.push_enabled, "
            + "updated_at = now()", userId, category, pushEnabled);
    }

    /** True if push is allowed for this user+category (global off or category off => blocked). */
    public boolean pushAllowed(UUID userId, String category) {
        Boolean global = lookup(userId, "global");
        if (Boolean.FALSE.equals(global)) return false;
        Boolean cat = lookup(userId, category);
        return !Boolean.FALSE.equals(cat);
    }

    private Boolean lookup(UUID userId, String category) {
        return jdbc.query("SELECT push_enabled FROM notification_preferences WHERE user_id = ? AND category = ?",
            rs -> rs.next() ? rs.getBoolean(1) : null, userId, category);
    }
}
