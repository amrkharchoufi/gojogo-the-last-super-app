# GojoGo — Backend Architecture & Build Plan

Status: planning document, backend not yet started (iOS app is a SwiftUI prototype on sample data)
Stack: Spring Boot (modular monolith, Spring Modulith) · AWS · Postgres · iOS/SwiftUI client
Budget context: build proceeding in small paid milestones (~$100 increments of Claude usage)

---

## 1. Guiding principle

**Modular monolith now, microservices later — only when forced to.** One deployable Spring Boot application, internally split into modules that never share database tables, never call each other's internals directly, and communicate only through public interfaces and domain events. This gets almost all the benefit of microservices (clean boundaries, independent reasoning, safe parallel work) without the operational cost (N deployments, N databases, service-to-service auth, a gateway) before that cost is justified.

Scalability comes from statelessness + horizontal scaling + caching, not from splitting services. A stateless Spring Boot monolith behind a load balancer, with Redis caching and read replicas, scales to very large traffic before any module needs to become its own service — this is how Shopify and GitHub operate at enormous scale.

**When to actually split a module out**, and not before:
- A workload needs different scaling/hardware than the rest (video transcoding needing GPU-ish instances; the dispatch/geo-matching module needing low-latency co-located Redis).
- A module's failure mode must not take down everything else (realtime chat crashing shouldn't break checkout).
- A team boundary forms and independent deploy cadence is needed (not relevant solo, relevant once you hire).

---

## 2. Enforcing the boundary: Spring Modulith

Use **Spring Modulith** (official Spring project) instead of relying on folder-structure convention:

- Each domain is a top-level package (`com.gojogo.social`, `com.gojogo.profile`, `com.gojogo.media`, ...). A module may expose a public API package; everything else in the module is package-private and physically inaccessible from other modules.
- `ApplicationModules.of(GojogoApplication.class).verify()` runs in the test suite and **fails the build** if any module reaches into another module's internals. This is what prevents the boundary from rotting under deadline pressure — it's enforced, not just agreed upon.
- Cross-module communication happens two ways:
  1. **Synchronous, public API call** — module A calls an explicit public interface method on module B (e.g., `ProfileLookupApi.getUser(id)`), never B's repository or entities directly.
  2. **Asynchronous, event-driven** — module A publishes a domain event (`PostCreated`, `OrderPlaced`, `UserFollowed`); other modules react via `@ApplicationModuleListener`. In-process now; swapping the transport to SQS/EventBridge later is a config change, not a rewrite.
- `@ApplicationModuleTest` lets you test one module in isolation, bootstrapping only its dependencies — this is also what makes eventual extraction low-risk: the module's test suite already proves it works standalone.

## 3. Data ownership rule

**Schema-per-module in one physical Postgres database**, from day one:

- `social.*`, `profile.*`, `media.*`, `delivery.*`, `travel.*`, `economy.*`, `partner.*` — one schema per domain module.
- **No foreign keys across schemas. No cross-schema JOINs in application code, ever.** If module A needs data owned by module B, it calls B's public API or reacts to B's events — never queries B's tables directly.
- This is the single highest-leverage rule in this document. When a module is later extracted into its own service, its schema is already isolated — you point a new database connection at it and nothing about the module's internal code changes.

## 4. Target system diagram (full vision)

```
iOS app (SwiftUI)
   │
   ├── CloudFront ──► S3 (media, HLS video)
   ├── ALB / API Gateway ──► Spring Boot modular monolith (App Runner → ECS Fargate later)
   ├── API Gateway (WebSocket) ──► Realtime module (chat, typing, live tracking)
   └── Cognito (auth, JWT)

Spring Boot monolith modules:
   social · profile · media · delivery · travel · economy · partner
   — each with its own Postgres schema, communicating via public APIs + domain events

Shared infra:
   Postgres (RDS) · Redis (ElastiCache — cache, sessions, geo dispatch) · OpenSearch (search)
   S3 (media) · MediaConvert (video transcoding) · Bedrock (Madeleine AI)
   EventBridge / SQS (async event fan-out) · SNS → APNs (push)
```

## 5. Domain → module mapping (from current iOS app)

| iOS screen / model (existing) | Backend module | Schema | Notes |
|---|---|---|---|
| `WelcomeView`, `EmailSignUpView`, `OnboardingFlow` | `auth` (thin — mostly Cognito) | — | Cognito user pool; app-side profile creation on first login |
| `HomeView`, `Post`, `Story`, `Comment`, `ComposePostView` | `social` | `social` | Feed, posts, stories, comments, likes, follows |
| `ProfileView`, `ProfileHomeView`, `GGUser`, `ProfileUser` | `profile` | `profile` | User profiles, settings, interests |
| `ShortsView`, `WatchView`, `GojoTVView`, `VideoItem`, `Short`, `TVShow` | `media` | `media` | Video catalog + S3/MediaConvert/CloudFront pipeline |
| `WorldChatView`, `WorldConversation`, `WorldMessage`, polls/reactions | `realtime` | `realtime` (mostly DynamoDB, not Postgres) | WebSocket-based, kept semi-separate from day one — natural first extraction candidate |
| `GojoTravelView`, `TravelPlace`, `RideOption`, `TravelDriver` | `travel` | `travel` | Ride-hailing; shares dispatch engine with delivery |
| `GojoDeliveryView`, `DeliveryRestaurant`, `DeliveryCartLine`, `DeliveryCourier` | `delivery` | `delivery` | Catalog/orders; shares dispatch engine with travel |
| `EconomyView`, `Product`, seller chat | `economy` | `economy` | Marketplace |
| `PartnerFlowView`, `PartnerDashboardView`, `PartnerApplication` | `partner` | `partner` | Driver/courier onboarding + KYC workflow |
| `MadeleineHomeView`, `MadeleineOrb`, `WatchingMadeleineView` | `assistant` | `assistant` (mostly DynamoDB) | Bedrock-backed AI assistant |
| `SearchView` | (cross-cutting) | — | OpenSearch, indexed from domain events, not its own module |

## 6. Tech stack

| Layer | Choice | Why |
|---|---|---|
| Backend framework | **Spring Boot 3 + Spring Modulith** | Enforced module boundaries, built-in event-driven internal comms, documented monolith→microservice path |
| Language | Java 21 (or Kotlin, if preferred later) | |
| Database | **PostgreSQL** (AWS RDS) | Schema-per-module; system of record for users, posts, orders, trips, partner data |
| Cache / sessions / geo | **Redis** (ElastiCache) | Sessions, hot-feed cache, rate limiting, `GEOADD`/`GEOSEARCH` for dispatch |
| Realtime | DynamoDB + API Gateway WebSocket | Chat messages, connection registry, live trip/courier position — deliberately outside the Postgres monolith from day one |
| Search | OpenSearch | Indexed asynchronously off domain events |
| Media storage/delivery | S3 + CloudFront | All user media and video |
| Video transcoding | MediaConvert | HLS ABR ladder for Shorts/GojoTV |
| AI assistant | Amazon Bedrock (Claude) | Madeleine; DynamoDB for conversation memory |
| Auth | Amazon Cognito | JWT verified at the gateway; add Sign in with Apple |
| Payments | Stripe + Stripe Connect | Never build payment rails; ledger table in Postgres for reconciliation |
| Events | EventBridge (+ SQS consumers) | Async fan-out: search indexing, notifications, analytics |
| Push | SNS → APNs | |
| IaC | AWS CDK | |
| CI/CD | GitHub Actions → ECR → App Runner (→ ECS Fargate later) | |
| Deploy target (early) | **AWS App Runner** | Container-based, no ALB/VPC wiring to hand-manage yet; swap to ECS Fargate + ALB later with no code change |

---

## 7. Milestone plan — Phase 1 slice (current ~$100 budget)

Goal of this phase: **turn the app from a demo into a real product for its core loop** — real accounts, a real social feed, real media — while laying down the module/schema discipline so every later phase is cheap to add.

Each milestone is sized to run as its own Claude Code session (fresh context, cheaper). Model: Sonnet 5 by default; escalate to Opus/Fable only if a session gets stuck on something hard.

### Milestone 1 — Backend skeleton + auth
**Budget: ~$15–20**

- New Spring Boot 3 project (Maven multi-module or Modulith package structure), Java 21.
- Modules scaffolded: `auth`, `profile`, `social`, `media` (empty shells except `auth`).
- Spring Modulith wired in: `ApplicationModules.of(...).verify()` in the test suite from commit #1.
- AWS Cognito user pool created via CDK; Spring Security configured to validate Cognito JWTs.
- `/v1/auth/session` endpoint: given a valid Cognito JWT, create-or-fetch the app-side profile row.
- RDS Postgres instance (small, dev-tier) provisioned via CDK, one schema per module created (even if empty).
- Deployed to AWS App Runner via GitHub Actions; a health-check endpoint confirms the deploy.

**Definition of done:** you can sign up via Cognito from a REST client (or curl) and get back a JWT + a created profile row.

### Milestone 2 — Profiles + social API
**Budget: ~$25–30**

- `profile` module: user profile CRUD, interests, avatar reference (S3 key, not yet uploadable — that's milestone 3).
- `social` module: `Post`, `Story`, `Comment`, `Like`, `Follow` entities — mirroring the existing `Models.swift` shapes (`Post`, `PostMediaItem`, `Comment`, `StoryFrame`) so the iOS models map directly.
- Feed endpoint: `GET /v1/feed` — simple recency + following-based ordering (no ML ranking yet).
- Compose endpoint: `POST /v1/posts` (text + media references), `POST /v1/stories`.
- Follow/unfollow, like/unlike, comment endpoints.
- `social` publishes domain events (`PostCreated`, `UserFollowed`) via Spring Modulith's event system — no consumers yet, but the publish side is in place so `search`/`activity` can subscribe later at zero cost to `social`.

**Definition of done:** a client can create a profile, post content, follow another user, and see a feed — all against Postgres, no sample data.

### Milestone 3 — Media upload
**Budget: ~$10**

- S3 bucket for user media (`gojogo-user-media`), scoped IAM policy.
- `media` module: `POST /v1/media/presign` returns a presigned S3 PUT URL; client uploads directly to S3 (never proxied through the API).
- CloudFront distribution in front of the bucket for reads.
- `PostMediaItem`/`StoryFrame` records store the CloudFront URL once upload completes.

**Definition of done:** a photo taken/picked in the iOS compose flow uploads to S3 and renders back in the feed via CloudFront.

### Milestone 4 — iOS wiring
**Budget: ~$30**

- New `CoreNetworking` layer in the iOS app: `URLSession` + async/await, JWT storage/refresh (Keychain), typed request/response models matching the backend DTOs.
- Auth flow: `WelcomeView` → `EmailSignUpView` → Cognito hosted auth (or native Cognito SDK flow) → session established.
- Split `AppState` (currently one `ObservableObject` with 80+ `@Published` properties covering every domain) into per-domain observable stores: `SocialStore`, `ProfileStore`, at minimum — matching the module boundaries on the backend. Other domains (`WorldChatView`, `GojoTravelView`, etc.) keep using `SampleData` for now; only social/profile/media get wired live.
- Rewire `HomeView`, `ComposePostView`, `ProfileView`, `StoryViewer`, `CommentsSheet` off `SampleData` onto the live API.
- Media picker → presigned upload flow → post/story creation against the real backend.

**Definition of done:** running the app end-to-end — sign up, post a photo, see it in the feed, view another profile — with zero `SampleData` involved in that path.

### Milestone 5 — Buffer / hardening
**Budget: ~$15–20**

- Fix whatever milestones 1–4 leave rough: deploy issues, CDK edge cases, auth token refresh bugs, feed pagination.
- Basic error handling and empty/loading states in the wired iOS screens.
- Write `PROGRESS.md` (see §9) so future sessions resume cheaply.

**Running total: ~$95–120** — matches the $100 budget with a small buffer either way depending on how milestone 5 lands.

---

## 8. Later phases (not in current budget — for when you top up)

### Phase 2 — Realtime + commerce
- `realtime` module: WebSocket chat (DynamoDB-backed), matching `WorldChatView`/`WorldConversation`/`WorldMessage` — polls, reactions, replies, typing indicators.
- `economy` module: marketplace (`Product`, seller chat).
- `delivery` module: restaurant catalog, cart, orders (no live dispatch yet — order status only).
- Stripe + Stripe Connect integration; ledger table for reconciliation.
- OpenSearch wired up as a real `search` consumer of the `PostCreated`/`ProductCreated` events already being published since Milestone 2.
- `partner` module: driver/courier onboarding + KYC document upload workflow.

### Phase 3 — Dispatch + AI
- Redis geo-dispatch engine shared by `delivery` and `travel` — courier/driver matching, live position tracking.
- `travel` module: ride-hailing on top of the shared dispatch engine.
- `assistant` module: Madeleine on Bedrock, streamed over the existing WebSocket, DynamoDB conversation memory.
- Video pipeline: S3 → MediaConvert → HLS → CloudFront for user-generated Shorts/GojoTV content (today these use pre-supplied remote videos).

### Phase 4 — Extract what's earned it
By this point, natural extraction candidates (in likely order): `realtime` (already semi-separate on DynamoDB), the shared dispatch engine (`delivery` + `travel`), then `media`/video processing (different scaling profile — CPU/GPU-heavy transcoding vs. request-response API traffic). Extraction is cheap specifically because of the schema-per-module and event-driven discipline established in Phase 1 — each becomes its own Spring Boot service pointed at its own already-isolated data, communicating over the same event contracts that already existed in-process.

---

## 9. Session-to-session continuity

Maintain a `PROGRESS.md` at the repo root (created at the end of Milestone 5, updated at the end of every future milestone) recording: what's deployed, what's stubbed, known issues, and the next milestone to run. Each new Claude Code session should read `PROGRESS.md` first rather than re-deriving context — this is what keeps later sessions cheap.

---

## 10. Cost notes

- Claude usage: this plan assumes Sonnet 5 for nearly all sessions (~$8–20/session at current pricing), escalating to Opus/Fable only for genuinely hard debugging. Estimated 8–12 sessions to clear Milestones 1–5.
- AWS runtime cost at this dev scale: roughly $15–30/month (small RDS instance + App Runner + S3/CloudFront), well within typical free-tier/dev budgets — separate from the Claude credit and billed directly by AWS.
