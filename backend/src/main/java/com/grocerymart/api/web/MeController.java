package com.grocerymart.api.web;

import java.util.List;
import java.util.Map;

import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Returns the authenticated principal — a protected endpoint proving the JWT works. */
@RestController
@RequestMapping("/api/v1")
public class MeController {

    @GetMapping("/me")
    public Map<String, Object> me(Authentication auth) {
        List<String> roles = auth.getAuthorities().stream().map(Object::toString).toList();
        return Map.of("userId", auth.getName(), "roles", roles);
    }
}
