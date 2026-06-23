package com.grocerymart.api.config;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

/**
 * Epic 6 (Story 6.6): STOMP over WebSocket for live driver tracking. Driver GPS fixes are fanned
 * out to {@code /topic/orders/{orderId}/tracking}. A single in-memory simple broker is used now;
 * the Redis relay for multi-instance fan-out is an Epic 9 hardening swap. The REST polling endpoint
 * is the always-on fallback (NFR-AVL-02).
 *
 * <p>Security hardening: the client inbound channel is guarded by {@link StompAuthChannelInterceptor}
 * (JWT on CONNECT + per-SUBSCRIBE order-ownership authorization), and origins are restricted to the
 * known frontends instead of {@code *}.
 */
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    /** Same allowlist source as HTTP CORS (GROCERYMART_CORS_ORIGINS); local dev origins always allowed. */
    @Value("${grocerymart.cors.origins:}")
    private String extraOrigins;

    private final StompAuthChannelInterceptor authInterceptor;

    public WebSocketConfig(StompAuthChannelInterceptor authInterceptor) {
        this.authInterceptor = authInterceptor;
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        registry.enableSimpleBroker("/topic");
        registry.setApplicationDestinationPrefixes("/app");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        String[] origins = allowedOrigins();
        registry.addEndpoint("/ws").setAllowedOriginPatterns(origins).withSockJS();
        registry.addEndpoint("/ws").setAllowedOriginPatterns(origins);
    }

    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        registration.interceptors(authInterceptor);
    }

    private String[] allowedOrigins() {
        List<String> patterns = new ArrayList<>(List.of(
            "http://localhost:5173", "http://localhost:5174", "http://localhost:5180", "http://localhost:5181"));
        if (extraOrigins != null && !extraOrigins.isBlank()) {
            Arrays.stream(extraOrigins.split(",")).map(String::trim).filter(s -> !s.isEmpty()).forEach(patterns::add);
        }
        return patterns.toArray(String[]::new);
    }
}
