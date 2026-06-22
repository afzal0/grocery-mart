package com.grocerymart.api.identity;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.identity.AuthDtos.AuthResponse;
import com.grocerymart.api.identity.AuthDtos.LogoutRequest;
import com.grocerymart.api.identity.AuthDtos.OtpRequest;
import com.grocerymart.api.identity.AuthDtos.OtpVerifyRequest;
import com.grocerymart.api.identity.AuthDtos.PortalLoginRequest;
import com.grocerymart.api.identity.AuthDtos.RefreshRequest;
import com.grocerymart.api.identity.AuthDtos.RegisterRequest;
import com.grocerymart.api.identity.AuthDtos.ResetConfirmRequest;
import com.grocerymart.api.identity.AuthDtos.ResetRequest;

import jakarta.validation.Valid;

/** Authentication endpoints (Epic 2). All public. */
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final AuthService auth;

    public AuthController(AuthService auth) {
        this.auth = auth;
    }

    // Story 2.2 — phone OTP
    @PostMapping("/otp/request")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public void requestOtp(@Valid @RequestBody OtpRequest req) {
        auth.requestOtp(req.phone());
    }

    @PostMapping("/otp/verify")
    public AuthResponse verifyOtp(@Valid @RequestBody OtpVerifyRequest req) {
        return auth.verifyOtp(req.phone(), req.code());
    }

    // Story 2.4 — portal email + password
    @PostMapping("/portal/login")
    public AuthResponse portalLogin(@Valid @RequestBody PortalLoginRequest req) {
        return auth.portalLogin(req.email(), req.password());
    }

    @PostMapping("/password/reset/request")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public void requestReset(@Valid @RequestBody ResetRequest req) {
        auth.requestPasswordReset(req.email());
    }

    @PostMapping("/password/reset/confirm")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void confirmReset(@Valid @RequestBody ResetConfirmRequest req) {
        auth.confirmPasswordReset(req.token(), req.newPassword());
    }

    // Story 2.7 — restricted registration
    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    public AuthResponse register(@Valid @RequestBody RegisterRequest req) {
        return auth.register(req.email(), req.password(), req.role(), req.displayName());
    }

    // Story 2.6 — session lifecycle
    @PostMapping("/refresh")
    public AuthResponse refresh(@Valid @RequestBody RefreshRequest req) {
        return auth.refresh(req.refreshToken());
    }

    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void logout(@Valid @RequestBody LogoutRequest req) {
        auth.logout(req.refreshToken());
    }
}
