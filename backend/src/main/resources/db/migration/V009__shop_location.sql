-- Epic 4 (Story 4.1): store geolocation for near-me discovery + basket comparison.
ALTER TABLE shop ADD COLUMN address  text;
ALTER TABLE shop ADD COLUMN location geography(Point, 4326);
CREATE INDEX idx_shop_location ON shop USING gist (location);
