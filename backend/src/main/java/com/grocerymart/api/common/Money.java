package com.grocerymart.api.common;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * A money amount is ALWAYS (amount, currency). There is no scalar money in this system and
 * no operation aggregates across currencies (AR-12). Amounts are scale-2, HALF_UP.
 */
public record Money(BigDecimal amount, String currency) {

    public static Money of(BigDecimal amount, String currency) {
        return new Money(scale(amount), currency);
    }

    public static BigDecimal scale(BigDecimal v) {
        return v.setScale(2, RoundingMode.HALF_UP);
    }
}
