# Qubolt — Quantum-Inspired Logistics Platform

**Q-Loop / Qubolt** is a B2B SaaS platform that eliminates empty-run inefficiencies across last-mile, return, and disposal flows. It combines a FastAPI backend, a Flutter multi-platform frontend, and quantum-inspired optimization (simulated annealing + behavioural entropy) to route shipments through Odisha's logistics network.

> The application source lives under [`q-loop/`](q-loop/). Detailed engineering notes are in [`q-loop/README.md`](q-loop/README.md).

---

## Project Architecture

```
┌───────────────────────────────────────────────────────────────────────┐
│                         Flutter Frontend                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │ Admin / Mgr  │  │ Hub Operator │  │   Driver     │  │ Gatekeeper│ │
│  │  Web Dash    │  │  Web / PWA   │  │  Mobile App  │  │ Mobile App│ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └─────┬─────┘ │
│         │                 │                 │                │       │
│         └────────── Riverpod + go_router + Dio + Mapbox ─────┘       │
└───────────────────────────────────┬───────────────────────────────────┘
                                    │  HTTPS + JWT (HS256)
                                    │  X-Tenant-ID header
                                    ▼
┌───────────────────────────────────────────────────────────────────────┐
│                     FastAPI Backend (async)                           │
│  Auth · Shipments · Routes · Ingestion · Events · AI · QR · Users     │
│  Pydantic v2 · SQLAlchemy 2 async · Alembic migrations                │
└────────┬──────────────────┬──────────────────┬───────────────────────┘
         │                  │                  │
         ▼                  ▼                  ▼
   ┌──────────┐       ┌──────────┐      ┌─────────────┐
   │ Postgres │       │  Redis   │      │   Celery    │
   │    16    │       │  cache/  │◀────▶│   Worker    │
   │ tenants· │       │  broker  │      │ SA routing· │
   │shipments │       │          │      │ AI pipeline │
   └──────────┘       └──────────┘      └─────────────┘
                                               │
                                               ▼
                               ┌────────────────────────────────┐
                               │ External: Mapbox · Gemini AI · │
                               │ Twilio · Firebase              │
                               └────────────────────────────────┘
```

### Layered Breakdown

| Layer | Tech | Responsibility |
|---|---|---|
| UI | Flutter 3 (Web + Mobile) | Role-based views, maps, real-time UI |
| State | Riverpod | Reactive state & dependency injection |
| Routing | go_router | Deep-linking, auth guards |
| HTTP | Dio | Auth interceptor, tenant header, retries |
| API | FastAPI (async) | REST endpoints, OpenAPI schema |
| Auth | JWT (HS256) + HMAC QR | Stateless sessions, single-use QR tokens |
| ORM | SQLAlchemy 2 async | Row-level multi-tenancy |
| DB | PostgreSQL 16 | Shipments, users, events, routes |
| Cache/Broker | Redis 7 | Rate limits, Celery broker, Mapbox tile cache |
| Worker | Celery | SA optimizer, bulk ingestion, AI calls |
| Deploy | Docker Compose | 4-service stack: backend · worker · postgres · redis |

---

## Quantum Advantage

Qubolt borrows two quantum-computing primitives and maps them onto classical logistics:

1. **Simulated Annealing (SA)** for multi-stop routing — a direct classical analogue of quantum annealing. Starts from a nearest-neighbour tour, perturbs via 2-opt swap, and accepts worse solutions with Boltzmann probability `P = e^(-ΔC/T)`. Cooling schedule `T(k) = T₀·α^k`. Escapes the greedy-solver local minima that trap TSP/VRP heuristics, yielding a typical 15–30% distance saving.
2. **Behavioural Entropy** — a quantum-wave-function inspired score over each driver/hub's event distribution. Low entropy ⇒ predictable operator (reliable ETA). High entropy ⇒ anomalous behaviour (flag for review). Used in the dashboard's "wave function" chart.

Together these enable empty-run elimination: the system simultaneously solves the delivery **and** return-leg assignment for each vehicle, instead of running two independent greedy passes.

---

## User Roles

Role hierarchy (from [`q-loop/backend/app/dependencies.py`](q-loop/backend/app/dependencies.py)):

| Role | Level | Capabilities |
|---|---|---|
| `superadmin` | 100 | Cross-tenant administration |
| `admin` | 80 | Full tenant admin, user management |
| `manager` | 70 | Assign drivers, view analytics, approve routes |
| `operator` | 60 | Hub operations, shipment intake, dispatch |
| `gatekeeper` | 40 | QR scan at hub gate, verify driver arrival |
| `driver` | 40 | Mobile app: pickups, transit, hub arrival |
| `viewer` | 20 | Read-only dashboards |

Every API dependency uses `require_min_role(...)` for RBAC; tenant isolation is enforced at the ORM layer via `tenant_id` on every query.

---

## Core Workflows

### 1. Shipment lifecycle
```
created → assigned → picked_up → in_transit → driver_arrived → delivered
```
Each transition emits a `ShipmentEvent` with geo-coordinates, actor, and timestamp. Events feed the live dashboard and the behavioural-entropy score.

### 2. Driver hub-arrival flow
1. Driver picks up shipment from origin.
2. Status → `in_transit`. Flutter app displays "Drop at Hub: Bhubaneswar Regional Hub" banner.
3. Mapbox Directions API draws a road-following route from driver GPS → hub.
4. Driver taps **Arrived at Hub** ⇒ POST `/shipments/{id}/events` with `event_type=driver_arrived`.
5. Hub Operator view shows a "Driver Arrived" badge and auto-refreshes every 20 s.
6. Gatekeeper scans QR on the package → single-use HMAC token validated → shipment marked `delivered`.

### 3. QR handshake (3-way, HMAC-SHA256, 5 min TTL)
```
Warehouse creates shipment → Backend mints signed QR token
Driver shows QR → Gatekeeper scans → POST /auth/qr-scan
Backend validates HMAC + TTL → single-use invalidation → event emitted
```

### 4. Ingestion pipeline
`POST /api/v1/ingestion/upload?source_type=<...>` → Celery task → streams CSV rows into `shipments` with dedup by tenant + external_id.

---

## Key Sections of the Dashboard

- **Overview** — live KPI cards (Total, In-Transit, Delayed, On-Time %, Active Routes, Empty-Runs-Saved).
- **Shipments** — per-row **Assign Driver** action (manager+), status filter, bulk import.
- **Routes** — Mapbox GL "ghost route" overlay, SA-optimized polyline, `POST /routes/{id}/optimize` trigger.
- **Analytics** — Behavioural-Entropy wave chart, driver on-time history, region heatmap.
- **Users & Drivers** — role management, driver roster (`GET /users/drivers`, manager+).
- **Geofences** — interactive Odisha hub-zone editor.
- **Messenger** — Firebase Firestore real-time chat + Twilio masked VoIP.
- **Proof-of-Delivery** — photo viewer with geo-tagged timestamps.

---

## Quick Start

```bash
# 1. Environment
cd q-loop
cp .env.example .env           # fill GEMINI_API_KEY, TWILIO_*, MAPBOX_ACCESS_TOKEN

# 2. Stack
docker-compose up -d           # backend, worker, postgres, redis

# 3. Migrations
docker exec -it q-loop-backend alembic upgrade head

# 4. Frontend
cd frontend
flutter pub get
flutter run -d chrome          # web dashboard
flutter run -d <device-id>     # driver / gatekeeper mobile
```

APIs at `http://localhost:8000/docs`. Default web build served at `http://localhost:8080`.

---

## Repository Layout

```
.
├── q-loop/
│   ├── backend/              FastAPI service + Alembic migrations + Celery tasks
│   │   ├── app/
│   │   │   ├── api/v1/       Route modules: auth, shipments, users, routes, ai, ...
│   │   │   ├── core/         Config, security, logging
│   │   │   ├── db/           Models, session, base
│   │   │   ├── services/     SA optimizer, Gemini client, Twilio client, QR signer
│   │   │   └── workers/      Celery tasks
│   │   └── alembic/versions/ Schema migrations 0001-0010
│   ├── frontend/
│   │   ├── lib/features/     shipments/, routes/, analytics/, auth/, messenger/
│   │   ├── lib/core/         API constants, theme, Dio setup, Riverpod providers
│   │   └── web/              Custom flutter_bootstrap.js (service worker disabled)
│   ├── docker-compose.yml
│   └── README.md             Detailed engineering notes
└── README.md                 (this file)
```

---

## License

Proprietary — © Pikallery. All rights reserved.
