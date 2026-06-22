-- Epic 6: delivery & tracking. A paid order gets a delivery aggregate that moves
-- pending -> ready -> assigned -> accepted -> picked_up -> delivered (reject reverts to ready).
-- order.status (R21: Pending/Processing/On the Way/Delivered/Cancelled) is synced from this state.

-- Bookable delivery slots per shop (window + capacity). booked is incremented atomically.
CREATE TABLE delivery_slot (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id      uuid NOT NULL REFERENCES shop(id) ON DELETE CASCADE,
    window_start timestamptz NOT NULL,
    window_end   timestamptz NOT NULL,
    capacity     int NOT NULL CHECK (capacity > 0),
    booked       int NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CHECK (booked <= capacity)
);
CREATE INDEX idx_slot_shop_window ON delivery_slot (shop_id, window_start);

-- A shop's own driver roster. A driver may only be assigned jobs from a shop they belong to.
CREATE TABLE shop_driver (
    shop_id      uuid NOT NULL REFERENCES shop(id) ON DELETE CASCADE,
    driver_id    uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    is_available boolean NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (shop_id, driver_id)
);

-- Per-order delivery aggregate (1:1 with orders).
CREATE TABLE delivery (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id         uuid NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
    shop_id          uuid NOT NULL REFERENCES shop(id),
    timing           text NOT NULL DEFAULT 'immediate',   -- immediate | scheduled
    slot_id          uuid REFERENCES delivery_slot(id),
    state            text NOT NULL DEFAULT 'pending',     -- pending|ready|assigned|accepted|picked_up|delivered|cancelled
    driver_id        uuid REFERENCES app_user(id),
    fee_amount       numeric(12,2),
    currency         text,
    dest_address     text,
    dest_lat         double precision,
    dest_lng         double precision,
    consent_location boolean NOT NULL DEFAULT false,
    assigned_at      timestamptz,
    accepted_at      timestamptz,
    picked_up_at     timestamptz,
    delivered_at     timestamptz,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_delivery_shop_state ON delivery (shop_id, state);
CREATE INDEX idx_delivery_driver ON delivery (driver_id) WHERE driver_id IS NOT NULL;

-- Driver GPS fixes — sensitive PII: consent-gated on write, access-controlled on read,
-- retention-bounded by a scheduled purge (NFR-PRIV-01).
CREATE TABLE driver_location (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    driver_id   uuid NOT NULL REFERENCES app_user(id),
    lat         double precision NOT NULL,
    lng         double precision NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_driver_location_order ON driver_location (order_id, recorded_at DESC);

-- In-app notifications (shared by delivery dual-notify here and Epic 7).
CREATE TABLE notification (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    type       text NOT NULL,
    title      text NOT NULL,
    body       text,
    order_id   uuid,
    read_at    timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_notification_user ON notification (user_id, created_at DESC);
