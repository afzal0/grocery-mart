package com.grocerymart.api.payments;

import java.math.BigDecimal;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

public final class PaymentDtos {
    private PaymentDtos() {}

    public record TopupRequest(@NotNull @Positive BigDecimal amount, @NotBlank String currency) {}

    public record PayOrderRequest(@NotBlank String orderId) {}
}
