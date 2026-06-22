-- Epic 5: ordering + payments. The ORDER is the aggregate root — one order = one store =
-- one delivery = one payment (no order_group, AR-12). All money is (amount, currency); a
-- cart/order is bound to a single currency and never aggregates across currencies.

-- Stores can be open/closed independent of admin approval; checkout rejects a closed store.
ALTER TABLE shop ADD COLUMN is_open boolean NOT NULL DEFAULT true;

-- ---- Cart: at most one active cart per (customer, store). Single store, single currency.
CREATE TABLE cart (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id  uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    store_id     uuid NOT NULL REFERENCES shop(id) ON DELETE CASCADE,
    currency     text NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (customer_id, store_id)
);

CREATE TABLE cart_line (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cart_id              uuid NOT NULL REFERENCES cart(id) ON DELETE CASCADE,
    store_product_id     uuid NOT NULL REFERENCES store_product(id),
    canonical_product_id uuid,
    qty                  int NOT NULL CHECK (qty > 0),
    unit_price_amount    numeric(12,2) NOT NULL,        -- price-at-resolution (incl. substitution price)
    currency             text NOT NULL,
    is_substitution      boolean NOT NULL DEFAULT false,
    created_at           timestamptz NOT NULL DEFAULT now(),
    UNIQUE (cart_id, store_product_id)
);
CREATE INDEX idx_cart_line_cart ON cart_line (cart_id);

-- ---- Order aggregate root.
CREATE TABLE orders (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id       uuid NOT NULL REFERENCES app_user(id),
    store_id          uuid NOT NULL REFERENCES shop(id),
    currency          text NOT NULL,
    payment_status    text NOT NULL DEFAULT 'pending_payment',  -- pending_payment | paid | refunded
    status            text NOT NULL DEFAULT 'pending',          -- Pending|Processing|On the Way|Delivered|Cancelled (R21)
    items_subtotal    numeric(12,2) NOT NULL,
    delivery_fee      numeric(12,2) NOT NULL DEFAULT 0,
    gst_amount        numeric(12,2) NOT NULL DEFAULT 0,         -- tax-inclusive component of grand_total
    grand_total       numeric(12,2) NOT NULL,
    delivery_address  text,
    delivery_lat      double precision,
    delivery_lng      double precision,
    payment_method    text,                                     -- wallet | card
    idempotency_key   text UNIQUE,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_orders_customer ON orders (customer_id, created_at DESC);
CREATE INDEX idx_orders_store ON orders (store_id, created_at DESC);

CREATE TABLE order_item (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id             uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    store_product_id     uuid NOT NULL REFERENCES store_product(id),
    canonical_product_id uuid,
    name_snapshot        text NOT NULL,
    qty                  int NOT NULL CHECK (qty > 0),
    unit_price_amount    numeric(12,2) NOT NULL,                -- price snapshot at placement
    currency             text NOT NULL
);
CREATE INDEX idx_order_item_order ON order_item (order_id);

-- ---- Wallet: one balance row per (customer, currency); CHECK keeps it non-negative.
CREATE TABLE wallet (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id    uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    currency       text NOT NULL,
    balance_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (balance_amount >= 0),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (customer_id, currency)
);

-- Append-only money ledger for the wallet (never updated, only inserted).
CREATE TABLE wallet_transaction (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id       uuid NOT NULL REFERENCES wallet(id) ON DELETE CASCADE,
    customer_id     uuid NOT NULL,
    type            text NOT NULL,                  -- credit | debit
    amount          numeric(12,2) NOT NULL CHECK (amount > 0),
    currency        text NOT NULL,
    reason          text NOT NULL,                  -- topup | order_payment | refund
    order_id        uuid,
    stripe_event_id text,
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_wallet_txn_wallet ON wallet_transaction (wallet_id, created_at DESC);
-- One debit per order (idempotent wallet payment); one refund credit per order.
CREATE UNIQUE INDEX ux_wallet_txn_order_reason ON wallet_transaction (order_id, reason)
    WHERE order_id IS NOT NULL;

-- ---- Payment intents (Stripe). order_id null => wallet top-up. Manual capture for cards.
CREATE TABLE payment_intent (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id           uuid REFERENCES orders(id) ON DELETE CASCADE,
    customer_id        uuid NOT NULL,
    purpose            text NOT NULL DEFAULT 'order',  -- order | wallet_topup
    provider           text NOT NULL DEFAULT 'stripe',
    provider_intent_id text NOT NULL UNIQUE,
    amount             numeric(12,2) NOT NULL,
    currency           text NOT NULL,
    capture_method     text NOT NULL DEFAULT 'manual',
    status             text NOT NULL DEFAULT 'requires_payment', -- requires_payment|authorized|captured|canceled|succeeded
    created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_payment_intent_order ON payment_intent (order_id);

-- Webhook idempotency: every Stripe event id is processed exactly once.
CREATE TABLE processed_stripe_event (
    stripe_event_id text PRIMARY KEY,
    event_type      text NOT NULL,
    processed_at    timestamptz NOT NULL DEFAULT now()
);

-- Stock reservations for card flow (authorize -> reserve -> capture). Sweeper releases expired.
CREATE TABLE stock_reservation (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id         uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    store_product_id uuid NOT NULL REFERENCES store_product(id),
    qty              int NOT NULL,
    status           text NOT NULL DEFAULT 'reserved',  -- reserved | released | captured
    expires_at       timestamptz NOT NULL,
    created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_reservation_open ON stock_reservation (expires_at) WHERE status = 'reserved';

-- ---- Per-store settlement ledger: one 'charge' per paid order, one 'reversal' on refund.
CREATE TABLE settlement_ledger (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id      uuid NOT NULL REFERENCES orders(id),
    store_id      uuid NOT NULL REFERENCES shop(id),
    entry_type    text NOT NULL,                  -- charge | reversal
    order_total   numeric(12,2) NOT NULL,
    gst_amount    numeric(12,2) NOT NULL,
    platform_fee  numeric(12,2) NOT NULL DEFAULT 0,
    currency      text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
);
-- Exactly one entry of each type per order (idempotent settlement + refund reversal).
CREATE UNIQUE INDEX ux_settlement_order_type ON settlement_ledger (order_id, entry_type);
CREATE INDEX idx_settlement_store ON settlement_ledger (store_id, created_at DESC);
