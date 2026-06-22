-- Transactional outbox scaffold (AR-05 / NFR-AVL-03).
-- Domain modules write events here in the SAME transaction as their state change; a
-- relay (added with notifications/read-model consumers in later epics) publishes
-- unpublished rows at-least-once. bigint identity PK for a high-insert append table;
-- a stable event_id for idempotent consumers.
CREATE TABLE outbox_event (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id      uuid        NOT NULL DEFAULT gen_random_uuid(),
    aggregate     text        NOT NULL,            -- e.g. 'order', 'store_product'
    aggregate_id  uuid        NOT NULL,
    type          text        NOT NULL,            -- e.g. 'OrderConfirmed'
    payload       jsonb       NOT NULL,
    occurred_at   timestamptz NOT NULL DEFAULT now(),
    published_at  timestamptz,                     -- NULL until published
    attempts      int         NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX ux_outbox_event_id ON outbox_event (event_id);
-- Relay scans only the unpublished tail.
CREATE INDEX idx_outbox_unpublished ON outbox_event (occurred_at) WHERE published_at IS NULL;
