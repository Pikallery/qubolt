# Q-Loop — Supply Chain Optimization MVP

B2B SaaS that eliminates **empty-run inefficiencies** by simultaneously
optimizing delivery, returns, and disposal.

---

## Architecture

```
q-loop/
├── backend/          FastAPI + PostgreSQL + Celery + Redis
└── frontend/         Flutter (Web Dashboard + Android/iOS Driver & Gatekeeper)
```

### Core Technologies
| Layer | Technology |
|---|---|
| API | FastAPI (async) + Pydantic v2 |
| Database | PostgreSQL 16 + SQLAlchemy 2 (async) |
| Migrations | Alembic (4 versions) |
| Queue | Celery + Redis |
| Auth | Stateless JWT (HS256) + HMAC-SHA256 QR tokens |
| Routing | Simulated Annealing (pure Python, no solver dep) |
| AI | DeepSeek-R1 via NVIDIA API (OpenAI-compatible) |
| Comms | Twilio masked VoIP + SMS fallback |
| Frontend | Flutter + Riverpod + go_router + Mapbox GL |

---

## Quick Start

### 1. Copy environment
```bash
cp .env.example .env
# Fill in TWILIO_* and MAPBOX_ACCESS_TOKEN
# NVIDIA_API_KEY is pre-filled for DeepSeek-R1
```

### 2. Start services
```bash
docker-compose up -d
```

### 3. Run migrations
```bash
cd backend
alembic upgrade head
```

### 4. API is live
```
http://localhost:8000/docs     # Swagger UI
http://localhost:8000/health   # Health check
```

### 5. Flutter frontend
```bash
cd frontend
flutter pub get
flutter run -d chrome          # Web dashboard
flutter run -d <device>        # Mobile (Driver / Gatekeeper)
```

---

## Data Ingestion

POST a CSV to `/api/v1/ingestion/upload` with the `source_type` query param:

| Dataset | source_type | Rows |
|---|---|---|
| Delivery_Logistics.csv | `delivery_logistics` | 25,000 |
| Ecommerce_Delivery_Analytics_New.csv | `ecommerce_analytics` | 100,000 |
| delivery_points_rourkela.csv | `delivery_points` | 500 |

Auto-detection works if `source_type` is omitted — the ingestion service
identifies the file from its header columns.

---

## 3-Way QR Handshake

```
[Warehouse] ─── issues shipment ──→ [Backend creates QR token]
                                            │ HMAC-SHA256 signed
                                            ↓
[Driver App] ←── GET /auth/qr-generate/{id} ── PNG QR code (5 min TTL)
     │
     │  Driver shows QR at gate
     ↓
[Gatekeeper App] scans QR → POST /auth/qr-scan { token_hash, lat, lon }
                                            │
                                            ↓
                              Backend: validates HMAC + TTL
                              → marks token invalid (single-use)
                              → emits ShipmentEvent(picked_up)
                              → triggers Twilio SMS to customer
```

---

## Simulated Annealing Route Optimizer

- **Initial solution**: Nearest-neighbour greedy tour
- **Perturbation**: 2-opt swap
- **Acceptance**: Boltzmann criterion `P = e^(-ΔC/T)`
- **Cooling**: Geometric schedule `T(k) = T₀ × α^k`
- **Defaults**: T₀=1000, α=0.995, max_iter=10,000
- **Result**: Typically 15-30% distance improvement over greedy

Trigger via `POST /api/v1/routes/{id}/optimize` (async Celery task).
Poll status at `GET /api/v1/routes/{id}/optimize/status?task_id=...`

---

## DeepSeek AI (NVIDIA API)

Model: `deepseek-ai/deepseek-r1` — returns both `content` and `reasoning_content`.

| Endpoint | Function |
|---|---|
| `POST /ai/insight` | Supply chain narrative + delay/risk/cost analysis |
| `POST /ai/route-explain/{id}` | Plain-English SA decision explanation |
| `POST /ai/eta-predict/{id}` | Predicted delivery datetime |

---

## Multi-Tenancy

All tables include `tenant_id UUID NOT NULL` with FK to `tenants`.
Tenant is resolved from the JWT `tenant_id` claim on every request.
Row-level isolation — no cross-tenant data leakage possible at the query layer.

---

## Dashboard (Flutter Web)

- MongoDB Atlas-inspired dark sidebar (#161B22)
- Real-time metric cards (Total Shipments, In Transit, Delayed, On-Time Rate, Active Routes, Empty Runs Saved)
- Mapbox GL **ghost route** visualization — SA-optimised path as 50% opacity teal polyline
- Shipment status doughnut chart (fl_chart)
- Responsive: sidebar collapses on mobile

---

## Planned (Post-MVP)

- [ ] WebSocket real-time shipment event stream
- [ ] Mapbox GL live vehicle tracking (replace canvas placeholder)
- [ ] Multi-stop delivery + return loop optimization
- [ ] Tenant billing integration (Stripe)
- [ ] Partner API webhook ingestion
