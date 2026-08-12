-- Single-storefront pivot: display-price normalization, platform fee, loyalty credits.
--
-- The customer is charged a NORMALIZED display price (the max price among stores within the
-- display radius of their location); the fulfilling vendor is settled at their OWN price. The
-- spread is returned to the customer as loyalty credits and recorded here for settlement.
--
-- Column semantics (deliberate, keeps every existing money path working unchanged):
--   order_item.unit_price_amount  = what the customer was CHARGED (display price)
--   order_item.store_unit_price_amount = the vendor's real price
--   orders.items_subtotal         = Σ charged      (so grand_total / wallet debit / Stripe
--   orders.store_items_subtotal   = Σ vendor        amount / refunds need no change at all)
--
-- Settlement commission is derived, never stored twice:
--   settlement_ledger.platform_fee = (items_subtotal − store_items_subtotal) + orders.platform_fee
-- which preserves the existing invariant  net = gross − platform_fee − refunds.

-- ---- orders: charged-vs-vendor decomposition -------------------------------------------
ALTER TABLE orders ADD COLUMN store_items_subtotal numeric(12,2);
ALTER TABLE orders ADD COLUMN platform_fee         numeric(12,2) NOT NULL DEFAULT 0;  -- flat service fee
ALTER TABLE orders ADD COLUMN loyalty_credits      numeric(12,2) NOT NULL DEFAULT 0;  -- = items − store

-- Pre-pivot orders were charged at the vendor's own price, so the two subtotals are equal.
UPDATE orders SET store_items_subtotal = items_subtotal WHERE store_items_subtotal IS NULL;
ALTER TABLE orders ALTER COLUMN store_items_subtotal SET NOT NULL;

ALTER TABLE order_item ADD COLUMN store_unit_price_amount numeric(12,2);
UPDATE order_item SET store_unit_price_amount = unit_price_amount WHERE store_unit_price_amount IS NULL;
ALTER TABLE order_item ALTER COLUMN store_unit_price_amount SET NOT NULL;

-- ---- cart_line: display price stamped at resolve time ----------------------------------
-- Nullable: carts are ephemeral and pre-existing ones have no snapshot, so every read uses
-- COALESCE(display_unit_price, unit_price_amount).
ALTER TABLE cart_line ADD COLUMN display_unit_price numeric(12,2);

-- ---- Loyalty ---------------------------------------------------------------------------
-- Deliberately NOT the wallet: the wallet holds real money, is funded by verified Stripe
-- webhooks and can pay for orders. Credits are a promotional balance with no spend path yet
-- (no conversion rate decided), so they get their own account + append-only ledger.
CREATE TABLE loyalty_account (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id     uuid NOT NULL UNIQUE REFERENCES app_user(id) ON DELETE CASCADE,
    balance_credits numeric(12,2) NOT NULL DEFAULT 0 CHECK (balance_credits >= 0),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE loyalty_transaction (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id  uuid NOT NULL REFERENCES loyalty_account(id) ON DELETE CASCADE,
    customer_id uuid NOT NULL,
    order_id    uuid NOT NULL REFERENCES orders(id),
    type        text NOT NULL,                       -- earn | reverse
    credits     numeric(12,2) NOT NULL CHECK (credits > 0),
    created_at  timestamptz NOT NULL DEFAULT now()
);
-- One earn and at most one reverse per order — makes award/reverse idempotent under webhook
-- redelivery, same guarantee ux_wallet_txn_order_reason gives the wallet.
CREATE UNIQUE INDEX ux_loyalty_txn_order_type ON loyalty_transaction (order_id, type);
CREATE INDEX idx_loyalty_txn_account ON loyalty_transaction (account_id, created_at DESC);

-- ---- RLS: owner or admin, mirroring the V015 wallet policies ----------------------------
-- Only enforced when grocerymart.rls.enforce=true routes the request through grocery_app.
ALTER TABLE loyalty_account ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_account FORCE ROW LEVEL SECURITY;
CREATE POLICY loyalty_account_access ON loyalty_account
  USING      (current_setting('app.current_role', true) = 'ADMIN'
              OR customer_id = current_setting('app.current_user_id', true)::uuid)
  WITH CHECK (current_setting('app.current_role', true) = 'ADMIN'
              OR customer_id = current_setting('app.current_user_id', true)::uuid);

ALTER TABLE loyalty_transaction ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_transaction FORCE ROW LEVEL SECURITY;
CREATE POLICY loyalty_transaction_access ON loyalty_transaction
  USING      (current_setting('app.current_role', true) = 'ADMIN'
              OR customer_id = current_setting('app.current_user_id', true)::uuid)
  WITH CHECK (current_setting('app.current_role', true) = 'ADMIN'
              OR customer_id = current_setting('app.current_user_id', true)::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON loyalty_account, loyalty_transaction TO grocery_app;
