-- Epic 2 (Story 2.1): identity foundation. Global identity (not tenant-scoped);
-- shop/tenant membership is layered on in Epic 3. Permission-based roles.
CREATE TABLE app_user (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    phone         text UNIQUE,
    email         text UNIQUE,
    display_name  text,
    status        text NOT NULL DEFAULT 'active',     -- active | deactivated
    country_code  text NOT NULL DEFAULT 'AU',
    currency      text NOT NULL DEFAULT 'AUD',
    locale        text NOT NULL DEFAULT 'en-AU',
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_role (
    user_id  uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    role     text NOT NULL,        -- CUSTOMER | SHOP_OWNER | SHOP_STAFF | DRIVER | ADMIN | NGO
    PRIMARY KEY (user_id, role)
);

-- Phone OTP challenges (Story 2.2). Code is stored hashed; never plaintext.
CREATE TABLE otp_challenge (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    phone        text NOT NULL,
    code_hash    text NOT NULL,
    expires_at   timestamptz NOT NULL,
    attempts     int NOT NULL DEFAULT 0,
    consumed_at  timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_otp_phone ON otp_challenge (phone, created_at DESC);

-- Rotating refresh tokens (Story 2.6). Stored hashed; one row per issued token.
CREATE TABLE refresh_token (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    token_hash  text NOT NULL UNIQUE,
    device_id   uuid,
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_refresh_user ON refresh_token (user_id) WHERE revoked_at IS NULL;

-- Push/device registry (Story 2.6 / FCM in Epic 7).
CREATE TABLE device (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    platform    text,
    push_token  text,
    created_at  timestamptz NOT NULL DEFAULT now()
);
