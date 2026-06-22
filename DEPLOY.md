# Deploying Grocery-Mart (demo) — Supabase + Render + Vercel

Three tiers, three hosts, all free-tier-friendly:

| Tier | Host | What |
|------|------|------|
| Database (PostgreSQL + PostGIS) | **Supabase** | schema is auto-created by Flyway on first boot |
| Backend (Spring Boot, Docker) | **Render** | `backend/Dockerfile` + `render.yaml` |
| Customer web + Shop portal + Admin portal | **Vercel** | static builds |

Do the steps **in order** — the backend URL is needed by the frontends, and the frontend URLs are needed by the backend's CORS.

---

## 0. Push to GitHub (one-time)
Render and Vercel deploy from a Git repo.
```bash
cd /Volumes/SSD/grocery-mart
gh repo create grocery-mart --private --source=. --remote=origin --push    # or create on github.com and: git remote add origin … && git push -u origin main
```

## 1. Supabase — the database
1. Create a project (note the **database password** you set).
2. **Database → Extensions → enable `postgis`** (also enable `pgcrypto` and `pg_trgm` if not already on). This guarantees the geo/crypto/fuzzy functions the migrations use.
3. **Connect → Session pooler** (NOT "Transaction pooler") and copy two forms of the connection:
   - JDBC (for the backend): `jdbc:postgresql://aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require`
   - psql URI (for seeding): `postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require`

   ⚠️ Use the **session pooler on port 5432** — Flyway needs session-level advisory locks, which the transaction pooler (6543) does not support.

## 2. Render — the backend
1. **New → Blueprint**, pick the GitHub repo. Render reads `render.yaml` and creates the `grocery-mart-api` Docker service.
2. Set the env vars it asks for (the rest are auto):
   - `DB_URL` = the **JDBC** url from step 1
   - `POSTGRES_USER` = `postgres.<project-ref>`
   - `POSTGRES_PASSWORD` = your Supabase DB password
   - `GROCERYMART_CORS_ORIGINS` = leave blank for now (set in step 5)
   - `JWT_SECRET` is generated for you.
3. Deploy. On first boot Flyway runs `V001…V014` and builds the whole schema. Watch the logs for `Started ApiApplication`.
4. Verify: open `https://grocery-mart-api.onrender.com/api/v1/ping` → `{"status":"ok",…}`.
   (Free tier sleeps after ~15 min idle; the first request then takes ~30–50s to wake.)

## 3. Seed the demo data
After the backend has migrated the schema, populate the 10 stores / ~75 products:
```bash
export DATABASE_URL="postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require"
infra/seed/seed-remote.sh
```
(Needs `psql` + `python3` locally.) The `admin@grocery-mart.dev / admin-dev-pass` account is created by the migration itself.

## 4. Vercel — the three frontends
For **each** of `apps/shop-portal`, `apps/admin-portal`:
- New Project → import the repo → **Root Directory = `apps/shop-portal`** (resp. `apps/admin-portal`).
- Framework preset: **Vite** (the `vercel.json` adds SPA rewrites).
- Add env var **`VITE_API_BASE_URL` = `https://grocery-mart-api.onrender.com`** (build-time).
- Deploy. You get e.g. `https://grocery-mart-shop.vercel.app`.

For the **customer Flutter web app** (Vercel can't run Flutter, so build locally and deploy the static output):
```bash
cd apps/customer-mobile
export PATH="/Volumes/xcode/flutter/bin:$PATH"
flutter build web --release --dart-define=API_BASE=https://grocery-mart-api.onrender.com
cp vercel.json build/web/vercel.json
npx vercel deploy build/web --prod      # or: wrangler pages deploy build/web   (Cloudflare Pages)
```
(The same recipe works for `apps/driver-mobile` if you want the courier app online too.)

## 5. Open CORS to the deployed frontends
Back in Render → `grocery-mart-api` → Environment, set:
```
GROCERYMART_CORS_ORIGINS = https://grocery-mart-shop.vercel.app,https://grocery-mart-admin.vercel.app,https://<customer-web>.vercel.app
```
Wildcards work too (`https://*.vercel.app`). Save → Render redeploys. Done.

---

## Sign-in for the demo
- **Admin console:** `admin@grocery-mart.dev` / `admin-dev-pass`
- **Shop portal:** `shop1@grocery-mart.dev` / `shoppass123` (Patel Cash & Carry) — or any `owner_*@grocery-mart.dev` / `shoppass123`
- **Customer app:** tap **Create an account** (self-registers), or `demo@grocery-mart.dev` / `demopass123` if you seed it.

## Notes & gotchas
- **HTTPS everywhere** — Vercel/Render provide it; the customer app's auto-location needs HTTPS, which hosted domains give you.
- **Stripe/FCM are dev stubs** — no real keys needed; payments/webhooks/push are simulated. `STRIPE_WEBHOOK_SECRET` stays at its dev value.
- **No Redis** — live tracking uses the in-process STOMP broker; Redis is off.
- **Cold starts** — Render free + Supabase free both pause when idle; the first hit after a quiet period is slow. Upgrade either to a paid instance to keep it always-warm.
- **Always-warm alternative** — Fly.io (with a `postgis` DB image) or Google Cloud Run avoid spin-down.
