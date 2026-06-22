-- Epic 3 (Story 3.3): store profile fields.
ALTER TABLE shop ADD COLUMN description text;
ALTER TABLE shop ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
