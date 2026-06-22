#!/usr/bin/env bash
# Seed demo stores/products into a FRESH database after the backend has booted (Flyway has run).
#
# Usage:
#   export DATABASE_URL="postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require"
#   ./seed-remote.sh
#
# Use the Supabase *psql* connection string (the "postgresql://" one from Connect → Session pooler),
# NOT the JDBC url. Requires psql + python3 installed locally.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
: "${DATABASE_URL:?Set DATABASE_URL to your Supabase psql connection string}"

python3 "$DIR/seed-remote.py" > /tmp/gm-seed-remote.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f /tmp/gm-seed-remote.sql
echo "✓ Demo data seeded."
