package com.grocerymart.api.account;

import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Account self-service: deletion (9.5), data export + correction + privacy policy (9.6). */
@RestController
@RequestMapping("/api/v1")
public class AccountController {

    public record CorrectRequest(String displayName, String country, String currency, String locale) {}

    private final AccountService account;

    public AccountController(AccountService account) {
        this.account = account;
    }

    private static UUID uid(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @DeleteMapping("/account")
    @PreAuthorize("isAuthenticated()")
    public Map<String, Object> delete(Authentication auth) {
        return account.deleteAccount(uid(auth));
    }

    @GetMapping("/account/export")
    @PreAuthorize("isAuthenticated()")
    public Map<String, Object> export(Authentication auth) {
        return account.exportData(uid(auth));
    }

    @PatchMapping("/account")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("isAuthenticated()")
    public void correct(@RequestBody CorrectRequest req, Authentication auth) {
        account.correctProfile(uid(auth), req.displayName(), req.country(), req.currency(), req.locale());
    }

    /** Public — readable logged-in or not (APP requirement). */
    @GetMapping("/privacy")
    public Map<String, Object> privacy() {
        return account.privacyPolicy();
    }
}
