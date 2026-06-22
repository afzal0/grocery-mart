package com.grocerymart.api.identity;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.grocerymart.api.identity.AuthDtos.AuthResponse;
import com.grocerymart.api.identity.AuthDtos.OtpRequest;
import com.grocerymart.api.identity.AuthDtos.OtpVerifyRequest;

import jakarta.validation.Valid;

/** Phone-OTP sign-in (Story 2.2). Public endpoints. */
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final AuthService auth;

    public AuthController(AuthService auth) {
        this.auth = auth;
    }

    /** Request a one-time code for a phone number. The code is delivered out-of-band (dev: logged). */
    @PostMapping("/otp/request")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public void requestOtp(@Valid @RequestBody OtpRequest req) {
        auth.requestOtp(req.phone());
    }

    /** Verify the code; on success returns an access token + rotating refresh token. */
    @PostMapping("/otp/verify")
    public AuthResponse verifyOtp(@Valid @RequestBody OtpVerifyRequest req) {
        return auth.verifyOtp(req.phone(), req.code());
    }
}
