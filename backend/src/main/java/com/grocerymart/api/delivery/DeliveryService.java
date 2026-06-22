package com.grocerymart.api.delivery;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.grocerymart.api.common.PricingService;
import com.grocerymart.api.identity.ApiException;
import com.grocerymart.api.notifications.OutboxService;

/**
 * Epic 6: delivery slots, distance quoting/out-of-range, manual dispatch + driver accept/reject,
 * consent-gated GPS ingest with live STOMP fan-out + REST tracking, and completion dual-notify.
 * Drives the order's customer-facing R21 status from the delivery state machine.
 */
@Service
public class DeliveryService {

    private final JdbcTemplate jdbc;
    private final PricingService pricing;
    private final OutboxService outbox;
    private final SimpMessagingTemplate stomp;
    private final PasswordEncoder encoder;
    private final double maxServiceKm;
    private final int slotReadyLeadMinutes;

    public DeliveryService(JdbcTemplate jdbc, PricingService pricing, OutboxService outbox,
                           SimpMessagingTemplate stomp, PasswordEncoder encoder,
                           @Value("${grocerymart.pricing.max-service-km}") double maxServiceKm,
                           @Value("${grocerymart.delivery.slot-ready-lead-minutes}") int slotReadyLeadMinutes) {
        this.jdbc = jdbc;
        this.pricing = pricing;
        this.outbox = outbox;
        this.stomp = stomp;
        this.encoder = encoder;
        this.maxServiceKm = maxServiceKm;
        this.slotReadyLeadMinutes = slotReadyLeadMinutes;
    }

    // ---- R21 status sync -------------------------------------------------------------------
    private static String orderStatusFor(String deliveryState) {
        return switch (deliveryState) {
            case "pending" -> "pending";
            case "ready", "assigned", "accepted" -> "processing";
            case "picked_up" -> "on_the_way";
            case "delivered" -> "delivered";
            case "cancelled" -> "cancelled";
            default -> "pending";
        };
    }

    private void transition(UUID orderId, String newState) {
        jdbc.update("UPDATE delivery SET state = ?, updated_at = now() WHERE order_id = ?", newState, orderId);
        jdbc.update("UPDATE orders SET status = ?, updated_at = now() WHERE id = ?", orderStatusFor(newState), orderId);
    }

    // ---- Slots (Story 6.1) -----------------------------------------------------------------
    @Transactional
    public Map<String, Object> createSlot(UUID shopOwnerId, OffsetDateTime start, OffsetDateTime end, int capacity) {
        UUID shopId = ownShop(shopOwnerId);
        if (!end.isAfter(start)) throw ApiException.badRequest("window end must be after start");
        UUID id = jdbc.queryForObject(
            "INSERT INTO delivery_slot (shop_id, window_start, window_end, capacity) VALUES (?, ?, ?, ?) RETURNING id",
            UUID.class, shopId, start, end, capacity);
        return Map.of("slotId", id.toString());
    }

    /** Future slots for a store with remaining capacity, plus the always-available Immediate option. */
    @Transactional(readOnly = true)
    public Map<String, Object> availableSlots(UUID storeId) {
        List<Map<String, Object>> slots = jdbc.query(
            "SELECT id, window_start, window_end, capacity, booked FROM delivery_slot "
            + "WHERE shop_id = ? AND window_start > now() AND booked < capacity ORDER BY window_start",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("slotId", rs.getObject("id").toString());
                m.put("windowStart", rs.getTimestamp("window_start").toInstant().toString());
                m.put("windowEnd", rs.getTimestamp("window_end").toInstant().toString());
                m.put("remaining", rs.getInt("capacity") - rs.getInt("booked"));
                return m;
            }, storeId);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("immediate", true);
        out.put("slots", slots);
        return out;
    }

    // ---- Quote + range (Story 6.2) ---------------------------------------------------------
    @Transactional(readOnly = true)
    public Map<String, Object> quote(UUID storeId, Double lat, Double lng) {
        if (lat == null || lng == null) {
            throw ApiException.unprocessable("delivery fee cannot be computed without delivery coordinates");
        }
        Double meters = storeDistanceMeters(storeId, lat, lng);
        if (meters == null) {
            throw ApiException.unprocessable("delivery fee cannot be computed (store has no location)");
        }
        Map<String, Object> out = new LinkedHashMap<>();
        double km = meters / 1000.0;
        if (km > maxServiceKm) {
            out.put("inRange", false);
            out.put("distanceKm", round1(km));
            out.put("message", "address is %.1f km away, beyond the %.0f km service range".formatted(km, maxServiceKm));
            return out;
        }
        String currency = jdbc.query(
            "SELECT currency FROM store_product WHERE shop_id = ? ORDER BY created_at LIMIT 1",
            rs -> rs.next() ? rs.getString(1) : "AUD", storeId);
        out.put("inRange", true);
        out.put("distanceKm", round1(km));
        out.put("fee", pricing.deliveryFee(storeId, lat, lng));
        out.put("currency", currency == null ? "AUD" : currency);
        return out;
    }

    /** Throws if the destination is beyond the store's max service distance (used at checkout). */
    public void assertInRange(UUID storeId, Double lat, Double lng) {
        if (lat == null || lng == null) return;   // no coords -> base fee path, allowed
        Double meters = storeDistanceMeters(storeId, lat, lng);
        if (meters != null && meters / 1000.0 > maxServiceKm) {
            throw ApiException.unprocessable("delivery address is out of range (>%.0f km)".formatted(maxServiceKm));
        }
    }

    // ---- Create delivery at checkout + book slot (Stories 6.1/6.2) -------------------------
    @Transactional
    public void createForOrder(UUID orderId, String timing, UUID slotId) {
        Map<String, Object> o = orderRow(orderId);
        UUID shopId = (UUID) o.get("store_id");
        String t = "scheduled".equals(timing) ? "scheduled" : "immediate";
        if ("scheduled".equals(t)) {
            if (slotId == null) throw ApiException.badRequest("scheduled delivery requires a slotId");
            int booked = jdbc.update(
                "UPDATE delivery_slot SET booked = booked + 1 WHERE id = ? AND shop_id = ? "
                + "AND window_start > now() AND booked < capacity", slotId, shopId);
            if (booked == 0) throw ApiException.conflict("delivery slot is full or no longer available; please re-select");
        } else {
            slotId = null;
        }
        jdbc.update("INSERT INTO delivery (order_id, shop_id, timing, slot_id, state, fee_amount, currency, "
            + "dest_address, dest_lat, dest_lng) VALUES (?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?)",
            orderId, shopId, t, slotId, o.get("delivery_fee"), o.get("currency"),
            o.get("delivery_address"), o.get("delivery_lat"), o.get("delivery_lng"));
    }

    /** Called when an order is paid: immediate deliveries enter the dispatch queue right away. */
    @Transactional
    public void onOrderPaid(UUID orderId) {
        String timing = jdbc.query("SELECT timing FROM delivery WHERE order_id = ?",
            rs -> rs.next() ? rs.getString(1) : null, orderId);
        if (timing == null) return;
        transition(orderId, "immediate".equals(timing) ? "ready" : "pending");
        outbox.emitNotification(customerOf(orderId), "OrderConfirmed", "orders",
            "Payment confirmed", "Your order is confirmed and being prepared", orderId);
    }

    // ---- Dispatch queue + assignment (Story 6.3) -------------------------------------------
    @Transactional(readOnly = true)
    public List<Map<String, Object>> dispatchQueue(UUID shopOwnerId) {
        UUID shopId = ownShop(shopOwnerId);
        return jdbc.query(
            "SELECT d.order_id, d.state, d.timing, d.driver_id, d.dest_address, o.grand_total, o.currency, "
            + "s.window_start FROM delivery d JOIN orders o ON o.id = d.order_id "
            + "LEFT JOIN delivery_slot s ON s.id = d.slot_id "
            + "WHERE d.shop_id = ? AND d.state IN ('ready','assigned','accepted','picked_up') "
            + "ORDER BY d.created_at", (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("orderId", rs.getObject("order_id").toString());
                m.put("state", rs.getString("state"));
                m.put("timing", rs.getString("timing"));
                m.put("driverId", rs.getObject("driver_id") == null ? null : rs.getObject("driver_id").toString());
                m.put("destination", rs.getString("dest_address"));
                m.put("grandTotal", rs.getBigDecimal("grand_total"));
                m.put("currency", rs.getString("currency"));
                m.put("slotStart", rs.getTimestamp("window_start") == null ? null
                    : rs.getTimestamp("window_start").toInstant().toString());
                return m;
            }, shopId);
    }

    @Transactional
    public void assignDriver(UUID shopOwnerId, UUID orderId, UUID driverId) {
        UUID shopId = ownShop(shopOwnerId);
        Map<String, Object> d = deliveryRow(orderId);
        if (!shopId.equals(d.get("shop_id"))) throw ApiException.forbidden("not your order");
        if (!"ready".equals(d.get("state"))) throw ApiException.conflict("order is not ready for assignment");
        Integer roster = jdbc.query("SELECT 1 FROM shop_driver WHERE shop_id = ? AND driver_id = ? AND is_available",
            rs -> rs.next() ? 1 : null, shopId, driverId);
        if (roster == null) throw ApiException.unprocessable("driver is not on this shop's roster or is unavailable");
        jdbc.update("UPDATE delivery SET driver_id = ?, assigned_at = now() WHERE order_id = ?", driverId, orderId);
        transition(orderId, "assigned");
        outbox.emitNotification(driverId, "DriverAssigned", "delivery",
            "New delivery job", "You have a pending delivery to accept", orderId);
    }

    // ---- Driver accept/reject/pickup/deliver (Stories 6.4, 6.7) ----------------------------
    @Transactional(readOnly = true)
    public List<Map<String, Object>> driverJobs(UUID driverId) {
        return jdbc.query(
            "SELECT d.order_id, d.state, d.timing, d.dest_address, d.dest_lat, d.dest_lng, sh.name AS shop_name "
            + "FROM delivery d JOIN shop sh ON sh.id = d.shop_id "
            + "WHERE d.driver_id = ? AND d.state IN ('assigned','accepted','picked_up') ORDER BY d.assigned_at",
            (rs, i) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("orderId", rs.getObject("order_id").toString());
                m.put("state", rs.getString("state"));
                m.put("timing", rs.getString("timing"));
                m.put("pickupStore", rs.getString("shop_name"));
                m.put("destination", rs.getString("dest_address"));
                m.put("destLat", rs.getObject("dest_lat"));
                m.put("destLng", rs.getObject("dest_lng"));
                return m;
            }, driverId);
    }

    @Transactional
    public void accept(UUID driverId, UUID orderId) {
        requireDriverState(driverId, orderId, "assigned");
        transition(orderId, "accepted");
        jdbc.update("UPDATE delivery SET accepted_at = now() WHERE order_id = ?", orderId);
        outbox.emitNotification(customerOf(orderId), "DriverAccepted", "delivery",
            "Driver assigned", "A driver accepted your delivery", orderId);
    }

    @Transactional
    public void reject(UUID driverId, UUID orderId) {
        requireDriverState(driverId, orderId, "assigned");
        jdbc.update("UPDATE delivery SET driver_id = NULL, assigned_at = NULL WHERE order_id = ?", orderId);
        transition(orderId, "ready");   // back to the dispatch queue for reassignment
        outbox.emitNotification(shopOwnerOf(orderId), "DriverRejected", "delivery",
            "Driver rejected job", "A driver rejected a delivery; please reassign", orderId);
    }

    @Transactional
    public void pickedUp(UUID driverId, UUID orderId) {
        requireDriverState(driverId, orderId, "accepted");
        transition(orderId, "picked_up");
        jdbc.update("UPDATE delivery SET picked_up_at = now() WHERE order_id = ?", orderId);
        outbox.emitNotification(customerOf(orderId), "OrderOnTheWay", "delivery",
            "On the way", "Your order is on the way", orderId);
    }

    @Transactional
    public void deliver(UUID driverId, UUID orderId) {
        requireDriverState(driverId, orderId, "picked_up");
        transition(orderId, "delivered");
        jdbc.update("UPDATE delivery SET delivered_at = now() WHERE order_id = ?", orderId);
        outbox.emitNotification(customerOf(orderId), "OrderDelivered", "delivery",
            "Delivered", "Your order has been delivered", orderId);
        outbox.emitNotification(shopOwnerOf(orderId), "OrderDelivered", "delivery",
            "Order delivered", "An order was delivered", orderId);
        // final tracking frame so a subscribed customer view closes out cleanly
        stomp.convertAndSend("/topic/orders/" + orderId + "/tracking",
            (Object) Map.of("orderId", orderId.toString(), "state", "delivered"));
    }

    // ---- Consent + GPS ingest (Story 6.5) --------------------------------------------------
    @Transactional
    public void setConsent(UUID driverId, UUID orderId, boolean consent) {
        requireDriver(driverId, orderId);
        jdbc.update("UPDATE delivery SET consent_location = ? WHERE order_id = ?", consent, orderId);
    }

    @Transactional
    public void ingestLocation(UUID driverId, UUID orderId, double lat, double lng) {
        Map<String, Object> d = deliveryRow(orderId);
        if (!driverId.equals(d.get("driver_id"))) throw ApiException.forbidden("not your delivery");
        boolean active = List.of("accepted", "picked_up").contains((String) d.get("state"));
        if (!Boolean.TRUE.equals(d.get("consent_location")) || !active) {
            throw ApiException.forbidden("location sharing requires consent and an active delivery");   // NFR-PRIV-01
        }
        jdbc.update("INSERT INTO driver_location (order_id, driver_id, lat, lng) VALUES (?, ?, ?, ?)",
            orderId, driverId, lat, lng);
        Map<String, Object> frame = new LinkedHashMap<>();
        frame.put("orderId", orderId.toString());
        frame.put("lat", lat);
        frame.put("lng", lng);
        frame.put("state", d.get("state"));
        Object eta = etaMinutes(lat, lng, (Double) d.get("dest_lat"), (Double) d.get("dest_lng"));
        if (eta != null) frame.put("etaMinutes", eta);
        stomp.convertAndSend("/topic/orders/" + orderId + "/tracking", (Object) frame);   // live fan-out (Story 6.6)
    }

    // ---- Customer tracking (Story 6.6 REST fallback) ---------------------------------------
    @Transactional(readOnly = true)
    public Map<String, Object> tracking(UUID requesterId, boolean isAdmin, UUID orderId) {
        Map<String, Object> d = deliveryRow(orderId);
        UUID customer = customerOf(orderId);
        boolean allowed = isAdmin || requesterId.equals(customer) || requesterId.equals(d.get("driver_id"))
            || requesterId.equals(shopOwnerOf(orderId));
        if (!allowed) throw ApiException.forbidden("not allowed to track this order");   // access control

        String state = (String) d.get("state");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("orderId", orderId.toString());
        out.put("state", state);
        out.put("orderStatus", orderStatusFor(state));
        if ("delivered".equals(state)) { out.put("phase", "delivered"); return out; }
        Map<String, Object> last = jdbc.query(
            "SELECT lat, lng, recorded_at FROM driver_location WHERE order_id = ? ORDER BY recorded_at DESC LIMIT 1",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("lat", rs.getDouble("lat"));
                m.put("lng", rs.getDouble("lng"));
                m.put("recordedAt", rs.getTimestamp("recorded_at").toInstant().toString());
                return m;
            }, orderId);
        if (last == null) { out.put("phase", "driver_not_en_route"); return out; }
        out.put("phase", "en_route");
        out.put("location", last);
        Object eta = etaMinutes((Double) last.get("lat"), (Double) last.get("lng"),
            (Double) d.get("dest_lat"), (Double) d.get("dest_lng"));
        if (eta != null) out.put("etaMinutes", eta);
        return out;
    }

    // ---- Driver roster (supports Story 6.3) ------------------------------------------------
    @Transactional
    public Map<String, Object> addDriver(UUID shopOwnerId, String email, String password, String displayName) {
        UUID shopId = ownShop(shopOwnerId);
        if (email == null || email.isBlank() || password == null || password.length() < 8) {
            throw ApiException.badRequest("driver email and a password (>=8 chars) are required");
        }
        UUID driverId = jdbc.query("SELECT id FROM app_user WHERE email = ?",
            rs -> rs.next() ? (UUID) rs.getObject("id") : null, email.toLowerCase());
        if (driverId == null) {
            driverId = jdbc.queryForObject(
                "INSERT INTO app_user (email, display_name, password_hash) VALUES (?, ?, ?) RETURNING id",
                UUID.class, email.toLowerCase(), displayName, encoder.encode(password));
        }
        jdbc.update("INSERT INTO user_role (user_id, role) VALUES (?, 'DRIVER') ON CONFLICT DO NOTHING", driverId);
        try {
            jdbc.update("INSERT INTO shop_driver (shop_id, driver_id) VALUES (?, ?)", shopId, driverId);
        } catch (DuplicateKeyException dup) { /* already on roster */ }
        return Map.of("driverId", driverId.toString());
    }

    // ---- Scheduled jobs --------------------------------------------------------------------
    /** Scheduled orders enter the dispatch queue as their slot start approaches (Story 6.3). */
    @Transactional
    public int promoteScheduledToReady() {
        List<UUID> due = jdbc.queryForList(
            "SELECT d.order_id FROM delivery d JOIN orders o ON o.id = d.order_id JOIN delivery_slot s ON s.id = d.slot_id "
            + "WHERE d.state = 'pending' AND d.timing = 'scheduled' AND o.payment_status = 'paid' "
            + "AND s.window_start <= now() + (? * interval '1 minute')",
            UUID.class, slotReadyLeadMinutes);
        for (UUID id : due) transition(id, "ready");
        return due.size();
    }

    /** Purge GPS fixes for deliveries completed beyond the retention window (NFR-PRIV-01). */
    @Transactional
    public int purgeOldLocations(int retentionHours) {
        return jdbc.update(
            "DELETE FROM driver_location dl USING delivery d WHERE dl.order_id = d.order_id "
            + "AND d.state = 'delivered' AND d.delivered_at < now() - (? * interval '1 hour')", retentionHours);
    }

    // ---- helpers ---------------------------------------------------------------------------
    private Double storeDistanceMeters(UUID storeId, double lat, double lng) {
        return jdbc.query(
            "SELECT ST_Distance(location, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography) "
            + "FROM shop WHERE id = ? AND location IS NOT NULL",
            rs -> rs.next() ? rs.getDouble(1) : null, lng, lat, storeId);
    }

    private Object etaMinutes(Double fromLat, Double fromLng, Double toLat, Double toLng) {
        if (fromLat == null || fromLng == null || toLat == null || toLng == null) return null;
        Double meters = jdbc.queryForObject(
            "SELECT ST_Distance(ST_SetSRID(ST_MakePoint(?, ?),4326)::geography, ST_SetSRID(ST_MakePoint(?, ?),4326)::geography)",
            Double.class, fromLng, fromLat, toLng, toLat);
        double minutes = (meters / 1000.0) / 30.0 * 60.0;   // assume 30 km/h
        return Math.max(1, Math.round(minutes));
    }

    private static double round1(double v) {
        return BigDecimal.valueOf(v).setScale(1, RoundingMode.HALF_UP).doubleValue();
    }

    private UUID ownShop(UUID ownerId) {
        UUID id = jdbc.query("SELECT id FROM shop WHERE owner_id = ?",
            rs -> rs.next() ? (UUID) rs.getObject("id") : null, ownerId);
        if (id == null) throw ApiException.notFound("you do not own a shop");
        return id;
    }

    private Map<String, Object> orderRow(UUID orderId) {
        Map<String, Object> o = jdbc.query(
            "SELECT store_id, currency, delivery_fee, delivery_address, delivery_lat, delivery_lng FROM orders WHERE id = ?",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("store_id", rs.getObject("store_id"));
                m.put("currency", rs.getString("currency"));
                m.put("delivery_fee", rs.getBigDecimal("delivery_fee"));
                m.put("delivery_address", rs.getString("delivery_address"));
                m.put("delivery_lat", rs.getObject("delivery_lat"));
                m.put("delivery_lng", rs.getObject("delivery_lng"));
                return m;
            }, orderId);
        if (o == null) throw ApiException.notFound("order not found");
        return o;
    }

    private Map<String, Object> deliveryRow(UUID orderId) {
        Map<String, Object> d = jdbc.query(
            "SELECT shop_id, state, driver_id, consent_location, dest_lat, dest_lng FROM delivery WHERE order_id = ?",
            rs -> {
                if (!rs.next()) return null;
                Map<String, Object> m = new java.util.HashMap<>();
                m.put("shop_id", rs.getObject("shop_id"));
                m.put("state", rs.getString("state"));
                m.put("driver_id", rs.getObject("driver_id"));
                m.put("consent_location", rs.getBoolean("consent_location"));
                m.put("dest_lat", rs.getObject("dest_lat"));
                m.put("dest_lng", rs.getObject("dest_lng"));
                return m;
            }, orderId);
        if (d == null) throw ApiException.notFound("delivery not found");
        return d;
    }

    private void requireDriver(UUID driverId, UUID orderId) {
        Map<String, Object> d = deliveryRow(orderId);
        if (!driverId.equals(d.get("driver_id"))) throw ApiException.forbidden("not your delivery");
    }

    private void requireDriverState(UUID driverId, UUID orderId, String expected) {
        Map<String, Object> d = deliveryRow(orderId);
        if (!driverId.equals(d.get("driver_id"))) throw ApiException.forbidden("not your delivery");
        if (!expected.equals(d.get("state"))) {
            throw ApiException.conflict("job no longer available (state is " + d.get("state") + ")");
        }
    }

    private UUID customerOf(UUID orderId) {
        return jdbc.queryForObject("SELECT customer_id FROM orders WHERE id = ?", UUID.class, orderId);
    }

    private UUID shopOwnerOf(UUID orderId) {
        return jdbc.queryForObject(
            "SELECT s.owner_id FROM orders o JOIN shop s ON s.id = o.store_id WHERE o.id = ?", UUID.class, orderId);
    }
}
