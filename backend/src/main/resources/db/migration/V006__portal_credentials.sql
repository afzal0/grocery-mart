-- Epic 2 (Stories 2.4 / 2.7): portal email+password credentials, password reset,
-- and a dev-only admin bootstrap. Customer accounts (phone OTP) have no password.
ALTER TABLE app_user ADD COLUMN password_hash text;

CREATE TABLE password_reset (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    token_hash   text NOT NULL,
    expires_at   timestamptz NOT NULL,
    consumed_at  timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_password_reset_user ON password_reset (user_id, created_at DESC);

-- Dev-only admin bootstrap (admin #0). bcrypt via pgcrypto; verifies with Spring's
-- BCryptPasswordEncoder. Rotate/disable before any non-dev environment (NFR-SEC-01).
INSERT INTO app_user (email, display_name, password_hash)
VALUES ('admin@grocery-mart.dev', 'Dev Admin', crypt('admin-dev-pass', gen_salt('bf')));

INSERT INTO user_role (user_id, role)
SELECT id, 'ADMIN' FROM app_user WHERE email = 'admin@grocery-mart.dev';
