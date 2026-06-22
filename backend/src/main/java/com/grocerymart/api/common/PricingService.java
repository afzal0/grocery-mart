package com.grocerymart.api.common;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/**
 * Single source of truth for derived money: distance-based delivery fee (PostGIS) and the
 * tax-inclusive GST component. Every value is scale-2 HALF_UP so displayed components sum
 * exactly to the grand total (Story 5.3).
 */
@Service
public class PricingService {

    private final JdbcTemplate jdbc;
    private final BigDecimal deliveryBase;
    private final BigDecimal deliveryPerKm;
    private final BigDecimal gstRate;

    public PricingService(JdbcTemplate jdbc,
                          @Value("${grocerymart.pricing.delivery-base}") BigDecimal deliveryBase,
                          @Value("${grocerymart.pricing.delivery-per-km}") BigDecimal deliveryPerKm,
                          @Value("${grocerymart.pricing.gst-rate}") BigDecimal gstRate) {
        this.jdbc = jdbc;
        this.deliveryBase = deliveryBase;
        this.deliveryPerKm = deliveryPerKm;
        this.gstRate = gstRate;
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
