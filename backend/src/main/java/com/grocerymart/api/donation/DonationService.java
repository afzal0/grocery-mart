package com.grocerymart.api.donation;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.identity.ApiException;

/**
 * Epic 8: NGO food donation. Admins manage/approve NGOs and oversee all activity; stores list
 * surplus (quantity decoupled from catalog stock); approved NGOs discover by PostGIS radius, claim
 * (single-winner), and confirm collection. Access is enforced at the app layer (RLS is defence-in-depth).
 */
@Service
public class DonationService {

    private final JdbcTemplate jdbc;
    private final PasswordEncoder encoder;

    public DonationService(JdbcTemplate jdbc, PasswordEncoder encoder) {
        this.jdbc = jdbc;
        this.encoder = encoder;
    }

    // ---- Admin NGO management (Story 8.1) --------------------------------------------------
    @Transactional
    public Map<String, Object> createNgo(String name, String contactEmail, Double lat, Double lng) {
        validateCoords(lat, lng);
        UUID id;
        if (lat != null && lng != null) {
            id = jdbc.queryForObject(
                "INSERT INTO ngos (name, contact_email, location) "
                + "VALUES (?, ?, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography) RETURNING id",
                UUID.class, name, contactEmail, lng, lat);
        } else {
            id = jdbc.queryForObject("INSERT INTO ngos (name, contact_email) VALUES (?, ?) RETURNING id",
                UUID.class, name, contactEmail);
        }
        return Map.of("ngoId", id.toString(), "status", "PENDING_APPROVAL");
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> listNgos() {
        return jdbc.query("SELECT id, name, contact_email, status, approved_at FROM ngos ORDER BY created_at DESC",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("ngoId", rs.getObject("id").toString());
                m.put("name", rs.getString("name"));
                m.put("contactEmail", rs.getString("contact_email"));
                m.put("status", rs.getString("status"));
                m.put("approvedAt", rs.getTimestamp("approved_at") == null ? null
                    : rs.getTimestamp("approved_at").toInstant().toString());
                return m;
            });
    }

    @Transactional
    public void approveNgo(UUID adminId, UUID ngoId) {
        int n = jdbc.update("UPDATE ngos SET status = 'APPROVED', approved_by = ?, approved_at = now() "
            + "WHERE id = ? AND status <> 'APPROVED'", adminId, ngoId);
        if (n == 0) throw ApiException.conflict("NGO not found or already approved");
    }

    @Transactional
    public void suspendNgo(UUID ngoId) {
        int n = jdbc.update("UPDATE ngos SET status = 'SUSPENDED' WHERE id = ?", ngoId);
        if (n == 0) throw ApiException.notFound("NGO not found");
    }

    @Transactional
    public Map<String, Object> addNgoManager(UUID ngoId, String email, String password, String displayName) {
        Integer exists = jdbc.query("SELECT 1 FROM ngos WHERE id = ?", rs -> rs.next() ? 1 : null, ngoId);
        if (exists == null) throw ApiException.notFound("NGO not found");
        if (password == null || password.length() < 8) throw ApiException.badRequest("password must be >= 8 chars");
        UUID userId = jdbc.queryForObject(
            "INSERT INTO app_user (email, display_name, password_hash, ngo_id) VALUES (?, ?, ?, ?) RETURNING id",
            UUID.class, email.toLowerCase(), displayName, encoder.encode(password), ngoId);
        jdbc.update("INSERT INTO user_role (user_id, role) VALUES (?, 'NGO')", userId);
        return Map.of("userId", userId.toString(), "ngoId", ngoId.toString());
    }

    // ---- Store offers a donation (Story 8.2) -----------------------------------------------
    @Transactional
    public Map<String, Object> createDonation(UUID ownerId, String productRef, String description, int quantity, String unit) {
        UUID storeId = ownShop(ownerId);
        UUID id = jdbc.queryForObject(
            "INSERT INTO donations (store_id, product_ref, description, quantity, unit) VALUES (?, ?, ?, ?, ?) RETURNING id",
            UUID.class, storeId, productRef, description, quantity, unit);   // store from auth, not body
        return Map.of("donationId", id.toString(), "status", "AVAILABLE");
    }

    @Transactional
    public void updateDonation(UUID ownerId, UUID donationId, Integer quantity, String description) {
        UUID storeId = ownShop(ownerId);
        int n = jdbc.update("UPDATE donations SET quantity = COALESCE(?, quantity), "
            + "description = COALESCE(?, description), updated_at = now() "
            + "WHERE id = ? AND store_id = ? AND status = 'AVAILABLE'", quantity, description, donationId, storeId);
        if (n == 0) throw ApiException.conflict("donation not found, not yours, or not AVAILABLE");
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> myDonations(UUID ownerId) {
        UUID storeId = ownShop(ownerId);
        return jdbc.query("SELECT id, product_ref, description, quantity, unit, status FROM donations "
            + "WHERE store_id = ? ORDER BY created_at DESC", (rs, i) -> donationRow(rs), storeId);
    }

    // ---- NGO discover / claim / collect (Stories 8.4–8.6) ----------------------------------
    @Transactional(readOnly = true)
    public List<Map<String, Object>> discover(UUID userId, double lat, double lng, double radiusMeters) {
        requireApprovedNgo(userId);
        return jdbc.query(
            "SELECT d.id, d.product_ref, d.description, d.quantity, d.unit, s.name AS shop_name, "
            + "ST_Distance(s.location, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography) AS dist "
            + "FROM donations d JOIN shop s ON s.id = d.store_id "
            + "WHERE d.status = 'AVAILABLE' AND d.claimed_by_ngo_id IS NULL AND s.location IS NOT NULL "
            + "AND ST_DWithin(s.location, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?) "
            + "ORDER BY dist", (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("donationId", rs.getObject("id").toString());
                m.put("productRef", rs.getString("product_ref"));
                m.put("description", rs.getString("description"));
                m.put("quantity", rs.getInt("quantity"));
                m.put("unit", rs.getString("unit"));
                m.put("store", rs.getString("shop_name"));
                m.put("distanceM", Math.round(rs.getDouble("dist")));
                return m;
            }, lng, lat, lng, lat, radiusMeters);
    }

    @Transactional
    public void claim(UUID userId, UUID donationId) {
        UUID ngoId = requireApprovedNgo(userId);
        int n = jdbc.update("UPDATE donations SET claimed_by_ngo_id = ?, claimed_at = now() "
            + "WHERE id = ? AND status = 'AVAILABLE' AND claimed_by_ngo_id IS NULL", ngoId, donationId);
        if (n == 0) throw ApiException.conflict("donation is already claimed or not available");
    }

    @Transactional
    public void collect(UUID userId, UUID donationId) {
        UUID ngoId = requireApprovedNgo(userId);
        // Claim-first: only the claiming NGO can confirm collection; result always has a collector.
        int n = jdbc.update("UPDATE donations SET status = 'COLLECTED', collected_by_ngo_id = ?, collected_at = now() "
            + "WHERE id = ? AND status = 'AVAILABLE' AND claimed_by_ngo_id = ?", ngoId, donationId, ngoId);
        if (n == 0) {
            throw ApiException.conflict("donation not claimed by you, already collected, or unavailable");
        }
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> myClaims(UUID userId) {
        UUID ngoId = requireApprovedNgo(userId);
        return jdbc.query("SELECT d.id, d.product_ref, d.description, d.quantity, d.unit, d.status, s.name AS shop_name "
            + "FROM donations d JOIN shop s ON s.id = d.store_id "
            + "WHERE d.claimed_by_ngo_id = ? OR d.collected_by_ngo_id = ? ORDER BY d.updated_at DESC",
            (rs, i) -> {
                Map<String, Object> m = donationRow(rs);
                m.put("store", rs.getString("shop_name"));
                return m;
            }, ngoId, ngoId);
    }

    // ---- Admin oversight + metrics (Story 8.7) ---------------------------------------------
    @Transactional(readOnly = true)
    public List<Map<String, Object>> allDonations() {
        return jdbc.query(
            "SELECT d.id, d.product_ref, d.quantity, d.unit, d.status, s.name AS store_name, "
            + "cn.name AS claimed_ngo, on2.name AS collected_ngo FROM donations d "
            + "JOIN shop s ON s.id = d.store_id "
            + "LEFT JOIN ngos cn ON cn.id = d.claimed_by_ngo_id "
            + "LEFT JOIN ngos on2 ON on2.id = d.collected_by_ngo_id ORDER BY d.created_at DESC",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("donationId", rs.getObject("id").toString());
                m.put("store", rs.getString("store_name"));
                m.put("productRef", rs.getString("product_ref"));
                m.put("quantity", rs.getInt("quantity"));
                m.put("unit", rs.getString("unit"));
                m.put("status", rs.getString("status"));
                m.put("claimedBy", rs.getString("claimed_ngo"));
                m.put("collectedBy", rs.getString("collected_ngo"));
                return m;
            });
    }

    @Transactional(readOnly = true)
    public Map<String, Object> metrics() {
        return jdbc.query(
            "SELECT COUNT(*) AS rescued_count, COALESCE(SUM(quantity), 0) AS rescued_qty "
            + "FROM donations WHERE status = 'COLLECTED'",
            rs -> {
                rs.next();
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("collectedCount", rs.getLong("rescued_count"));
                m.put("totalQuantityRescued", rs.getLong("rescued_qty"));
                return m;
            });
    }

    // ---- helpers ---------------------------------------------------------------------------
    UUID requireApprovedNgo(UUID userId) {
        Map<String, Object> ngo = jdbc.query(
            "SELECT n.id, n.status FROM app_user u JOIN ngos n ON n.id = u.ngo_id WHERE u.id = ?",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("id", rs.getObject("id"));
                m.put("status", rs.getString("status"));
                return m;
            }, userId);
        if (ngo == null) throw new ApiException(HttpStatus.FORBIDDEN, "your account is not linked to an NGO");
        if (!"APPROVED".equals(ngo.get("status"))) {
            throw new ApiException(HttpStatus.FORBIDDEN, "your NGO is not approved");
        }
        return (UUID) ngo.get("id");
    }

    private UUID ownShop(UUID ownerId) {
        UUID id = jdbc.query("SELECT id FROM shop WHERE owner_id = ?",
            rs -> rs.next() ? (UUID) rs.getObject("id") : null, ownerId);
        if (id == null) throw ApiException.notFound("you do not own a shop");
        return id;
    }

    private static void validateCoords(Double lat, Double lng) {
        if (lat == null && lng == null) return;
        if (lat == null || lng == null) throw ApiException.badRequest("both lat and lng are required");
        if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
            throw ApiException.badRequest("coordinates out of range");
        }
    }

    private static Map<String, Object> donationRow(java.sql.ResultSet rs) throws java.sql.SQLException {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("donationId", rs.getObject("id").toString());
        m.put("productRef", rs.getString("product_ref"));
        m.put("description", rs.getString("description"));
        m.put("quantity", rs.getInt("quantity"));
        m.put("unit", rs.getString("unit"));
        m.put("status", rs.getString("status"));
        return m;
    }
}
