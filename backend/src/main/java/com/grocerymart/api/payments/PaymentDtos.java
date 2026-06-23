package com.grocerymart.api.payments;

import java.math.BigDecimal;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;

public final class PaymentDtos {
    private PaymentDtos() {}

    public record TopupRequest(
        @NotNull @Positive
        @Digits(integer = 8, fraction = 2)            // money: scale 2, prevents precision drift vs numeric(12,2)
        @DecimalMax(value = "99999.99", message = "amount exceeds the per-topup maximum")
        BigDecimal amount,
        @NotBlank
        @Pattern(regexp = "^[A-Z]{3}$", message = "currency must be a 3-letter ISO-4217 code")
        String currency) {}

    public record PayOrderRequest(@NotBlank String orderId) {}
}
