-- Grocery-Mart baseline: enable the Postgres extensions the platform relies on.
--   postgis   -> geography(Point) for near-me discovery, distance fees, driver tracking
--   pg_trgm   -> trigram similarity for canonical-product fuzzy matching
--   pgcrypto  -> gen_random_uuid() and uuidv7-style id generation
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Smoke-test row so the walking skeleton proves migrations + DB connectivity end to end.
CREATE TABLE IF NOT EXISTS schema_smoke_test (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    note        text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO schema_smoke_test (note) VALUES ('grocery-mart V001 baseline applied');
