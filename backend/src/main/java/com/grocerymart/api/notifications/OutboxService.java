package com.grocerymart.api.notifications;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import tools.jackson.databind.ObjectMapper;

/**
 * Transactional outbox writer (AR-05). Domain modules call this in the SAME transaction as their
 * state change; the {@link NotificationConsumer} relay publishes rows at-least-once. Notification
 * events carry the resolved recipient in the payload so the consumer stays generic.
 */
@Service
public class OutboxService {

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;

    public OutboxService(JdbcTemplate jdbc, ObjectMapper mapper) {
        this.jdbc = jdbc;
        this.mapper = mapper;
    }

    /** Generic domain event (e.g. ReviewCreated) used to drive read-model recompute. */
    public void emit(String aggregate, UUID aggregateId, String type, Map<String, Object> payload) {
        jdbc.update("INSERT INTO outbox_event (aggregate, aggregate_id, type, payload) VALUES (?, ?, ?, ?::jsonb)",
            aggregate, aggregateId, type, mapper.writeValueAsString(payload));
    }

    /** A notification event targeting one recipient. category drives opt-out (Story 7.6). */
    public void emitNotification(UUID recipientId, String type, String category, String title, String body,
                                 UUID orderId) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("recipientId", recipientId.toString());
        payload.put("category", category);
        payload.put("title", title);
        payload.put("body", body);
        if (orderId != null) payload.put("orderId", orderId.toString());
        emit("notification", orderId != null ? orderId : recipientId, type, payload);
    }
}
