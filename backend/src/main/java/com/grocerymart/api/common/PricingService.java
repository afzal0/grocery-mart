package com.grocerymart.api.common;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/**
 * Single source of truth for derived money: distance-based delivery fee (PostGIS), the
 * tax-inclusive GST component, the flat platform fee, and the normalized display price.
 * Every value is scale-2 HALF_UP so displayed components sum exactly to the grand total
 * (Story 5.3).
 */
@Service
public class PricingService {

    private final JdbcTemplate jdbc;
    private final BigDecimal deliveryBase;
    private final BigDecimal deliveryPerKm;
    private final BigDecimal gstRate;
    private final BigDecimal platformFee;
    private final double displayRadiusMeters;

    public PricingService(JdbcTemplate jdbc,
                          @Value("${grocerymart.pricing.delivery-base}") BigDecimal deliveryBase,
                          @Value("${grocerymart.pricing.delivery-per-km}") BigDecimal deliveryPerKm,
                          @Value("${grocerymart.pricing.gst-rate}") BigDecimal gstRate,
                          @Value("${grocerymart.pricing.platform-fee}") BigDecimal platformFee,
                          @Value("${grocerymart.pricing.display-radius-km}") double displayRadiusKm) {
        this.jdbc = jdbc;
        this.deliveryBase = deliveryBase;
        this.deliveryPerKm = deliveryPerKm;
        this.gstRate = gstRate;
        this.platformFee = platformFee.setScale(2, RoundingMode.HALF_UP);
        this.displayRadiusMeters = displayRadiusKm * 1000d;
    }

    /** Flat service and platform fee charged once per order, shown as its own checkout line. */
    public BigDecimal platformFee() {
        return platformFee;
    }

    /**
     * Normalized display price per canonical product: the HIGHEST price among stores within the
     * display radius of the customer, so a cheaper vendor's price is never revealed. Returns an
     * empty map when the customer has no coordinates (callers then fall back to the store's own
     * price) or when no ids are requested.
     *
     * <p>One grouped query for the whole basket — deliberately not the per-store loop the removed
     * basket comparison used.
     */
    public Map<UUID, BigDecimal> displayPrices(Collection<UUID> canonicalIds, Double lat, Double lng) {
        Map<UUID, BigDecimal> out = new HashMap<>();
        if (canonicalIds == null || canonicalIds.isEmpty() || lat == null || lng == null) return out;
        String idsCsv = String.join(",", canonicalIds.stream().filter(java.util.Objects::nonNull)
            .map(UUID::toString).distinct().toList());
        if (idsCsv.isEmpty()) return out;
        jdbc.query(
            "SELECT sp.canonical_product_id AS cid, MAX(sp.price_amount) AS max_price "
            + "FROM store_product sp JOIN shop s ON s.id = sp.shop_id "
            + "WHERE s.status = 'active' AND s.location IS NOT NULL "
            + "AND ST_DWithin(s.location, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?) "
            + "AND sp.match_status IN ('auto_linked','merged_confirmed') AND sp.stock > 0 "
            + "AND sp.canonical_product_id = ANY(string_to_array(?, ',')::uuid[]) "
            + "GROUP BY sp.canonical_product_id",
            rs -> { out.put((UUID) rs.getObject("cid"), rs.getBigDecimal("max_price")); },
            lng, lat, displayRadiusMeters, idsCsv);
        return out;
    }

    /**
     * The price to charge for one unit: the in-radius maximum, floored at the fulfilling store's
     * own price. The floor matters because delivery reaches 25 km while the display radius is
     * 10 km — without it a store outside the customer's circle could be charged below its own
     * price, making the margin and the loyalty credit negative.
     */
    public BigDecimal displayPrice(BigDecimal storePrice, BigDecimal maxInRadius) {
        BigDecimal own = storePrice.setScale(2, RoundingMode.HALF_UP);
        if (maxInRadius == null) return own;
        BigDecimal max = maxInRadius.setScale(2, RoundingMode.HALF_UP);
        return max.compareTo(own) > 0 ? max : own;
    }

    /**
     * Distance-based fee = base + perKm * km(store, deliveryPoint). Falls back to the flat base
     * when either endpoint lacks coordinates. The full PostGIS slot/zone model arrives in Epic 6.
     */
    public BigDecimal deliveryFee(UUID storeId, Double lat, Double lng) {
        BigDecimal fee = deliveryBase;
        if (lat != null && lng != null) {
            Double meters = jdbc.query(
                "SELECT ST_Distance(location, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography) "
                + "FROM shop WHERE id = ? AND location IS NOT NULL",
                rs -> rs.next() ? rs.getDouble(1) : null,
                lng, lat, storeId);
            if (meters != null) {
                BigDecimal km = BigDecimal.valueOf(meters).divide(BigDecimal.valueOf(1000), 4, RoundingMode.HALF_UP);
                fee = deliveryBase.add(deliveryPerKm.multiply(km));
            }
        }
        return fee.setScale(2, RoundingMode.HALF_UP);
    }

    /** Tax-inclusive GST component of a gross total: gross * rate/(1+rate). */
    public BigDecimal gstInclusive(BigDecimal grossTotal) {
        BigDecimal factor = gstRate.divide(BigDecimal.ONE.add(gstRate), 10, RoundingMode.HALF_UP);
        return grossTotal.multiply(factor).setScale(2, RoundingMode.HALF_UP);
    }
}
