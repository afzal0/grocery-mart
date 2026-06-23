-- Security hardening (audit 2026-06-23, findings H-5/H-6/H-7): make Row-Level Security a real
-- defense-in-depth layer on the private/financial tables, keyed to the per-request GUCs
-- (app.current_user_id / app.current_role) that the API sets via RlsConnectionFilter.
--
-- IMPORTANT — why this is safe to ship even while live:
--   The application currently connects as the Supabase `postgres` role, which has BYPASSRLS and
--   OWNS these tables, so it bypasses every policy below regardless of FORCE. Enabling RLS here is
--   therefore a NO-OP for the running app (zero behavior change / zero outage risk) and only takes
--   effect once the app executes queries under the non-bypass `grocery_app` role — which happens
--   per-request when grocerymart.rls.enforce=true (RlsConnectionFilter does SET ROLE grocery_app).
--   Until that flag is enabled and QA'd, this provides a correct, ready-to-activate isolation layer.
--
-- current_setting('app.current_user_id', true) returns NULL when the GUC is unset -> predicate is
-- NULL -> no rows -> deny-by-default. Unauthenticated auth-flow requests deliberately run as
-- `postgres` (bypass) so login can read app_user/refresh_token before a user context exists.

-- ---- grant the application role everything it needs (RLS, not GRANTs, does the isolation) ----
-- ACTIVATION PREREQUISITE (NOT done here): to enable enforcement the runtime DB login must be a
-- member of grocery_app so it can `SET ROLE grocery_app` per request, i.e. run once via a DIRECT
-- (non-pooler) connection or the Supabase SQL editor:   GRANT grocery_app TO postgres;
-- It is intentionally NOT in this migration because Supabase's transaction/session pooler terminates
-- the connection on a self-membership GRANT, which would fail Flyway on boot. Enforcement is OFF by
-- default (grocerymart.rls.enforce=false), so the membership grant is only needed when activating.
GRANT USAGE ON SCHEMA public TO grocery_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO grocery_app;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO grocery_app;
-- future tables/sequences created by later migrations (run as the owner) inherit the grants
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO grocery_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO grocery_app;

-- ---- helper predicates (inlined per policy; Postgres has no policy macros) ----
--   admin:    current_setting('app.current_role', true) = 'ADMIN'
--   self uid: current_setting('app.current_user_id', true)::uuid

-- ===== orders: customer (own) / shop owner (their store) / assigned driver / admin =====
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
CREATE POLICY orders_access ON orders
  USING (
        current_setting('app.current_role', true) = 'ADMIN'
     OR customer_id = current_setting('app.current_user_id', true)::uuid
     OR store_id IN (SELECT id FROM shop WHERE owner_id = current_setting('app.current_user_id', true)::uuid)
     OR id IN (SELECT order_id FROM delivery WHERE driver_id = current_setting('app.current_user_id', true)::uuid)
  )
  WITH CHECK (
        current_setting('app.current_role', true) = 'ADMIN'
     OR customer_id = current_setting('app.current_user_id', true)::uuid
     OR store_id IN (SELECT id FROM shop WHERE owner_id = current_setting('app.current_user_id', true)::uuid)
  );

-- order_item / cart_line inherit scope from their parent via the parent's RLS-filtered subquery
ALTER TABLE order_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_item FORCE ROW LEVEL SECURITY;
CREATE POLICY order_item_access ON order_item
  USING (order_id IN (SELECT id FROM orders))
  WITH CHECK (order_id IN (SELECT id FROM orders));

ALTER TABLE cart ENABLE ROW LEVEL SECURITY;
ALTER TABLE cart FORCE ROW LEVEL SECURITY;
CREATE POLICY cart_access ON cart
  USING      (current_setting('app.current_role', true) = 'ADMIN'
              OR customer_id = current_setting('app.current_user_id', true)::uuid)
  WITH CHECK (current_setting('app.current_role', true) = 'ADMIN'
              OR customer_id = current_setting('app.current_user_id', true)::uuid);

ALTER TABLE cart_line ENABLE ROW LEVEL SECURITY;
ALTER TABLE cart_line FORCE ROW LEVEL SECURITY;
CREATE POLICY cart_line_access ON cart_line
  USING (cart_id IN (SELECT id FROM cart))
  WITH CHECK (cart_id IN (SELECT id FROM cart));

-- ===== wallet / money: owner or admin only =====
ALTER TABLE wallet ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet FORCE ROW LEVEL SECURITY;
CREATE POLICY wallet_access ON wallet
  USING      (current_setting('app.current_role', true) = 'ADMIN'
              OR customer_id = current_setting('app.current_user_id', true)::uuid)
  WITH CHECK (current_setting('app.current_role', true) = 'ADMIN'
              OR customer_id = current_setting('app.current_user_id', true)::uuid);

ALTER TABLE wallet_transaction ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_transaction FORCE ROW LEVEL SECURITY;
CREATE POLICY wallet_transaction_access ON wallet_transaction
  USING      (current_setting('app.current_role', true) = 'ADMIN'
              OR customer_id = current_setting('app.current_user_id', true)::uuid)
  WITH CHECK (current_setting('app.current_role', true) = 'ADMIN'
              OR customer_id = current_setting('app.current_user_id', true)::uuid);

ALTER TABLE payment_intent ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_intent FORCE ROW LEVEL SECURITY;
CREATE POLICY payment_intent_access ON payment_intent
  USING      (current_setting('app.current_role', true) = 'ADMIN'
              OR customer_id = current_setting('app.current_user_id', true)::uuid)
  WITH CHECK (current_setting('app.current_role', true) = 'ADMIN'
              OR customer_id = current_setting('app.current_user_id', true)::uuid);

-- ===== notifications: a user reads/updates only their own, but the SYSTEM creates them for
--       other recipients (e.g. a customer's checkout notifies the shop owner), so INSERT is open. =====
ALTER TABLE notification ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification FORCE ROW LEVEL SECURITY;
CREATE POLICY notification_read ON notification FOR SELECT
  USING (current_setting('app.current_role', true) = 'ADMIN'
         OR user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY notification_update ON notification FOR UPDATE
  USING      (current_setting('app.current_role', true) = 'ADMIN'
              OR user_id = current_setting('app.current_user_id', true)::uuid)
  WITH CHECK (current_setting('app.current_role', true) = 'ADMIN'
              OR user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY notification_insert ON notification FOR INSERT
  WITH CHECK (true);   -- system fan-out addresses notifications to shop owners / drivers / others

-- ===== driver GPS: the assigned driver, the order's customer/shop (via orders RLS), or admin =====
ALTER TABLE driver_location ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_location FORCE ROW LEVEL SECURITY;
CREATE POLICY driver_location_access ON driver_location
  USING      (current_setting('app.current_role', true) = 'ADMIN'
              OR driver_id = current_setting('app.current_user_id', true)::uuid
              OR order_id IN (SELECT id FROM orders))
  WITH CHECK (current_setting('app.current_role', true) = 'ADMIN'
              OR driver_id = current_setting('app.current_user_id', true)::uuid);

-- ===== Fix H-7: donations_ngo_browse fails open (any role sees AVAILABLE donations). Add role gate. =====
DROP POLICY IF EXISTS donations_ngo_browse ON donations;
CREATE POLICY donations_ngo_browse ON donations FOR SELECT
  USING (status = 'AVAILABLE' AND current_setting('app.current_role', true) = 'NGO');
