-- Epic 7: purchase-gated reviews, rating read-model aggregates, FCM device tokens,
-- notification preferences, and outbox-driven in-app notifications with dedup.

-- Reviews are keyed to the SHARED canonical product (cross-store identity), one per customer.
CREATE TABLE reviews (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    canonical_product_id uuid NOT NULL REFERENCES canonical_product(id) ON DELETE CASCADE,
    customer_id          uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    rating               int NOT NULL CHECK (rating BETWEEN 1 AND 5),
    body                 text,
    deleted_at           timestamptz,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    UNIQUE (canonical_product_id, customer_id)
);
CREATE INDEX idx_reviews_canonical ON reviews (canonical_product_id, created_at DESC) WHERE deleted_at IS NULL;

-- Read-model aggregates recomputed (idempotently) by the outbox consumer from reviews rows.
CREATE TABLE product_rating_aggregate (
    canonical_product_id uuid PRIMARY KEY REFERENCES canonical_product(id) ON DELETE CASCADE,
    avg_rating           numeric(2,1) NOT NULL DEFAULT 0,
    review_count         int NOT NULL DEFAULT 0,
    updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE store_rating_aggregate (
    shop_id      uuid PRIMARY KEY REFERENCES shop(id) ON DELETE CASCADE,
    avg_rating   numeric(2,1) NOT NULL DEFAULT 0,
    review_count int NOT NULL DEFAULT 0,
    updated_at   timestamptz NOT NULL DEFAULT now()
);

-- FCM device tokens (per user, per device). Only 'active' tokens are targeted.
CREATE TABLE device_tokens (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    fcm_token    text NOT NULL UNIQUE,
    platform     text,
    app_id       text,
    status       text NOT NULL DEFAULT 'active',   -- active | expired
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_device_tokens_user ON device_tokens (user_id) WHERE status = 'active';

-- Per-user push opt-out, by category. Absence of a row means opted-in (default).
CREATE TABLE notification_preferences (
    user_id      uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    category     text NOT NULL,
    push_enabled boolean NOT NULL DEFAULT true,
    updated_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, category)
);

-- Extend the Epic 6 notification table: outbox dedup key + structured data payload.
ALTER TABLE notification ADD COLUMN event_id uuid;
ALTER TABLE notification ADD COLUMN data_json jsonb;
ALTER TABLE notification ADD COLUMN category text;
CREATE UNIQUE INDEX ux_notification_user_event ON notification (user_id, event_id) WHERE event_id IS NOT NULL;
