package com.grocerymart.api.identity;

import java.util.List;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/** Request/response payloads for the auth endpoints (camelCase wire shapes). */
public final class AuthDtos {
    private AuthDtos() {}

    public record OtpRequest(
        @NotBlank @Pattern(regexp = "\\+?[0-9]{6,15}", message = "phone must be 6-15 digits") String phone) {}

    public record OtpVerifyRequest(
        @NotBlank String phone,
        @NotBlank @Size(min = 6, max = 6) String code) {}

    public record AuthResponse(
        String accessToken,
        String refreshToken,
        String userId,
        String phone,
        List<String> roles) {}
}
