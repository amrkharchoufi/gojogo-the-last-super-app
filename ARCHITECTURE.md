# GojoGo — System Architecture & Build Plan

Status: **Phase 1 complete** (auth / profile / social / media live); **Phase 2 · Milestones 1–3 deployed** — M1 My World messaging (+ WhatsApp-style setup), M2 platform notifications (activity feed, first consumer of social domain events), M3 APNs push (**activated** — key in Secrets Manager, verified authenticating to Apple; device delivery pending a physical-device test) + messaging polish (reply-linking, typing) — `messaging` module + DynamoDB + WebSocket infra + iOS wiring live in prod (two-user REST + real-time fan-out green), plus a **WhatsApp-style My World setup**: its own phone-verified identity (OTP over SNS + dev-code fallback) and World name/avatar, gated on first entry, separate from the app/social account. See [PROGRESS.md](PROGRESS.md) for deploy URLs, API surface, and known issues.
Stack: Spring Boot (modular monolith, Spring Modulith) · AWS · Postgres · iOS/SwiftUI client
Budget context: build in small paid milestones. Phase 2 Milestones 1–3 (My World messaging, notifications, APNs push + polish) are deployed; the next spend should finish the remaining Phase 2 loops (live device E2E, social sign-in verification) before spreading into commerce + delivery + Stripe.

---

## 1. Guiding principle

**Modular monolith now, microservices later — only when forced to.** One deployable Spring Boot application, internally split into modules that never share database tables, never call each other's internals directly, and communicate only through public interfaces and domain events. This gets almost all the benefit of microservices (clean boundaries, independent reasoning, safe parallel work) without the operational cost (N deployments, N databases, service-to-service auth, a gateway) before that cost is justified.

Scalability comes from statelessness + horizontal scaling + caching, not from splitting services. A stateless Spring Boot monolith behind a load balancer, with Redis caching and read replicas, scales to very large traffic before any module needs to become its own service.

**When to actually split a module out**, and not before:
- A workload needs different scaling/hardware than the rest (video transcoding; geo-dispatch needing low-latency co-located Redis).
- A module's failure mode must not take down everything else (messaging crashing shouldn't break checkout).
- A team boundary forms and independent deploy cadence is needed (not relevant solo, relevant once you hire).

---

## 2. Shape of the system: platform + verticals

GojoGo is a **superapp**. A flat list of equal modules under-explains how the iOS client is already structured (`AppNavMode.myWorld` vs `.collections`). Prefer this mental model:

```
┌─────────────────────────────────────────────────────────────┐
│                     PLATFORM (shared)                        │
│  identity · media · messaging · notifications · payments     │
│  dispatch · search                                           │
└─────────────────────────────────────────────────────────────┘
          ▲ used by ▼
┌─────────────────────────────────────────────────────────────┐
│                   VERTICAL PRODUCTS                          │
│  social · watch · travel · delivery · economy · partner      │
│  assistant                                                   │
└─────────────────────────────────────────────────────────────┘
```

| Layer | Modules | Role |
|---|---|---|
| **Platform** | `auth`/`identity`, `media`, `messaging`, `notifications`, `payments`, `dispatch`, `search` | Reusable capabilities. Verticals compose these; they do not re-implement chat, push, geo-matching, or uploads. |
| **Verticals** | `social`, `watch` (catalog UX on `media`), `travel`, `delivery`, `economy`, `partner`, `assistant` | Product surfaces the user opens from Collections / My World. Own their domain data; call platform APIs + publish events. |

**Why this is better than a flat module list:** My World is not “another social feature” — it is the private network shell. Seller chat is commerce, not World Chat. Co-watch Madeleine rooms sit on media + assistant. Dispatch is shared by travel and delivery and must be an explicit module, not an informal “shared engine.”

---

## 3. Enforcing the boundary: Spring Modulith

Use **Spring Modulith** instead of folder-structure convention alone:

- Each domain is a top-level package (`com.gojogo.social`, `com.gojogo.profile`, `com.gojogo.media`, …). A module may expose a public API package; everything else is package-private.
- `ApplicationModules.of(GojogoApplication.class).verify()` fails the build if a module reaches into another module's internals.
- Cross-module communication:
  1. **Synchronous public API** — e.g. `ProfileLookupApi.getUser(id)`.
  2. **Asynchronous domain events** — e.g. `PostCreated`, `OrderPlaced`, `UserFollowed` via `@ApplicationModuleListener`. In-process now; SQS/EventBridge later is config, not a rewrite.
- `@ApplicationModuleTest` boots one module in isolation — extraction stays low-risk.

**Live packages today:** `com.gojogo.auth`, `profile`, `social`, `media`, `messaging`, `notifications`, `economy` (plus app-level `SecurityConfig` / `ApiExceptionHandler`). `notifications` is the first cross-module event consumer (listens to `social`'s `UserFollowed` / `PostLiked` / `PostCommented`). `economy` is the first Phase 2b vertical — publishes `ListingCreated` (no consumer yet; the search index is a later 2b slice).

---

## 4. Data ownership rule

**Schema-per-module in one physical Postgres database:**

- Platform/vertical schemas as modules land: `profile.*`, `social.*`, `media.*`, `messaging.*` (Postgres side where needed), `notifications.*`, `economy.*`, `delivery.*`, `travel.*`, `partner.*`, `dispatch.*` (or Redis-primary with a thin Postgres ledger), `payments.*` (ledger only — Stripe is source of truth for charges).
- **No foreign keys across schemas. No cross-schema JOINs in application code.** Cross-domain reads go through public APIs or events.
- Messaging / live position / Madeleine memory may use **DynamoDB** where write patterns demand it; that does not excuse mixing Postgres ownership across modules.

This is the highest-leverage rule in the document: extraction later is a connection-string change, not a data model rewrite.

---

## 5. Target system diagram (full vision)

```
iOS app (SwiftUI)
   │
   ├── CloudFront ──► S3 (media, HLS video)     [interim: direct S3 until CF verified]
   ├── App Runner / later ALB ──► Spring Boot modular monolith
   ├── API Gateway WebSocket ──► messaging (+ live tracking fan-out)
   ├── Cognito (auth, JWT)
   └── Mapbox (client-side maps/directions for Travel/Partner)  ← not the dispatch authority

Spring Boot — PLATFORM:
   identity/auth · media · messaging · notifications · payments · dispatch · search

Spring Boot — VERTICALS:
   social · watch(catalog) · travel · delivery · economy · partner · assistant

Shared infra:
   Postgres (RDS) · Redis (cache, sessions, GEO dispatch) · OpenSearch
   S3 · MediaConvert · Bedrock (Madeleine)
   EventBridge / SQS · SNS → APNs
```

**Client vs server maps:** Mapbox runs on-device for camera, routing preview, and markers. Server `dispatch` owns matching, ETAs for assigned jobs, and authoritative trip/order state. Do not treat Mapbox as the backend.

---

## 6. Coverage matrix — iOS functions → ownership

### 6a Covered and mapped

| iOS surface / models | Layer | Module | Schema / store | Notes |
|---|---|---|---|---|
| `WelcomeView`, `EmailSignUpView`, `OnboardingFlow` | Platform | `auth` (thin) + `profile` | Cognito + `profile` | Session via `POST /v1/auth/session`; email + Google (Hosted UI) + native Apple (`POST /v1/auth/apple`) — **deployed (2026-07-23); live E2E of Google + Apple still pending** |
| `HomeView`, `Post`, `Story`, `Comment`, `ComposePostView` | Vertical | `social` | `social` | Feed, likes, bookmarks, follows — **live** |
| `ProfileView`, `GGUser`, `ProfileUser`, interests | Platform-ish | `profile` | `profile` | CRUD + by-handle — **live** |
| Presigned upload, post/story media | Platform | `media` | S3 (+ `media` metadata) | CloudFront deferred — **live** (S3 public-read interim) |
| `ShortsView`, `WatchView`, `GojoTVView`, `VideoItem`, `Short`, `TVShow` | Vertical on platform | `media` (+ later `watch` catalog) | `media` | Still SampleData on client; UGC HLS = later |
| `GojoTravelView`, `TravelPlace`, `RideOption`, `TravelDriver` | Vertical | `travel` | `travel` | Uses platform `dispatch` + client Mapbox |
| `GojoDeliveryView`, restaurant/cart/courier | Vertical | `delivery` | `delivery` | Own `AppTab`; uses platform `dispatch` |
| `EconomyView`, `Product` | Vertical | `economy` | `economy` | Marketplace listings |
| `PartnerFlowView`, `PartnerDashboardView`, KYC/stake | Vertical | `partner` | `partner` | Driver/courier onboarding |
| `MadeleineHomeView`, `MadeleineOrb` | Vertical | `assistant` | DynamoDB memory | Bedrock |
| `SearchView` | Platform | `search` | OpenSearch | Event-indexed; not a domain owner |

### 6b Gaps closed by this revision (were weak/missing)

| iOS surface / models | Was | Now |
|---|---|---|
| **My World** — `AppNavMode.myWorld`, `MyWorldView`, circles, contacts | Folded vaguely into “realtime chat” | Platform **`messaging`**: conversations, circles, contacts, typing, polls, send-later, attachments. Private network shell, not public social. |
| `WorldChatView`, `WorldConversation`, `WorldMessage`, reactions | `realtime` only | Same `messaging` module; DynamoDB + WebSocket primary |
| Profile **DMs** (`dmPeer`, `dmThreads`) | Unowned | `messaging` (1:1 threads keyed by profile); distinct product UX, same transport |
| **Seller chat** (`messagingProduct`, `sellerChat`) | Implied under economy | `economy` owns thread metadata / context; **transport** = `messaging` (or economy embeds messaging API). Do not put marketplace threads in World circles. |
| **Co-watch chat** (`WatchingMadeleineView`, `watchingChat`) | Unowned | Ephemeral **media room** + `assistant` participation; not My World history |
| `ActivityView`, `ActivityItem` | Only “SNS later” | Platform **`notifications`** — **live**: in-app activity feed from `UserFollowed`/`PostLiked`/`PostCommented` events; APNs fan-out still later |
| **Profile Home** (`ProfileHomeBlock`, canvas editor) | Lumped under profile vaguely | Owned by **`profile`** (structured blocks JSON / rows in `profile` schema) |
| Watch channel subscribe / dislike / download | Unowned | `media`/`watch` engagement tables; downloads are client-local unless offline sync is productized |
| Partner live jobs / radar | Under partner only | `partner` UX + **`dispatch`** for offers/assignment |

### 6c Chat ownership summary (four surfaces)

| Surface | Product owner | Transport |
|---|---|---|
| My World (circles, group/1:1, polls, send-later) | `messaging` | WebSocket + DynamoDB |
| Profile DMs | `messaging` | Same |
| Seller chat | `economy` | `messaging` API |
| Co-watch / Madeleine while watching | `media` room + `assistant` | WebSocket (ephemeral or short TTL) |

---

## 7. iOS client architecture

The backend modules only matter if the client stays aligned.

### Current shape (Phase 1)

| Piece | Role |
|---|---|
| `AppState` | **Façade** views bind to (`@EnvironmentObject`). Still owns navigation + most `@Published` UI state. |
| `Stores/SocialStore`, `Stores/ProfileStore` | Domain API + DTO→UI mapping; called from `AppState+Backend.swift`. |
| `CoreNetworking/` | `APIClient`, Cognito JSON auth, Keychain, `BackendConfig`, DTOs. |
| `SessionStore` | Local cache / restore for snappy launch. |
| `SampleData` | All verticals not yet wired (Watch, Travel, Delivery, Economy, My World, Madeleine, …). |

A full split of `AppState` into many `@Published` stores was **deferred** (views are tightly coupled). Revisit when the next domain goes live — add a store, keep `AppState` as the façade until a vertical is mostly API-backed.

### Navigation (must stay in sync with backend product splits)

- `AppNavMode`: `.myWorld` (private network) vs `.collections` (public superapp tabs).
- `AppTab`: `.home`, `.watch`, `.madeleine`, `.travel`, `.delivery`, `.economy`, `.search`.
- Auth: `AuthPhase` `.welcome` → `.email` → `.onboarding` → `.app`.
- Travel: `TravelPhase` home → searching → choosingRide → matching → enRoute → inTrip → completed.

### Rules

- Drive UI from `AppState` (or thin stores behind it) — no parallel global navigation stacks.
- Live path: optimistic UI → API; DEBUG log failures; keychain session restore on launch.
- Do not invent a second networking stack; extend `APIClient` / stores per module.

---

## 8. Tech stack

| Layer | Choice | Why |
|---|---|---|
| Backend framework | **Spring Boot 3 + Spring Modulith** | Enforced boundaries; in-process events → SQS later |
| Language | Java 21+ (repo may run newer JDK for builds) | |
| Database | **PostgreSQL** (RDS) | Schema-per-module system of record |
| Cache / geo | **Redis** (ElastiCache) | Sessions, feed cache, rate limits, `GEO*` for dispatch |
| Messaging realtime | DynamoDB + API Gateway WebSocket | Chat, presence, live trip/courier positions |
| Search | OpenSearch | Async index from domain events |
| Media | S3 + CloudFront (CF when account verified) | User media + later HLS |
| Video transcoding | MediaConvert | Shorts / GojoTV ABR |
| AI | Amazon Bedrock | Madeleine |
| Auth | Amazon Cognito | JWT. Email/password + **Google** (Hosted-UI federation) + **native Sign in with Apple** (backend validates Apple's token, mints via a passwordless `CUSTOM_AUTH` flow). One `auth-triggers` Lambda gates the Apple challenge and links Google→email (`AdminLinkProviderForUser`), so all three providers share one email-keyed account. See PROGRESS.md "Social sign-in". |
| Payments | Stripe + Stripe Connect | Ledger in Postgres for reconciliation only |
| Maps (client) | Mapbox | Travel / partner UI; not dispatch authority |
| Events | EventBridge (+ SQS) | Search, notifications, analytics |
| Push | **APNs directly** (HTTP/2 + ES256 `.p8`) | Via `notifications` — chose direct APNs over SNS→APNs for a simpler, self-contained sender (free, one secret). SNS→APNs stays an option if multi-provider (APNs+FCM) fan-out is wanted later. Config-gated on an Apple key. |
| IaC | AWS CDK | |
| CI/CD | GitHub Actions → ECR → App Runner (→ ECS later) | |
| Deploy (early) | **AWS App Runner** | Already in use for Phase 1 |

---

## 9. Phase 1 — done (historical milestones)

Goal achieved: **real accounts, real feed, real media upload**, with Modulith + schema discipline in place.

| Milestone | Outcome |
|---|---|
| 1 — Skeleton + auth | Cognito, App Runner, RDS, `/v1/auth/session` |
| 2 — Profiles + social | Feed, posts, stories, likes, comments, follows + events |
| 3 — Media upload | Presigned S3 PUT; CF blocked on account verification |
| 4 — iOS wiring | `CoreNetworking`, stores, Home/Profile/Compose on live API |
| 5 — Hardening | Pagination, refresh, error bodies, by-handle; `PROGRESS.md` |

Details, curl-verified flows, and incidents: **[PROGRESS.md](PROGRESS.md)**.

---

## 10. Later phases (when budget tops up)

### Phase 2 — Messaging first (preferred next slice)

Deepen **one** product loop: **My World**.

- Platform `messaging`: WebSocket gateway, DynamoDB conversations/messages, typing, reactions, polls, send-later, attachments (reuse `media` presign). **M1 deployed (2026-07-23):** durable writes in the Spring `messaging` module over a DynamoDB single table; API Gateway WebSocket for server→client fan-out (`$connect`/`$disconnect` Lambdas own only the connection registry, keyed by Cognito subject); `Fanout` pushes via `@connections`. See PROGRESS.md "Phase 2 · Milestone 1".
- Wire `MyWorldView` / `WorldChatView` / contacts / circles off SampleData. **M1 built:** live threads coexist with the demo — live send-over-REST/receive-over-socket (text/media/poll/reactions/read/typing), the fake auto-reply suppressed for live threads; phone number or `@handle` → real 1:1.
- **My World identity (WhatsApp model, M1 deployed):** My World is a phone-verified space separate from the app/social account. First entry runs a setup (intro pages → phone OTP → World name/avatar), gated by `GET /v1/world/me`; the World profile (phone-keyed, own name+avatar) lives in the `messaging` module + DynamoDB and decorates conversation/message display. OTP over SNS SMS with a dev-code fallback while SNS is sandboxed.
- Profile DMs on the same module.
- Platform `notifications`: persist `ActivityItem`-shaped rows from `UserFollowed` / `PostLiked`-style events; in-app `ActivityView` first, APNs second. **M2 built (deployed):** `notifications` module consumes `UserFollowed`/`PostLiked`/`PostCommented` (AFTER_COMMIT listeners) → Postgres rows; `GET /v1/notifications`, unread-count, mark-read; `ActivityView` live. **M3 built (deployed, config-gated):** direct-APNs sender + device-token registration over those rows; iOS remote-notification registration. Activates when an Apple `.p8` key is set (see PROGRESS.md APNs checklist) + tested on a device.
- **Messaging polish (M3, live + complete):** reply-to linking, outbound typing, **send-later over the wire** (DynamoDB pending partition + a `@Scheduled` claim-and-deliver poller), **World-name reply snippets**, **backend group creation** (comma-separated recipients → 3+ participants). Live video uploads its poster frame (streamable in-chat playback stays with Phase 3's UGC video pipeline). Also fixed in the audit: profile edits + avatar upload now persist to the backend. Still open by design: streamable chat video (Phase 3), and per-message send-later precision is bounded by the 30s poller.
- **Chat attachments (M4, deployed 2026-07-24):** voice notes (record → `audio/m4a` presign → play in-bubble), system-keyboard stickers, real camera capture, and a real GPS pin. No wire-schema change: audio rides in the media item's file slot, a pin as a `geo:<lat>,<lon>` URI (the `media` module ignores non-S3 URIs). Same milestone hardened the socket — heartbeat ping, escalating backoff, foreground re-dial, and a re-sync of the list + open thread on reconnect, since API Gateway drops idle sockets. See PROGRESS.md "Phase 2 · Milestone 4".
- Optional thin OpenSearch for people/handles only — full commerce search waits. **(not in M1)**

**M1 deferred to M2:** send-later over the wire (currently local-only for live threads), server-side reply-to linking (snippet renders sender-side only), outbound typing on keystroke, group/circle creation UI against the backend, and APNs. Live video-attachment upload is stubbed (photos/carousel upload works).

**Defer in this phase:** Stripe, delivery catalog, economy listings, partner KYC — unless a specific paid milestone says otherwise. Spreading across all of old “Phase 2” burns budget without a shippable loop.

### Phase 2b — Commerce (after messaging is live)

- `economy`: products, sell flow, seller chat via messaging API. **M1 deployed + verified (2026-07-23):** the `economy` vertical module (listings CRUD, browse/keyset pagination, save/unsave, mine/saved) + iOS wiring (`EconomyStore` / `AppState+Economy`, live catalog + sell-with-photo) are live in prod; publishes `ListingCreated`; two-user curl E2E green. Deferred to later 2b slices: seller-chat over the messaging API, and the OpenSearch consumer. See PROGRESS.md "Phase 2b · Milestone 1".
- `delivery`: catalog, cart, order status (no live geo-dispatch yet).
- Stripe + Connect; `payments` ledger.
- OpenSearch consumer for `PostCreated` / `ProductCreated`.
- `partner`: onboarding + KYC document upload.

### Phase 3 — Dispatch + AI + video pipeline

- Explicit platform **`dispatch`** module (Redis geo) used by `delivery` and `travel`.
- `travel` ride-hailing on dispatch; client keeps Mapbox for map UX.
- `assistant`: Madeleine on Bedrock over existing WebSocket; DynamoDB memory; co-watch rooms.
- UGC video: S3 → MediaConvert → HLS → CloudFront.
- Profile Home block persistence under `profile`.

### Phase 4 — Extract what earned it

Likely order: `messaging` (already DynamoDB-heavy) → `dispatch` → `media` transcoding workers. Same event contracts; new deployables only when scaling or failure isolation demands it.

---

## 11. Session-to-session continuity

1. Read **[PROGRESS.md](PROGRESS.md)** first (what’s deployed, stubs, next action).
2. Use this file for **boundaries and sequencing**, not for live URLs or incident history.
3. Update `PROGRESS.md` at the end of every milestone; update this file when module ownership or phase order changes.

---

## 12. Cost notes

- Claude: prefer a capable default model per session; escalate only when stuck. Phase 1 took on the order of several focused sessions; Phase 2 messaging will be similar or larger because of WebSockets.
- AWS at current scale: roughly tens of dollars/month (App Runner + RDS + S3). Pause App Runner when idle. CloudFront waits on account verification (see `PROGRESS.md`).
- Prefer **one deep vertical per top-up** over parallel half-wired commerce surfaces.
