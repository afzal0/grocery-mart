-- Epic 3: stores + canonical catalog + matching (the price-comparison wedge).
-- canonical_product is SHARED reference data (the cross-store identity); store_product is
-- shop-scoped. Shops free-create store_products; a matching pass links them to a canonical
-- (exact -> auto, fuzzy -> candidate for human review, none -> new canonical).

CREATE TABLE shop (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id      uuid NOT NULL REFERENCES app_user(id),
    name          text NOT NULL,
    cuisine_tags  text[] NOT NULL DEFAULT '{}',
    status        text NOT NULL DEFAULT 'pending',   -- pending | active | rejected | suspended
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_shop_owner ON shop (owner_id);

CREATE TABLE canonical_product (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name         text NOT NULL,
    brand        text,
    size_label   text,
    category     text,
    cuisine_tag  text,
    match_key    text NOT NULL,        -- normalized brand+name+size for exact match / trigram
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_canonical_match_key ON canonical_product (match_key);
CREATE INDEX idx_canonical_trgm ON canonical_product USING gin (match_key gin_trgm_ops);

CREATE TABLE store_product (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id              uuid NOT NULL REFERENCES shop(id) ON DELETE CASCADE,
    canonical_product_id uuid REFERENCES canonical_product(id),   -- null until matched
    raw_name             text NOT NULL,
    raw_brand            text,
    raw_size             text,
    price_amount         numeric(12,2) NOT NULL,
    currency             text NOT NULL DEFAULT 'AUD',
    stock                int NOT NULL DEFAULT 0,
    match_status         text NOT NULL DEFAULT 'pending',  -- pending|auto_linked|candidate|merged_confirmed
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_store_product_shop ON store_product (shop_id);
CREATE INDEX idx_store_product_canonical ON store_product (canonical_product_id)
    WHERE canonical_product_id IS NOT NULL;

CREATE TABLE product_match_candidate (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_product_id     uuid NOT NULL REFERENCES store_product(id) ON DELETE CASCADE,
    canonical_product_id uuid NOT NULL REFERENCES canonical_product(id),
    similarity           numeric(4,3) NOT NULL,
    status               text NOT NULL DEFAULT 'open',   -- open | confirmed | rejected
    created_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_candidate_open ON product_match_candidate (created_at) WHERE status = 'open';

-- Append-only audit of every link/merge (NFR-DG-01).
CREATE TABLE product_merge_log (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_product_id     uuid NOT NULL,
    canonical_product_id uuid NOT NULL,
    action               text NOT NULL,            -- auto_link | confirm_candidate | admin_merge
    similarity           numeric(4,3),
    actor                text,
    created_at           timestamptz NOT NULL DEFAULT now()
);
