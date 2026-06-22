-- Epic 8: NGO food donation. Stores list surplus (quantity decoupled from catalog stock),
-- approved NGOs discover by PostGIS radius, claim, and confirm collection; admins oversee.

CREATE TABLE ngos (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name          text NOT NULL,
    contact_email text,
    status        text NOT NULL DEFAULT 'PENDING_APPROVAL'
                  CHECK (status IN ('PENDING_APPROVAL', 'APPROVED', 'SUSPENDED')),
    location      geography(Point, 4326),
    approved_by   uuid REFERENCES app_user(id),
    approved_at   timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_ngos_location ON ngos USING gist (location);

-- Link an NGO-manager account to its NGO.
ALTER TABLE app_user ADD COLUMN ngo_id uuid REFERENCES ngos(id);

CREATE TABLE donations (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id            uuid NOT NULL REFERENCES shop(id) ON DELETE CASCADE,
    product_ref         text,
    description         text,
    quantity            int NOT NULL CHECK (quantity > 0),   -- free-standing; NOT joined to catalog stock
    unit                text,
    status              text NOT NULL DEFAULT 'AVAILABLE' CHECK (status IN ('AVAILABLE', 'COLLECTED')),
    claimed_by_ngo_id   uuid REFERENCES ngos(id),
    claimed_at          timestamptz,
    collected_by_ngo_id uuid REFERENCES ngos(id),
    collected_at        timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_donations_store ON donations (store_id);
CREATE INDEX idx_donations_available ON donations (status) WHERE status = 'AVAILABLE';

-- RLS (defense-in-depth, NFR-ISO-01). The API enforces these same rules at the app layer; the
-- policies become the active gate once Epic 9 connects the API as the non-superuser grocery_app.
-- Keyed on per-transaction GUCs the API sets from the JWT (app.current_role/user_id/ngo_id).
ALTER TABLE ngos ENABLE ROW LEVEL SECURITY;
ALTER TABLE ngos FORCE ROW LEVEL SECURITY;
CREATE POLICY ngos_admin_all ON ngos
    USING (current_setting('app.current_role', true) = 'ADMIN')
    WITH CHECK (current_setting('app.current_role', true) = 'ADMIN');
CREATE POLICY ngos_self_read ON ngos FOR SELECT
    USING (id = current_setting('app.current_ngo_id', true)::uuid);

ALTER TABLE donations ENABLE ROW LEVEL SECURITY;
ALTER TABLE donations FORCE ROW LEVEL SECURITY;
CREATE POLICY donations_admin_all ON donations
    USING (current_setting('app.current_role', true) = 'ADMIN')
    WITH CHECK (current_setting('app.current_role', true) = 'ADMIN');
CREATE POLICY donations_store_own ON donations
    USING (store_id IN (SELECT id FROM shop WHERE owner_id = current_setting('app.current_user_id', true)::uuid))
    WITH CHECK (store_id IN (SELECT id FROM shop WHERE owner_id = current_setting('app.current_user_id', true)::uuid));
CREATE POLICY donations_ngo_browse ON donations FOR SELECT
    USING (status = 'AVAILABLE');

GRANT SELECT, INSERT, UPDATE, DELETE ON ngos, donations TO grocery_app;
