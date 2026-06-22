-- Tenant-isolation baseline (NFR-ISO-01).
-- Demonstrates Postgres Row-Level Security keyed on a per-transaction GUC
-- (app.current_shop_id) that the API sets via SET LOCAL from the JWT tenant claim
-- (full JWT wiring lands in Epic 2). FORCE ROW LEVEL SECURITY so even the table
-- owner is subject to the policy. Proven by RlsIsolationTest.
--
-- current_setting(..., true) returns NULL when the GUC is unset -> the predicate is
-- NULL -> no rows visible. That gives deny-by-default when no tenant context is set.

CREATE TABLE tenant_demo (
    id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id  uuid NOT NULL,
    label    text NOT NULL
);

-- Seed BEFORE enabling RLS so the migration itself isn't blocked by the policy.
INSERT INTO tenant_demo (shop_id, label) VALUES
    ('11111111-1111-1111-1111-111111111111', 'shop A only'),
    ('22222222-2222-2222-2222-222222222222', 'shop B only');

ALTER TABLE tenant_demo ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_demo FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_demo_isolation ON tenant_demo
    USING      (shop_id = current_setting('app.current_shop_id', true)::uuid)
    WITH CHECK (shop_id = current_setting('app.current_shop_id', true)::uuid);
