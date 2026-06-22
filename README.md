# Grocery-Mart

Ethnic-grocery **price-comparison** marketplace (South Asian diaspora). Compare the
same item's price across nearby ethnic stores, build a basket, and order from the
cheapest fully-available store.

Polyglot **Nx monorepo**:

```
grocery-mart/
├── backend/                 Spring Boot 4.1 / Java 21 (Maven) — REST API /api/v1
├── apps/
│   ├── customer-mobile/     Flutter (browse, compare, order, track)
│   ├── driver-mobile/       Flutter (accept jobs, navigate, status)
│   ├── shop-portal/         React + Vite + TS (onboarding, catalog, orders)
│   └── admin-portal/        React + Vite + TS (approvals, merge queue, NGO, oversight)
├── packages/api-contract/   OpenAPI spec → generated TS + Dart clients
└── infra/                   docker-compose dev stack (PostGIS, Redis, MinIO)
```

> **Planning artifacts** (PRD, architecture, 86-story epic breakdown) live under
> `~/_bmad-output/planning-artifacts/` and the design doc under the legacy
> `grocery-app/docs/plans/`. This repo is **Epic 1 — Foundation & Walking Skeleton**.

## Prerequisites
- Java 21 (JDK) · Node 20+ · pnpm · Docker · Flutter 3.x (`/Volumes/xcode/flutter/bin`)

## Quick start (Phase 0)
```bash
# 1. infra
docker compose -f infra/docker-compose.yml up -d

# 2. backend (port 8080)
cd backend && ./mvnw spring-boot:run
# verify:  curl localhost:8080/api/v1/ping   ·   curl localhost:8080/actuator/health
```

## Stack notes
- **Spring Boot 4.1 / Java 21** (Maven). Java 25 + Gradle were the original picks;
  Java 25 needs interactive sudo to install and start.spring.io's Gradle generator
  is currently broken for Boot 4.1, so Maven + Java 21 (both fully supported) are used.
- PostgreSQL 16 + **PostGIS**, Redis, S3 (MinIO locally). RLS multi-tenancy, OpenAPI-first.
