-- Epic 9: launch hardening — payouts, disputes, immutable audit trail, account-deletion tombstones.

-- Per-shop payouts against the internal settlement ledger (single Stripe account, no Connect).
CREATE TABLE payout (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id      uuid NOT NULL REFERENCES shop(id) ON DELETE CASCADE,
    amount       numeric(12,2) NOT NULL CHECK (amount > 0),
    currency     text NOT NULL,
    period_start date,
    period_end   date,
    status       text NOT NULL DEFAULT 'manual' CHECK (status IN ('pending','paid','manual','failed')),
    reference    text UNIQUE,              -- idempotency key for manual payouts
    reason       text,                     -- non-sensitive failure reason (no Stripe internals)
    note         text,
    paid_at      timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_payout_shop ON payout (shop_id, created_at DESC);

-- Chargebacks/disputes against the single Stripe account (admin-visible).
CREATE TABLE dispute (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id      uuid REFERENCES orders(id),
    shop_id       uuid REFERENCES shop(id),
    amount        numeric(12,2) NOT NULL,
    currency      text NOT NULL,
    status        text NOT NULL DEFAULT 'needs_response',
    evidence_due  timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- Immutable audit trail (Story 9.11). Append-only via the application; the retention purge (9.8)
-- is the only delete path. before/after captured as jsonb summaries.
CREATE TABLE audit_log (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_id      uuid,
    action        text NOT NULL,
    target_type   text,
    target_id     text,
    before_summary jsonb,
    after_summary  jsonb,
    source_ip     text,
    outcome       text NOT NULL DEFAULT 'success',   -- success | denied | failed
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_actor ON audit_log (actor_id, created_at DESC);
CREATE INDEX idx_audit_action ON audit_log (action, created_at DESC);

-- Account deletion / anonymization (Story 9.5). Financial rows are preserved; only PII is tombstoned.
CREATE TABLE deletion_request (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid NOT NULL REFERENCES app_user(id),
    status       text NOT NULL DEFAULT 'completed',
    requested_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);
ALTER TABLE app_user ADD COLUMN deleted_at timestamptz;
ALTER TABLE app_user ADD COLUMN anonymized boolean NOT NULL DEFAULT false;
