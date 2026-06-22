package com.grocerymart.api.web;

import java.time.Instant;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Walking-skeleton liveness endpoint. Returns the resource directly (no
 * {success,...} envelope) per the project's API conventions.
 */
@RestController
@RequestMapping("/api/v1")
public class PingController {

    public record PingResponse(String status, String service, Instant time) {}

    @GetMapping("/ping")
    public PingResponse ping() {
        return new PingResponse("ok", "grocery-mart-api", Instant.now());
    }
}
