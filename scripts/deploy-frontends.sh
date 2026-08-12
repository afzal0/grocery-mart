#!/usr/bin/env bash
# Deploy all three frontends to Vercel against a given backend.
#
#   ./scripts/deploy-frontends.sh https://grocery-mart-api.onrender.com
#
# The API URL is baked in at BUILD time for all three apps (Vite inlines
# VITE_API_BASE_URL; Flutter inlines API_BASE via --dart-define), so it cannot be changed
# afterwards from a dashboard — pointing at a different backend means rebuilding.
#
# Prerequisites: `npx vercel login` once (interactive), and a backend already reachable at
# the URL you pass. Deploying the frontends against a backend that is not up yet gives you
# three URLs that render and then fail on every request.
set -euo pipefail

API="${1:-}"
if [[ -z "$API" ]]; then
  echo "usage: $0 <backend-base-url>" >&2
  echo "   eg: $0 https://grocery-mart-api.onrender.com" >&2
  exit 64
fi
API="${API%/}"   # trailing slash would produce //api/v1 in every request

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER="${FLUTTER_BIN:-/Volumes/xcode/flutter/bin/flutter}"

echo "==> Backend: $API"

# Fail before doing any work if the CLI is not authenticated — a login prompt cannot be
# answered from a script, and a half-deployed set of frontends is worse than none.
echo "==> Checking Vercel auth"
if ! npx --yes vercel@latest whoami >/dev/null 2>&1; then
  echo "   Not logged in. Run: npx vercel login" >&2
  exit 1
fi
echo "   $(npx --yes vercel@latest whoami 2>/dev/null)"

echo "==> Verifying the backend answers"
if ! curl -fsS --max-time 20 "$API/api/v1/ping" >/dev/null 2>&1; then
  echo "   WARNING: $API/api/v1/ping did not respond." >&2
  echo "   A free-tier host may just be cold-starting; if it is genuinely down, the" >&2
  echo "   deployed apps will build fine and fail at runtime." >&2
  read -r -p "   Continue anyway? [y/N] " ok
  [[ "$ok" == [yY] ]] || exit 1
fi

deploy_portal() {
  local dir="$1" label="$2"
  echo "==> $label"
  ( cd "$ROOT/$dir"
    VITE_API_BASE_URL="$API" ./node_modules/.bin/vite build
    npx --yes vercel@latest deploy --prod --yes dist )
}

deploy_portal apps/shop-portal  "Shop portal"
deploy_portal apps/admin-portal "Admin portal"

echo "==> Customer app (Flutter web)"
( cd "$ROOT/apps/customer-mobile"
  "$FLUTTER" build web --release --dart-define=API_BASE="$API"
  cp vercel.json build/web/vercel.json          # SPA rewrites for the static output
  npx --yes vercel@latest deploy --prod --yes build/web )

cat <<EOF

==> Done. One step remains, or every request will be blocked by CORS.

The backend only allows localhost origins by default. Set this on the backend host
(Render → Environment) using the three URLs printed above, then redeploy it:

  GROCERYMART_CORS_ORIGINS=https://<shop>.vercel.app,https://<admin>.vercel.app,https://<customer>.vercel.app

A wildcard also works while the URLs are still churning:

  GROCERYMART_CORS_ORIGINS=https://*.vercel.app
EOF
