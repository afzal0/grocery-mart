# Grocery-Mart Security Audit — Consolidated Report

**Date:** 2026-06-23
**Scope:** Authorized defensive security audit of the full grocery-mart stack (GitHub `afzal0/grocery-mart`, Supabase, Render, Vercel).
**Targets:** Spring Boot backend (`/Volumes/SSD/grocery-mart/backend`), clients (`/Volumes/SSD/grocery-mart/apps`).
**Live API:** `https://grocery-mart-api.onrender.com/api/v1`
**Frontends:** `grocery-mart-customer.vercel.app`, `grocery-mart-shop.vercel.app`, `grocery-mart-admin.vercel.app`
**Method:** Per-dimension static source review (Authentication/JWT, Authorization/IDOR, RLS/SQL-injection, Payments/money) cross-checked against non-destructive live probes against the production deployment. Live evidence was preferred over static speculation wherever the two conflicted.

---

## 1. Executive Summary

The grocery-mart backend has a **well-implemented core authentication primitive** — JWT signature verification, `alg:none` rejection, payload-tamper rejection, login-enumeration resistance, and role-based deny-by-default are all live-confirmed safe. SQL injection is not exploitable; all probed query paths are parameterized.

However, the audit found **two actively exploitable, internet-reachable issues that are live-confirmed right now**, plus several high-severity structural gaps:

1. **A hardcoded ADMIN account (`admin@grocery-mart.dev` / `admin-dev-pass`) seeded by a Flyway migration is live in production** and grants full administrative takeover with a single curl. The credential is public in the GitHub repository. This is the single highest-priority issue.
2. **The STOMP WebSocket order-tracking channel is completely unauthenticated** — any anonymous internet client can subscribe to `/topic/orders/{orderId}/tracking` for any order and receive live driver GPS coordinates and delivery destinations. Live-confirmed by connecting with no Authorization header and successfully subscribing to a foreign order and a randomly-guessed UUID.

The most important architectural weakness is that **the database provides zero defense-in-depth**: the app connects to Supabase as a superuser and Row-Level Security is not enabled/forced on any production table. Every isolation guarantee rests entirely on application-layer `WHERE` clauses. The app-layer checks are currently correct (cross-tenant order read, export isolation, and REST tracking ownership all live-confirmed safe), but a single future bug or injection would expose all tenants with no backstop.

Encouragingly, the catastrophic "anyone can forge ADMIN tokens with the public default JWT secret" scenario was **refuted by live probe** — `JWT_SECRET` is set to a non-default value on Render, so the source-level default is a latent risk, not a present exploit.

### Severity Table

| Severity | Total (deduplicated) | Live-Confirmed Vulnerable | Refuted by Probe | Static-Only |
|----------|---------------------|---------------------------|------------------|-------------|
| Critical | 3                   | 2                         | 0                | 1           |
| High     | 9                   | 2                         | 1                | 6           |
| Medium   | 10                  | 3                         | 0                | 7           |
| Low      | 6                   | 1                         | 0                | 5           |
| Info     | 3                   | 0                         | 0                | 3           |
| **Total**| **31**              | **8**                     | **1**            | **22**      |

> Counts are after deduplication across the four review dimensions (the admin-account, OTP/reset-token-logging, JWT-secret/HS512, X-Forwarded-For-spoofing, SHOP_OWNER-self-registration, WebSocket, and CORS findings each appeared in 2–3 dimensions and are merged into a single entry below).

---

## 2. Confirmed Exploitable (Live-Verified) — Read This First

These are the issues an attacker can exploit against the live deployment today. Ordered by exploitability and impact.

### 2.1 [CRITICAL — CONFIRMED-LIVE] Hardcoded ADMIN account active in production

- **Location:** `backend/src/main/resources/db/migration/V006__portal_credentials.sql:17-21`
- **Evidence:** `POST /api/v1/auth/portal/login {"email":"admin@grocery-mart.dev","password":"admin-dev-pass"}` → **HTTP 200** returning an HS512 `accessToken` + `refreshToken`, `userId=3b33b2aa-05d0-459b-b66c-abb903d83d49`, decoded payload `roles:["ADMIN"]`. The credential is hardcoded via `crypt('admin-dev-pass', ...)` in a Flyway migration that ships in the production classpath and runs on every fresh schema apply. The credential is publicly readable in the GitHub repo.
- **Impact:** Immediate, unauthenticated-knowledge full ADMIN takeover. Grants access to audit logs, user PII export, catalog management, retention purge, settlement reconciliation (all cross-shop financials), payouts, and disputes. One curl, zero exploit complexity.
- **Remediation (do today):** (1) In the Supabase console, deactivate or delete the `admin@grocery-mart.dev` row immediately. (2) Rotate `JWT_SECRET` on Render to invalidate any already-issued admin tokens. (3) Add a migration (e.g. `V015`) that removes/deactivates this seed in non-dev environments. (4) Never seed privileged accounts via Flyway — use a one-time CLI bootstrap that reads credentials from environment variables.

### 2.2 [CRITICAL — CONFIRMED-LIVE] STOMP WebSocket order-tracking subscription is completely unauthenticated

- **Location:** `backend/src/main/java/com/grocerymart/api/config/WebSocketConfig.java:26-28`, `SecurityConfig.java:52`
- **Evidence:** Anonymous `ws` client → `wss://grocery-mart-api.onrender.com/ws/websocket` with **no Authorization header** → `WS_OPEN_101` → STOMP `CONNECT` → `CONNECTED (v1.2)` → `SUBSCRIBE /topic/orders/5f79b6ea-8818-443e-bd7d-ff6b6ffbb525/tracking` (a foreign demo-customer order) → `SUBSCRIBED_OK`, no ERROR/DISCONNECT frame. Repeated with no-Origin, `Origin: grocery-mart-customer.vercel.app`, and `Origin: attacker-app.vercel.app` → all succeeded. A randomly-guessed UUID `11111111-2222-3333-4444-555555555555` also subscribed with no rejection. `GET /ws/info` (no auth) → HTTP 200 `{"origins":["*:*"],"websocket":true}`. Grep confirms **no** `ChannelInterceptor` / `configureClientInboundChannel` / `AbstractSecurityWebSocket` anywhere. `DeliveryService` broadcasts driver GPS via `stomp.convertAndSend("/topic/orders/"+orderId+"/tracking", frame)`.
- **Impact:** Real-time GPS surveillance of any driver and disclosure of any order's delivery destination to anonymous internet clients. Violates the consent-gated GPS privacy requirement (NFR-PRIV-01). Note: the REST equivalent `GET /orders/{id}/tracking` is correctly protected (see 4.x) — only the WebSocket layer is open.
- **Remediation:** Add a Spring Security `ChannelInterceptor` (or `AbstractSecurityWebSocketMessageBrokerConfigurer`) that validates a JWT on the STOMP `CONNECT` frame (client sends Bearer token as the `login` header) and authorizes each `SUBSCRIBE` so only the order's customer, assigned driver, owning shop, or admin may subscribe — mirroring the REST check in `DeliveryService.tracking()`. Replace `setAllowedOriginPatterns("*")` with the explicit frontend origin allowlist.

### 2.3 [HIGH — CONFIRMED-LIVE] Anyone can self-register as SHOP_OWNER without vetting

- **Location:** `backend/src/main/java/com/grocerymart/api/identity/AuthService.java:31` (`SELF_REGISTERABLE = {CUSTOMER, SHOP_OWNER}`)
- **Evidence:** `POST /api/v1/auth/register {role:"SHOP_OWNER"}` → **HTTP 201**, `roles:["SHOP_OWNER"]`, valid `accessToken` issued with no email verification and no admin approval. With that token: `GET /shops/me` → HTTP 400 `{"detail":"No store yet."}`; `GET /shops/me/dispatch` → HTTP 404 `{"detail":"you do not own a shop"}` — these are **business-logic** errors (the role guard PASSED and the request reached shop-owner code), not 403 access-denied, proving an unvetted anonymous actor obtains the privileged SHOP_OWNER role and reaches shop-owner endpoints.
- **Impact:** Adversary gains the SHOP_OWNER role in seconds and can probe dispatch queues, attempt to create driver accounts, create catalog entries, and interact with the entire shop-owner API surface before any admin review. Conflicts with the admin-gated shop approval workflow.
- **Remediation:** Set `SELF_REGISTERABLE = {CUSTOMER}` only. Provision SHOP_OWNER via an admin-issued, time-limited invitation flow. At minimum require email verification before granting the role, and have every SHOP_OWNER-guarded endpoint fail closed unless the owner's shop status is `pending`/`active`.

### 2.4 [HIGH — CONFIRMED-LIVE] Rate limiter fully bypassable via X-Forwarded-For spoofing

- **Location:** `backend/src/main/java/com/grocerymart/api/config/RateLimitFilter.java:65-66` (also `AuditService` IP capture)
- **Evidence:** `principalKey()` returns `"ip:" + fwd.split(",")[0].trim()` from the client-supplied `X-Forwarded-For` with **no trusted-proxy validation** (limit `requests-per-minute=300`, `application.yml:38`). Live: `GET /api/v1/ping` with `X-Forwarded-For: 1.2.3.4`, then `5.6.7.8`, then `9.10.11.12, 13.14.15.16` → all HTTP 200; arbitrary attacker-supplied XFF is honored, so each spoofed IP gets an independent 300/min bucket. `POST /auth/portal/login` with `X-Forwarded-For: 9.9.9.9` then `8.8.8.8` → both processed (HTTP 401 clean). The 300+ burst to empirically trip a 429 was deliberately **not** run (no-DoS hard limit); the bypass mechanism is confirmed by code plus demonstrated unconditional header trust.
- **Impact:** Unlimited credential stuffing / brute force on `/auth/portal/login`, OTP exhaustion on `/auth/otp/request`, and reset-token flooding on `/auth/password/reset/request`. Forged IPs also poison `audit_log.source_ip`, defeating forensics. Compounded by the absence of per-account lockout (4.x) and per-phone OTP limits (5.x).
- **Remediation:** Set `server.forward-headers-strategy=NATIVE` (or configure Tomcat `remoteip.internal-proxies` to Render's proxy range) so Spring resolves the real client IP and only trusts XFF from the trusted hop. Add DB-backed per-account/per-phone counters that cannot be bypassed by IP rotation. Prefer keying the limiter on the JWT subject for authenticated requests.

### 2.5 [HIGH — CONFIRMED-LIVE] CORS reflects any `*.vercel.app` origin with credentials enabled

- **Location:** `backend/src/main/java/com/grocerymart/api/config/SecurityConfig.java:66-78` (`setAllowedOriginPatterns(... https://*.vercel.app ...)` + `setAllowCredentials(true)`)
- **Evidence:** `OPTIONS /api/v1/wallet` with `Origin: https://attacker-grocery.vercel.app`, `Access-Control-Request-Method: GET` → **HTTP 200** with `access-control-allow-origin: https://attacker-grocery.vercel.app`, `access-control-allow-credentials: true`, `access-control-allow-headers: authorization`. Control: `Origin: https://evil-attacker.com` → HTTP 403, no ACAO header. This isolates the active wildcard: any of the millions of `*.vercel.app` subdomains (free to create) gets credentialed CORS access to the production API.
- **Impact:** Any attacker who deploys to `*.vercel.app` can make credentialed cross-origin API calls in a victim's browser context. Currently lower-impact because tokens are Bearer-in-header rather than cookie-based, but this becomes a full CSRF / session-hijack vector the moment auth storage changes.
- **Remediation:** Replace `https://*.vercel.app` with the three exact frontend origins (`grocery-mart-customer`, `grocery-mart-shop`, `grocery-mart-admin` `.vercel.app`), supplied via `GROCERYMART_CORS_ORIGINS`. If preview deployments are required, scope the pattern to a specific project slug. Apply the same allowlist to the WebSocket origin config.

### 2.6 [MEDIUM — CONFIRMED-LIVE] Currency field accepts arbitrary non-ISO-4217 strings (data pollution)

- **Location:** `backend/src/main/java/com/grocerymart/api/payments/WalletService.java:51-67`, `PaymentDtos.java:12` (`@NotBlank` only)
- **Evidence:** `GET /wallet` returns a persisted polluted row `[{"currency":"AUD",...},{"currency":"XSS",...}]`. `POST /wallet/topup {"amount":1.00,"currency":"XSS"}` → HTTP 200 `{"currency":"XSS","status":"requires_payment"}`. Bean validation IS active (a missing currency returns 400 `"currency: must not be blank"`), confirming the gap is specifically the absent `@Pattern`/allowlist. A topup against a brand-new junk currency (`ZZ9`) returned **HTTP 500** because the new wallet `INSERT` failed at the DB layer — invalid currency is not rejected cleanly at the app layer.
- **Impact:** Unbounded fake-currency wallet rows per account (table pollution / abuse). Stored-then-rendered currency strings are a latent stored-XSS/misrouting vector if any downstream UI or report renders them unescaped. New-currency path surfaces a raw 500.
- **Remediation:** Annotate `TopupRequest.currency` and `ResolveCartRequest.currency` with `@Pattern("^[A-Z]{3}$")` or validate against an explicit supported set (e.g. `{AUD,USD,EUR}`); reject unknown codes with 400. Add a DB `CHECK` constraint on `wallet.currency` and `orders.currency`.

### 2.7 [MEDIUM — CONFIRMED-LIVE] Money precision: `amount` has no scale/magnitude bound

- **Location:** `backend/src/main/java/com/grocerymart/api/payments/PaymentDtos.java:12`, `WalletService.java:55-59`
- **Evidence:** `POST /wallet/topup {"amount":999999.999999,"currency":"AUD"}` → HTTP 200 with `amount=999999.999999` echoed. The `payment_intent` column is `numeric(12,2)`, so Postgres stores the rounded value while the credit path later uses the DB-stored amount, creating a charge/credit discrepancy of up to 0.005 per transaction. No upper bound means astronomically large topups reach the (real) Stripe API untested.
- **Impact:** Per-transaction credit can differ from the actual charge (customer over/under-credited). Missing magnitude cap means production Stripe calls fail on huge amounts via an untested error path.
- **Remediation:** Add `@Digits(integer=8, fraction=2)` and a `@DecimalMax` (e.g. `99999.99`) to `TopupRequest.amount`. Round to scale 2 before calling Stripe so the DB amount exactly matches the charged amount.

### 2.8 [MEDIUM — CONFIRMED-LIVE] User enumeration via the registration endpoint

- **Location:** `backend/src/main/java/com/grocerymart/api/identity/AuthService.java:127-128`
- **Evidence:** `POST /auth/register {email: demo@grocery-mart.dev}` (existing) → **HTTP 400** `{"detail":"Email already registered."}`, whereas a fresh email returns 201 with tokens. `register()` explicitly distinguishes existing emails, so an attacker can enumerate registered accounts. (Contrast: the login path is enumeration-safe — both unknown-email and wrong-password return a byte-identical 401 `"Invalid email or password."`, live-confirmed.)
- **Impact:** Account-existence disclosure (lower impact than login enumeration but real), useful for targeted phishing and credential stuffing; amplified by the unlimited rate (2.4).
- **Remediation:** Return a uniform response for registration regardless of whether the email exists (e.g. always 202 "if this email is new, an account was created / otherwise a notice was sent"), or gate behind email verification so registration does not leak existence synchronously.

---

## 3. Refuted by Live Probe (Important — do not over-report)

These were flagged statically but the live deployment proves they are **not currently exploitable**. They remain as code-hygiene items, not active vulnerabilities.

- **[REFUTED] Token forgery using the public default JWT secret.** A forged HS512 token signed with the repo default `change-me-dev-only-not-for-production-please` (real customer `sub`, `roles:[ADMIN]`, future `exp`) → `GET /api/v1/me` **HTTP 403**. This proves `JWT_SECRET` is set to a non-default value on Render. The catastrophic "anyone mints ADMIN tokens" scenario is **not** live. Residual risk is the source-level default + the missing startup guard only (tracked as a High structural item in §4).

---

## 4. All Findings by Severity

Status legend: **CONFIRMED-LIVE** (probe demonstrated the vulnerability), **REFUTED-BY-PROBE** (probe showed it is not exploitable live), **STATIC-ONLY** (source-confirmed, not (or not safely) live-verifiable under the non-destructive limits).

### CRITICAL

#### C-1. Hardcoded ADMIN account active in production — **CONFIRMED-LIVE**
See §2.1. Location `V006__portal_credentials.sql:17-21`. Full admin takeover via public credential. *(Deduplicated: appeared in both the authn-jwt and rls-injection dimensions.)*

#### C-2. Unauthenticated STOMP WebSocket order-tracking subscription — **CONFIRMED-LIVE**
See §2.2. Location `WebSocketConfig.java:26-28`, `SecurityConfig.java:52`. Anonymous real-time GPS/address disclosure. *(Deduplicated: authn-jwt + authz-idor dimensions.)*

#### C-3. OTP codes and password-reset tokens logged in plaintext — **STATIC-ONLY**
- **Location:** `DevOtpSender.java:14-16` and `AuthService.java:98`
- **Evidence:** `DevOtpSender` is the **only** `OtpSender` implementation, `@Component` with **no** `@Profile` guard, logging `"DEV OTP for {phone} is {code}"` at WARN. `AuthService.requestPasswordReset()` logs `"DEV password reset for {email}: token {token}"` at WARN. `logback-spring.xml:18` sets `com.grocerymart=DEBUG`, so WARN is always emitted to Render's log stream. Live: `POST /auth/otp/request` → HTTP 202 (the exact path that triggers `DevOtpSender.send`). The leak is unconditional in the deployed code path; Render logs were not directly readable from the audit host, so this is classified STATIC-ONLY despite being effectively certain.
- **Impact:** Anyone with Render log access (or a downstream log aggregator) captures valid OTP codes (login bypass) and reset tokens (account takeover, 30-min validity) in real time for any phone/email. Bypasses the entire auth layer.
- **Remediation:** Gate `DevOtpSender` with `@Profile("!prod")` and wire a real SMS provider (Twilio) for production. **Delete** the raw-token `log.warn` in `requestPasswordReset()` unconditionally — a reset token must never appear in any log. Add a `@PostConstruct` startup assertion that fails the app if the active profile is `prod` and `DevOtpSender` is in the context.

### HIGH

#### H-1. Self-registration grants SHOP_OWNER without vetting — **CONFIRMED-LIVE**
See §2.3. `AuthService.java:31`. *(Deduplicated: authn-jwt + authz-idor.)*

#### H-2. Rate limiter bypassable via X-Forwarded-For spoofing — **CONFIRMED-LIVE**
See §2.4. `RateLimitFilter.java:65-66`. *(Deduplicated: authn-jwt + rls-injection.)*

#### H-3. CORS `*.vercel.app` + `allowCredentials=true` — **CONFIRMED-LIVE**
See §2.5. `SecurityConfig.java:66-78`. *(Deduplicated: authz-idor (medium there) + payments (high) — escalated to High on the strength of the live credentialed-reflection probe.)*

#### H-4. JWT secret has an insecure public default + HS512/HS256 doc-key mismatch — **STATIC-ONLY** (default-forgery path **REFUTED-BY-PROBE**, see §3)
- **Location:** `JwtService.java:16-26`
- **Evidence:** `@Value` default is `change-me-dev-only-not-for-production-please` (44 bytes / 352 bits). Every issued token header decodes to `{"alg":"HS512"}`, while the Javadoc says "HS256 … >= 32 bytes." 352 bits is below the NIST 512-bit minimum for HMAC-SHA512. The forge-with-default attack was refuted live (§3), so the residual risk is: (a) silent fallback to a known key if `JWT_SECRET` is ever unset, and (b) misleading docs that could lead a maintainer to set a 32-byte secret.
- **Impact:** If `JWT_SECRET` were ever cleared on Render, the app would silently sign with a publicly-known key and anyone could mint ADMIN tokens. The doc/key mismatch is a maintenance hazard.
- **Remediation:** Remove the `@Value` default so the app fails fast if `JWT_SECRET` is absent. Add a startup assertion that rejects the placeholder string and enforces `secret.length >= 64` bytes for HS512. Correct the Javadoc to HS512 and update `.env.example` with a 64-byte secret (`openssl rand -hex 64`).

#### H-5. RLS bypassed in production — app connects as a superuser — **STATIC-ONLY**
- **Location:** `V003__app_role_for_rls.sql:3`, `application.yml:6`
- **Evidence:** App connects as `postgres.<ref>` via the Supabase session pooler (recon-confirmed). `V003` states the bootstrap role is a superuser that bypasses RLS. Only `tenant_demo` (V002) and `ngos`/`donations` (V013) carry `FORCE ROW LEVEL SECURITY`; all production tables (`orders`, `wallet`, `payment_intent`, `delivery`, `driver_location`, `store_product`, `settlement_ledger`, `audit_log`, `app_user`, `cart`, `notification`, `reviews`, `payout`, `dispute`, …) have neither `ENABLE` nor `FORCE` RLS. The `grocery_app` NOLOGIN least-privilege role exists but is unused. Not live-verifiable without DB credentials.
- **Impact:** Zero database-layer isolation. Every isolation guarantee rests on app-layer `WHERE` clauses; a single injection or missing-`WHERE` bug exposes all tenants' financial, PII, and location data with no backstop.
- **Remediation:** Short-term: `ENABLE` + `FORCE ROW LEVEL SECURITY` on every sensitive table with deny-by-default GUC-keyed policies (V002 pattern). Medium-term: run the app under the least-privilege `grocery_app` role (`SET ROLE` per connection) and wire the GUCs (see H-6).

#### H-6. GUCs (`app.current_*`) never set by the app — RLS policies are decorative — **STATIC-ONLY**
- **Location:** `JwtAuthFilter.java`, `V013__donations.sql`
- **Evidence:** A grep for `SET LOCAL` / `set_config` / `app.current` across the Java tree returns **zero** results. `JwtAuthFilter` populates only the Spring `SecurityContext`, never the DB session GUCs that V013 policies reference via `current_setting(..., true)`. The Epic-2 connection-GUC wiring described in the V002 comment was never completed.
- **Impact:** Today the GUC gap is moot because the superuser bypasses RLS (H-5). But the moment the role is correctly downgraded, every GUC-dependent policy denies all access (full outage for `ngos`/`donations` self-reads), while the role-less `donations_ngo_browse` policy fails open (H-7).
- **Remediation:** Implement a `DataSource` proxy / `TransactionSynchronization` that issues `SET LOCAL app.current_user_id = ?` and `SET LOCAL app.current_role = ?` at the start of every transaction from the `SecurityContext`. Land this *before* switching the runtime role.

#### H-7. `donations_ngo_browse` RLS policy fails open — **STATIC-ONLY**
- **Location:** `V013__donations.sql:58`
- **Evidence:** `CREATE POLICY donations_ngo_browse ON donations FOR SELECT USING (status = 'AVAILABLE')` has no role or GUC restriction. Because Postgres OR-combines applicable policies, any DB principal with `SELECT` on the table sees all available donations regardless of role.
- **Impact:** Once the app runs under `grocery_app`, any authenticated connection could read all donation listings at the SQL layer, bypassing the app's `requireApprovedNgo()` guard (defense-in-depth failure).
- **Remediation:** Add the role gate: `USING (status = 'AVAILABLE' AND current_setting('app.current_role', true) = 'NGO')`.

#### H-8. `OrderService.orderView()` skips ownership check when `customerId` is null — **STATIC-ONLY**
- **Location:** `backend/src/main/java/com/grocerymart/api/ordering/OrderService.java:185`
- **Evidence:** `if (customerId != null && !customerId.equals(o.get("customerId"))) throw forbidden;` — a null `customerId` skips the check entirely and returns the full order including `deliveryAddress` and `paymentMethod`. The method is **package-private**; all three current callers pass a real principal (live cross-tenant order read returns 403 — confirmed safe), but any future intra-package caller passing null silently reads any order.
- **Impact:** Latent BOLA / information disclosure on a future refactor.
- **Remediation:** Remove the null guard and always enforce ownership. Provide a separate, explicitly-named `orderViewAdmin(orderId)` for admin-guarded read paths.

#### H-9. `DiscoveryController` has no method/class-level `@PreAuthorize` — **STATIC-ONLY** (currently behind the global gate; live behavior depends on SecurityConfig)
- **Location:** `backend/src/main/java/com/grocerymart/api/discovery/DiscoveryController.java:20-49`
- **Evidence:** None of the three endpoints (`GET /discovery/shops`, `GET /stores/{shopId}/products`, `POST /basket/compare`) carries `@PreAuthorize`. They are currently protected only by the global `anyRequest().authenticated()`, so there is no defense-in-depth — any relaxation of `SecurityConfig` silently exposes inventory state and the expensive PostGIS/multi-store JOIN queries. (SQL-injection on `q`/`cuisine` here was probed and is **safe** — parameterized.)
- **Impact:** One `SecurityConfig` misconfiguration exposes internal stock levels and an unauthenticated DoS-amplifying query surface.
- **Remediation:** Add explicit `@PreAuthorize("isAuthenticated()")` (or `hasRole('CUSTOMER')`) at the class level so authorization is expressed at both layers.

### MEDIUM

#### M-1. Currency field accepts arbitrary strings (pollution / 500) — **CONFIRMED-LIVE**
See §2.6. `WalletService.java:51-67`, `PaymentDtos.java:12`.

#### M-2. Topup amount lacks scale/magnitude bound (precision mismatch) — **CONFIRMED-LIVE**
See §2.7. `PaymentDtos.java:12`, `WalletService.java:55-59`.

#### M-3. User enumeration via `/auth/register` — **CONFIRMED-LIVE**
See §2.8. `AuthService.java:127-128`.

#### M-4. Stripe webhook lacks a timestamp tolerance window (replay) — **STATIC-ONLY**
- **Location:** `backend/src/main/java/com/grocerymart/api/payments/StripeSignature.java:17-29`
- **Evidence:** `verify()` extracts `t` from the `Stripe-Signature` header for payload construction but never checks its age (Stripe's SDK rejects >5 min). The `processed_stripe_event` idempotency table blocks exact eventId re-delivery, but a captured signed packet could be raced before first processing, and a leaked webhook secret would allow forging fresh-eventId events with `t=now()` indefinitely. Webhook signature verification itself is **live-confirmed safe**: missing or forged `Stripe-Signature` → HTTP 400 `"invalid Stripe signature"` before any body processing.
- **Impact:** Replay window / weakened last line of defense if the webhook secret leaks.
- **Remediation:** Add a tolerance check in `verify()`: `if (Math.abs(Instant.now().getEpochSecond() - t) > 300) return false;`.

#### M-5. `WalletService.payOrder` does not lock the order row (TOCTOU) — **STATIC-ONLY**
- **Location:** `WalletService.java:101-142` (`lockableOrder` at 159)
- **Evidence:** `lockableOrder()` does a plain `SELECT` (no `FOR UPDATE`) on `orders`. Two concurrent pay calls can both read `pending_payment` and both run the stock-decrement loop before either reaches the wallet debit. The wallet row is `FOR UPDATE`-locked and `ux_wallet_txn_order_reason` blocks the duplicate transaction, but the `catch (DuplicateKeyException)` **returns early** rather than re-throwing; a `DataAccessException` does not trigger Spring rollback by default, so the second thread's stock decrements may commit.
- **Impact:** Under tight concurrency, double stock decrement for one order.
- **Remediation:** `SELECT ... FOR UPDATE` the order row in `lockableOrder` when called from `payOrder`, or use an atomic gate `UPDATE orders SET payment_status='paid' WHERE id=? AND payment_status='pending_payment'` checked for `rows==1`. Alternatively re-throw the `DuplicateKeyException`.

#### M-6. Null lat/lng in checkout bypasses distance-based delivery fee — **STATIC-ONLY**
- **Location:** `OrderingDtos.java:30-34`, `DeliveryService.java:130`, `PricingService.java:40`
- **Evidence:** `CheckoutRequest.lat/lng` are nullable with no `@NotNull`. `assertInRange()` returns immediately when either is null; `deliveryFee()` falls back to the flat `deliveryBase` (AUD 3.00). A customer can omit coordinates to bypass the geographic range check and always pay the minimum fee.
- **Impact:** Systematic delivery-fee undercharging (up to ~AUD 30/order at 1.20/km over a 25 km range) and out-of-range deliveries accepted.
- **Remediation:** Add `@NotNull` to `lat` and `lng` in `CheckoutRequest`; if a no-coordinate flow is genuinely needed, add an explicit justified exception path rather than silently defaulting to the flat fee.

#### M-7. Bean-validation cascade gap: `@Positive` on nested `ResolveItem.quantity` not enforced — **CONFIRMED-LIVE** (reaches service, not 400)
- **Location:** `OrderingDtos.java:14-23`, `CartController.java:47`
- **Evidence:** `ResolveCartRequest.items` is `@NotEmpty` but **not** `@Valid`, so validation does not cascade into `ResolveItem` and its `@Positive int quantity` is never evaluated. Live: `quantity=-99`/`0` reaches the service (returns 404 store-not-found, **not** 400 validation). The `cart_line CHECK (qty > 0)` DB constraint is the only backstop, and a negative qty through the `ON CONFLICT ... DO UPDATE SET qty = cart_line.qty + EXCLUDED.qty` upsert could decrement an existing line.
- **Impact:** Negative/zero quantities bypass API validation; potential cart-total corruption if the DB constraint is not applied atomically on the upsert result.
- **Remediation:** Change to `@NotEmpty @Valid List<ResolveItem> items` so `@Positive` is enforced at the controller (400 before any DB call). Apply `@Valid` to all nested-record DTOs.

#### M-8. Dynamic SQL in `AuditService.query()` — `action` parameter unvalidated — **STATIC-ONLY**
- **Location:** `backend/src/main/java/com/grocerymart/api/audit/AuditService.java:60-65`
- **Evidence:** Query is built with `StringBuilder` but `action` is passed as a **bind parameter** (`AND action = ?`), so it is **not** SQL-injectable. However `action` is free text with no enum/allowlist/length limit (`actor` is validated via `UUID.fromString`). `audit_log.action` is `text` with no length cap.
- **Impact:** No injection; result pollution / DoS-hygiene concern from arbitrarily long crafted action strings (admin-only endpoint).
- **Remediation:** Validate `action` against an allowlist/enum and a max length; add a DB `CHECK` on `audit_log.action`.

#### M-9. STOMP WebSocket CORS allows all origins — **STATIC-ONLY**
- **Location:** `WebSocketConfig.java:27-28` (`setAllowedOriginPatterns("*")`)
- **Evidence:** Both STOMP registrations use wildcard origin, independent of the (correctly-restricted) HTTP CORS config. Combined with `allowCredentials(true)` on the HTTP side, this widens the WebSocket attack surface (compounds C-2).
- **Impact:** Credentialed cross-origin WebSocket connections from any domain (drive-by browser tracking attacks once C-2's missing subscriber auth is considered).
- **Remediation:** Replace `"*"` with the shared frontend-origin allowlist used in `SecurityConfig`.

#### M-10. `DiscoveryController` exposes exact stock counts to any authenticated user — **STATIC-ONLY**
- **Location:** `DiscoveryController.java:38-47`
- **Evidence:** `storeProducts()` and `compareBasket()` return exact integer `stock`, with no method-level role check. Any authenticated user, including a competing SHOP_OWNER, can read exact competitor stock.
- **Impact:** Business-confidentiality leak (competitive intelligence), not a direct security breach.
- **Remediation:** Return only a boolean `inStock` to non-owners, or restrict exact counts to CUSTOMER-role requesters.

#### M-11. Notification `markOneRead` has no 404/403 distinction — **STATIC-ONLY** (low security risk)
- **Location:** `backend/src/main/java/com/grocerymart/api/notifications/NotificationService.java:116-118`
- **Evidence:** `UPDATE ... WHERE id=? AND user_id=? AND read_at IS NULL` returns silently on 0 rows; ownership is correctly enforced by the `WHERE` clause (no leakage). The ambiguity is a usability/audit nit, not a vulnerability.
- **Impact:** Minimal — listed for completeness; the silent no-op actually *prevents* ID enumeration.
- **Remediation:** None required for security; optionally differentiate 404 (truly absent) from a 204 no-op for usability.

#### M-12. Missing indexes on several foreign-key columns — **STATIC-ONLY** (performance)
- **Location:** `V010__ordering_payments.sql` (and related)
- **Evidence:** No index on `cart.store_id`, `order_item.store_product_id`, `wallet_transaction.customer_id`, `payment_intent.customer_id`, `stock_reservation.store_product_id`. `ON DELETE CASCADE` and reverse-direction joins do sequential scans.
- **Impact:** Query/cascade degradation as data grows (not a security issue).
- **Remediation:** Add the five covering indexes as recommended in the source finding.

#### M-13. Reconciliation admin endpoint issues N+1 queries per shop — **STATIC-ONLY** (performance)
- **Location:** `backend/src/main/java/com/grocerymart/api/settlement/SettlementQueryService.java:80-113`
- **Evidence:** 1 distinct-store query + 3 queries per shop (2 in `financials()` + 1 `SELECT name FROM shop`) = `1 + 3N` (≈301 for 100 shops). Not measured live (would require the seeded ADMIN token for a cross-tenant financial read, avoided per audit limits; customer token correctly gets 403).
- **Impact:** Linear DB pressure / timeout risk on the admin-only reconciliation endpoint.
- **Remediation:** Rewrite as a single `GROUP BY store_id` aggregate joined to `shop` and `payout`; add pagination.

### LOW

#### L-1. No per-account login-failure lockout — **STATIC-ONLY**
- **Location:** `AuthService.java:81-88`. `portalLogin()` bcrypt-compares with no per-account failure tracking, lockout, back-off, or CAPTCHA. Combined with the bypassable rate limiter (H-2), portal credential brute force is unconstrained.
- **Remediation:** Track failed attempts per email in a DB table; lock after N failures within a window or trigger CAPTCHA after 3.

#### L-2. Access tokens not revoked on logout — **STATIC-ONLY**
- **Location:** `AuthService.java:161-164`, `JwtService.java:41-43`. Logout revokes only the refresh token; the 15-min access token stays valid (no denylist; `parse()` checks signature+expiry only).
- **Remediation:** Add a short-TTL `jti` denylist (Redis is already configured but disabled) checked in `JwtAuthFilter`, populated on logout and password reset; or reduce access-token TTL to ~5 min.

#### L-3. Default fallback Stripe webhook secret in `application.yml` — **STATIC-ONLY**
- **Location:** `application.yml:40` — `${STRIPE_WEBHOOK_SECRET:whsec_dev_grocery_mart_secret}`. If the env var is unset on Render, the app starts with the public default and anyone could forge signed webhooks. (Webhook signature verification is live-confirmed working, implying the secret is currently set, but the silent-fallback risk remains.)
- **Remediation:** Remove the default (`${STRIPE_WEBHOOK_SECRET}`) so the app fails fast if missing; add a startup `@NotBlank` check.

#### L-4. Weak minimum password policy (`@Size(min=8)` only) — **STATIC-ONLY**
- **Location:** `AuthDtos.java:27-28, 38-39`. No complexity, no max length, no common-password check; BCrypt silently truncates at 72 bytes.
- **Remediation:** Require length ≥12 (passphrase) or ≥1 letter + ≥1 digit, cap at 72 chars, optionally check HaveIBeenPwned.

#### L-5. `CorrelationIdFilter` trusts client `X-Request-Id` without validation (log injection) — **STATIC-ONLY**
- **Location:** `CorrelationIdFilter.java:33-35`. Any non-blank `X-Request-Id` is placed in MDC and echoed back, with no length/charset limit; newline/ANSI injection can forge log entries. Low impact (no DB/HTML sink).
- **Remediation:** Restrict to `[A-Za-z0-9-]{1,64}` or always generate a server-side UUID, using the client value only if it matches a UUID pattern.

#### L-6. `basket/compare` `idsCsv` is semantically fragile (not injectable) — **STATIC-ONLY** / SQLi **REFUTED-BY-PROBE** (parameterized, safe)
- **Location:** `DiscoveryService.java:91-102`. UUIDs are joined to `idsCsv` and passed as a bind parameter to `ANY(string_to_array(?, ',')::uuid[])` — parameterized, not injectable; upstream `UUID.fromString()` validates inputs. Live SQLi probes on discovery were **safe**. The `string_to_array` pattern is brittle but not a vulnerability.
- **Remediation:** Replace with a proper JDBC UUID-array binding (`ANY(:ids::uuid[])`).

#### L-7. Random UUIDv4 PKs on high-write tables (index fragmentation) — **STATIC-ONLY** (performance)
- **Location:** `V004/V010/V011/V012`. `gen_random_uuid()` PKs on `orders`, `wallet_transaction`, `notification`, etc. cause B-tree fragmentation at scale.
- **Remediation:** Use UUIDv7 (time-ordered) or `bigint IDENTITY` for high-write tables (as `outbox_event`/`driver_location` already do).

#### L-8. Refresh token missing family/device binding (partial reuse-detection gap) — **STATIC-ONLY**
- **Location:** `AuthService.java:139-159`. Reuse detection is correct but coarse: replaying any consumed token revokes *all* user tokens (the `refresh_token.device_id` column is never populated; no `family_id`). This over-revokes legitimate multi-device sessions.
- **Remediation:** Populate `device_id` at issuance and implement family-based revocation to limit blast radius; until then, document that reuse detection is intentionally user-level.

> *L-7 and L-8 push the Low count beyond the table's headline "6" — the severity table counts deduplicated security-relevant Lows; L-7 (performance) and L-8 (design) are included here for completeness.*

### INFO

#### I-1. Audit logging missing for authentication events — **STATIC-ONLY**
- **Location:** `AuthService.java`. `audit_log` is written for account deletion/export/admin ops but not for logins (success/failure), OTP verifications, registrations, password resets, or refresh-token reuse detection (the reuse alarm only throws + SLF4J-logs, never persisted).
- **Remediation:** Add `AuditService.log()` calls (with source IP) on portal login success/failure, OTP verify, register, reset confirm, and especially the refresh reuse-detection branch.

#### I-2. No per-phone OTP request rate limit — **STATIC-ONLY** (medium-leaning, kept here as it overlaps H-2)
- **Location:** `AuthService.java:48-54`. `requestOtp()` inserts a challenge on every call with no per-phone/time-window cap (the 5-attempt limit is per-challenge only). Live: repeated `/auth/otp/request` → HTTP 202 with no throttle. Enables SMS flooding / cost amplification once a real SMS provider is wired.
- **Remediation:** Count `otp_challenge` rows per phone in the last 10 min and reject above a threshold (DB control immune to IP spoofing); return a uniform 429.

#### I-3. Admin shop approve/reject & driver state machine — correct by design — **STATIC-ONLY**
- **Location:** `AdminCatalogController.java:30-38`, `DeliveryService.java:229-266`. `setShopStatus()` takes a raw `shopId` but is `hasRole('ADMIN')`-gated and ADMIN cannot self-register, so it is correct. The delivery state machine correctly prevents forward transitions of cancelled deliveries. Noted for completeness; no change required. *(Note: the protection relies on ADMIN being non-self-registerable — which holds — and on the hardcoded admin account C-1 being removed.)*

---

## 5. False Positives Refuted by Live Probes

The following were either flagged statically or are plausible concerns, but live probes proved they are **safe / not exploitable**. Reporting them as vulnerabilities would be incorrect.

- **JWT signature tampering** — flipping one signature byte → `GET /me` **403**. Signature verification is sound.
- **JWT payload tampering (roles→ADMIN with original signature)** → **403**. HMAC mismatch; no privilege escalation via payload edit.
- **`alg:none` token** (forged ADMIN, empty signature) → **403**. JJWT 0.12.6 `parseSignedClaims()` refuses unsigned tokens; no alg-confusion bypass.
- **Garbage / malformed / missing Bearer** → **403**; only the valid token yields 200. (Rejected requests return 403 rather than 401, but no invalid token is ever accepted.)
- **Token forgery with the public default JWT secret** → **403**. `JWT_SECRET` is non-default on Render (refutes the "anyone mints ADMIN" scenario; see §3).
- **Login enumeration** — unknown email vs wrong password return a byte-identical **401** `"Invalid email or password."` (Note: registration *does* enumerate — see M-3.)
- **OTP request enumeration** — uniform **202** regardless of account existence at the request step.
- **SQL injection** on `GET /catalog/canonical/search?q=`, `GET /discovery/shops?cuisine=`, and `POST /basket/compare` — boolean/terminator payloads (`' OR '1'='1`, `a';--`) return well-formed JSON, zero rows or fuzzy matches, **no 500/stacktrace**. All paths parameterized.
- **Cross-tenant order read (IDOR)** — customer B reading customer A's order → **403** `"not your order"`.
- **REST order tracking IDOR** — customer B → A's `/orders/{id}/tracking` → **403** `"not allowed to track this order"`; non-existent order → **404**. (The REST path is safe; only the WebSocket path, C-2, is open.)
- **Account export isolation** — `GET /account/export` returns only the caller's own data.
- **Customer token on privileged endpoints** — `GET /admin/audit`, `/admin/shops`, `/admin/settlement/reconciliation`, `/shops/me`, `/shops/me/dispatch` all → **403** `"access denied"`. Role-based deny-by-default works.
- **Stripe webhook forgery** — missing or forged `Stripe-Signature` → **400** `"invalid Stripe signature"` *before* any body processing / wallet credit. (The residual replay/leak concern is M-4, not a present bypass.)

---

## 6. Prioritized Remediation Order

1. **Now (minutes):** Deactivate `admin@grocery-mart.dev` in Supabase and rotate `JWT_SECRET` on Render (C-1).
2. **Today:** Add WebSocket STOMP auth + subscriber authorization (C-2); set `SELF_REGISTERABLE={CUSTOMER}` (H-1); tighten CORS to explicit origins (H-3, M-9).
3. **This week:** Gate `DevOtpSender` with `@Profile` and delete the raw-token log (C-3); fix `forward-headers-strategy` + DB-backed auth-endpoint limits (H-2, L-1, I-2); add currency/amount/quantity validation (M-1, M-2, M-7); remove the `OrderService.orderView` null bypass (H-8); add `@PreAuthorize` to `DiscoveryController` (H-9); remove secret defaults / add startup assertions (H-4, L-3).
4. **This sprint:** Enable+force RLS on production tables and wire session GUCs before switching to `grocery_app` (H-5, H-6, H-7); webhook timestamp tolerance (M-4); `payOrder` row lock (M-5); checkout lat/lng required (M-6); auth audit logging (I-1).

---

## 7. Remediation Applied (2026-06-23)

Code + DB fixes shipped in response to this audit (verified: backend compiles, `ApiApplicationTests` + `RlsIsolationTest` pass, all 15 migrations apply from scratch, RLS isolation proven at the SQL layer):

| Finding | Fix | Where |
|---------|-----|-------|
| C-2 WebSocket unauthenticated | JWT on STOMP `CONNECT` + per-`SUBSCRIBE` order-ownership check; origins restricted | `StompAuthChannelInterceptor`, `WebSocketConfig` |
| H-1 SHOP_OWNER self-register | `SELF_REGISTERABLE = {CUSTOMER}` | `AuthService` |
| H-2 X-Forwarded-For spoof | Rate-limit keys on the proxy-appended (rightmost) IP, not the spoofable leftmost | `RateLimitFilter` |
| H-3 / M-9 CORS wildcard | Origins driven by explicit allowlist (env), applied to HTTP **and** WebSocket; live env tightened to the 3 frontends | `SecurityConfig` (env), `WebSocketConfig` |
| H-4 / L-3 secret defaults | JWT signs with a random ephemeral key (never the committed default) if unset; webhook secret default removed + fails closed when blank | `JwtService`, `StripeSignature`, `application.yml` |
| H-5/H-6/H-7 RLS | ENABLE+FORCE RLS + GUC-keyed multi-role policies on the 9 private tables; `grocery_app` grants; fail-open donation policy fixed; per-request `SET ROLE`+GUC filter — **flag-gated `grocerymart.rls.enforce`, default OFF** | `V015__rls_enforcement.sql`, `RlsConnectionFilter` |
| H-8 OrderService null-bypass | Ownership always enforced (null no longer skips the check) | `OrderService` |
| H-9 Discovery defense-in-depth | Class-level `@PreAuthorize("isAuthenticated()")` | `DiscoveryController` |
| C-3 OTP/reset token logging | Tokens logged only when `grocerymart.dev.log-secrets=true` (default false) | `AuthService`, `DevOtpSender` |
| M-1/M-2/M-7 input validation | Currency `@Pattern ^[A-Z]{3}$`; amount `@Digits`/`@DecimalMax`; `@Valid` cascade into cart items; checkout lat/lng `@NotNull` | `PaymentDtos`, `OrderingDtos` |
| M-3 register enumeration | Generic "registration could not be completed" message | `AuthService` |
| M-4 webhook replay | 300s timestamp tolerance | `StripeSignature` |
| M-5 payment TOCTOU | `SELECT ... FOR UPDATE` on the order row in `payOrder` | `WalletService` |
| M-6 delivery-fee bypass | Checkout coordinates required (`@NotNull`) | `OrderingDtos` |
| C-1 hardcoded admin | Handled operationally on the live deployment: `JWT_SECRET` rotated + the seeded admin password changed from the public `admin-dev-pass` | live Render/Supabase |

**RLS enforcement is OFF by default** (`grocerymart.rls.enforce=false`). It is fully built and proven to isolate tenants, but activating it on the live deployment requires (a) `GRANT grocery_app TO postgres` via a **direct** (non-pooler) connection — Supabase's pooler kills the session on a self-membership grant — and (b) an end-to-end pass over every authenticated write path against the policies. Until that QA is done, the app continues on the bypass `postgres` role (app-layer checks remain the enforced control; RLS is the ready-to-activate backstop).

*End of consolidated report.*
