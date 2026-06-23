-- Security hardening round 2 (audit 2026-06-23, findings L-1/L-2/M-12).

-- L-1: per-account login-failure lockout. Tracks consecutive failures and a lockout window so
-- credential brute force is bounded even if the IP-based rate limiter is evaded.
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS failed_login_count integer NOT NULL DEFAULT 0;
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS locked_until timestamptz;

-- L-2: revoke access tokens on logout / password reset. A stateless JWT is accepted only if its
-- issued-at is >= the user's tokens_valid_from; logout and password-reset bump this to now(),
-- immediately invalidating every outstanding access token for that user.
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS tokens_valid_from timestamptz NOT NULL DEFAULT now();

-- M-12: cover foreign-key / reverse-join columns that were doing sequential scans.
CREATE INDEX IF NOT EXISTS ix_cart_store_id              ON cart(store_id);
CREATE INDEX IF NOT EXISTS ix_order_item_store_product   ON order_item(store_product_id);
CREATE INDEX IF NOT EXISTS ix_wallet_txn_customer        ON wallet_transaction(customer_id);
CREATE INDEX IF NOT EXISTS ix_payment_intent_customer    ON payment_intent(customer_id);
CREATE INDEX IF NOT EXISTS ix_stock_reservation_sp       ON stock_reservation(store_product_id);
CREATE INDEX IF NOT EXISTS ix_notification_user          ON notification(user_id);
