# Security Hardening & Secret Rotation (Epic 9)

## Secret rotation (Story 9.12)

Before payment code ships, every previously-committed credential must be rotated and moved to the
secrets manager. None of these may appear as literals in source.

| Secret | Rotation action | Where it lives in prod |
|--------|-----------------|------------------------|
| Stripe secret + webhook signing secret | Roll keys in Stripe dashboard; old keys revoked | AWS Secrets Manager → injected as env |
| Database password | Rotate RDS master + app role; update Secrets Manager | AWS Secrets Manager |
| JWT signing key | Regenerate; invalidate old (forces re-auth) | AWS Secrets Manager |
| Dev admin bootstrap (`admin-dev-pass`) | Disabled/removed in non-dev profiles | n/a (dev only) |

The app reads secrets from environment variables (12-factor): `STRIPE_WEBHOOK_SECRET`,
`POSTGRES_PASSWORD`, `DB_URL`, etc. Defaults in `application.yml` are **dev-only placeholders**
(allowlisted in `.gitleaks.toml`); production overrides them from Secrets Manager. The CI `security`
workflow runs gitleaks on every push/PR and **blocks merge** on any detected secret.

## Transport & input hardening (Story 9.13)

- **HTTPS only** in prod (ALB redirects HTTP→HTTPS; HSTS at the edge).
- **CORS** locked to approved origins (portal dev origins in `SecurityConfig`; prod origins via config).
- **Rate limiting** — `RateLimitFilter`, per-principal/IP sliding window, returns 429 problem+json.
- **Input validation** — Bean Validation on DTOs; RFC 9457 `application/problem+json` errors that never
  contain stack traces, SQL, or internal identifiers; unexpected exceptions → generic 500 (detail logged
  server-side only).

## Tenant isolation (RLS)

Postgres RLS policies enforce tenant/role isolation (catalog, donations, ngos). The API connects as a
least-privilege role (`grocery_app`) in prod; the privileged admin cross-tenant reads are explicit and
written to the immutable `audit_log` (Story 9.11).

## Availability (Story 9.14)

`/actuator/health/liveness` and `/actuator/health/readiness` back the load balancer probes; readiness
includes the DB so an instance with a broken DB connection is taken out of rotation. SLO: 99.5%.
