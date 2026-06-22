package com.grocerymart.api.identity;

import java.util.List;

import jakarta.validation.constraints.Email;
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

    public record PortalLoginRequest(
        @NotBlank @Email String email,
        @NotBlank String password) {}

    public record RegisterRequest(
        @NotBlank @Email String email,
        @NotBlank @Size(min = 8, message = "password must be at least 8 characters") String password,
        String role,
        String displayName) {}

    public record RefreshRequest(@NotBlank String refreshToken) {}

    public record LogoutRequest(@NotBlank String refreshToken) {}

    public record ResetRequest(@NotBlank @Email String email) {}

    public record ResetConfirmRequest(
        @NotBlank String token,
        @NotBlank @Size(min = 8) String newPassword) {}

    public record AuthResponse(
        String accessToken,
        String refreshToken,
        String userId,
        List<String> roles) {}
}
