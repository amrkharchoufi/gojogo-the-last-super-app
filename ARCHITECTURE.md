# GojoGo — System Architecture & Build Plan..

Status: **Phase 1 complete** (auth / profile / social / media live); **Phase 2 · Milestones 1–3 deployed** — M1 My World messaging (+ WhatsApp-style setup), M2 platform notifications (activity feed, first consumer of social domain events), M3 APNs push (**activated** — key in Secrets Manager, verified authenticating to Apple; device delivery pending a physical-device test) + messaging polish (reply-linking, typing) — `messaging` module + DynamoDB + WebSocket infra + iOS wiring live in prod (two-user REST + real-time fan-out green), plus a **WhatsApp-style My World setup**: its own phone-verified identity (OTP over SNS + dev-code fallback) and World name/avatar, gated on first entry, separate from the app/social account. See [PROGRESS.md](PROGRESS.md) for deploy URLs, API surface, and known issues.
Stack: Spring Boot (modular monolith, Spring Modulith) · AWS · Postgres · iOS/SwiftUI client
Vision alignment (2026-07-30): Phases 3+ re-planned against the full GoJoGo product vision (five pillars: Social & Content · Transportation · Delivery · Commerce · Services). See §2b for the pillar → module map, §10 for the new phase plan, and §10b for the GoJoAdmin integration contract. Only GoJoGo-side work is planned here; GoJoAdmin is a separate build that consumes the seams §10b defines. **[SPECS.md](SPECS.md)** fills the detailed logic every vision milestone needs (money flows, negotiation + dispatch mechanics, multi-merchant orders, bookings, storefront JSON, trust & safety, config registry) — read it before building any Phase 2e+ milestone.
Budget context: build in small paid milestones. Phase 2 Milestones 1–3 (My World messaging, notifications, APNs push + polish) are deployed; the next spend should finish the remaining Phase 2 loops (live device E2E, social sign-in verification) before spreading into commerce + delivery + Stripe.
**Money is live (2026-07-31, Phase 2e M3):** the `payments` module and the GoJo Wallet are deployed and prod-verified, and a delivery order is now held, settled and split through a double-entry ledger. That unblocked **Phase 3 M2's driver stake and M4's ride tokens**, which now have buckets to live in. Stripe is in **test mode** until someone completes live activation (PROGRESS "Needs YOU"). **Storefronts followed the same day (Phase 2e M4):** a new platform `storefront` module holds the versioned block document a business arranges its own page out of, on both the merchant and business-profile surfaces — the write contract GoJoAdmin's Studio drives. Next in sequence: **Phase 2e M5 (trust & safety baseline)**, which is a launch blocker rather than a feature (App Store UGC guideline 1.2).

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
│  social · watch · travel · delivery · economy · services     │
│  partner · assistant                                         │
└─────────────────────────────────────────────────────────────┘
```

| Layer | Modules | Role |
|---|---|---|
| **Platform** | `auth`/`identity`, `kyc`, `media`, `music`, `messaging`, `notifications`, `payments` (incl. **GoJo Wallet**), `dispatch`, `search` | Reusable capabilities. Verticals compose these; they do not re-implement chat, push, geo-matching, uploads, or money movement. |
| **Verticals** | `social`, `watch` (catalog UX on `media`), `travel`, `delivery`, `economy`, `services` (Phase 5), `partner`, `assistant` | Product surfaces the user opens from Collections / My World. Own their domain data; call platform APIs + publish events. |

**Why this is better than a flat module list:** My World is not “another social feature” — it is the private network shell. Seller chat is commerce, not World Chat. Co-watch Madeleine rooms sit on media + assistant. Dispatch is shared by travel and delivery and must be an explicit module, not an informal “shared engine.”

---

## 2b. Product vision → module map (the five pillars)

The GoJoGo vision is five interconnected pillars plus supporting systems. Nothing in it requires a new architecture — it requires **two structural decisions** and a handful of new/extended modules. Everything else lands inside modules that already exist.

| Vision pillar / system | Lands in | Status | Notes |
|---|---|---|---|
| Identity & accounts (phone/email/Google/Apple, roles, business profiles) | `auth` + `profile` (+ `partner` for role approval) | Live (2e M1 built 2026-07-30) | Business profiles, act-as and derived roles (`GET /v1/me/roles`) shipped in Phase 2e M1. One Cognito account powers everything, incl. GoJoAdmin later. |
| Social & content (videos, photos, posts, carousels, articles, follows, likes, saves, trending) | `social`, `watch`, `media`, `music` | Live | Businesses publish through the **same** modules once business-as-profile lands — no separate business content system. Articles = a post kind, later slice. |
| Transportation (ride-hailing, negotiation, scheduling, safety, vehicle categories) | `travel` + platform `dispatch` | Phase 3 | Fare negotiation is `travel` order state; `dispatch` only matches. Vehicle categories are a `travel` enum, not modules. |
| Driver & courier platform (modes, onboarding, staking, tokens, earnings) | `partner` (application — live) + **`kyc`** (identity — live) + `dispatch` (provisioning) + `payments` wallet (stake, tokens, earnings) | Phase 3 | `partner` already models DRIVER/COURIER kinds and refuses approval until dispatch exists — exactly the seam Phase 3 fills. Personal identity moved out to `kyc` (Sumsub) — see decision 3 below. |
| Delivery (multi-category, multi-merchant, scheduled, for-someone-else) | `delivery` + `dispatch` | Partially live | Catalog/orders/state machine live; simulated fulfilment job is replaced by dispatch (designed for that). Grocery/pharmacy/retail are merchant **categories**, not new modules. |
| Commerce (storefronts, products, variants, digital, ownership-transfer) | `economy` (+ `delivery` for food) | Listings live | Grows from C2C listings to merchant catalogs in Phase 5. Storefront config is authored in GoJoAdmin, rendered in GoJoGo. |
| Services marketplace (providers, catalogs, booking) | **`services`** (new vertical) | Phase 5 | Provisioned through `partner` like every other economic player. |
| Payments & wallet (balances, staking, tokens, tips, refunds, payouts) | **`payments`** (GoJo Wallet ledger) + **`config`** (policy registry) | Live (2e M3, 2026-07-31) | See decision 2 below. |
| Messaging (users ↔ drivers/couriers/businesses/support) | `messaging` | Live | Seller-chat pattern (`ConversationContext`) generalizes to order/ride threads. |
| Safety (contacts, live share, SOS, verified identities/vehicles) | `travel`/`delivery` UX + `partner` verification + `messaging` share | Phase 3 | Community vehicle verification is `partner` + a `travel` completion hook. |
| AI & platform intelligence (recommendations, matching, demand, fraud) | `search`, `dispatch`, `assistant`, feed ranking in verticals | Phase 6 | Feed ranking already live; the rest lands behind existing module APIs. |

**Decision 1 — a business is a profile.** The vision's universal journey ("create a Business Profile, build an audience, then activate commerce") means businesses must be discoverable, followable, content-publishing entities *before* any commerce exists. The cheapest correct model: `profile` gains `kind = PERSON | BUSINESS` plus business fields (category, address, hours, links) and an owning user. The entire social graph, feed, stories, watch, notifications, and search machinery then works for businesses with **zero changes** — a follow is a follow, a post is a post. The owner "acts as" the business on mutations (server-verified ownership, no second token). `partner` keeps owning the *operational* relationship (application, KYC, approval status); an approval flips the business profile's commerce state for its vertical. Do **not** build a parallel `business` module with its own graph — that forks every social feature forever.

**Decision 2 — the wallet is `payments`, and tokens/stakes are ledger rows.** Staking ($30 driver stake), the KYC fee deducted from it, ride-hailing token packs and per-ride deductions, verification rewards paid from a stake, tips, earnings, and refunds are all **internal balance transitions** — one double-entry ledger in the `payments` schema with buckets per user: `available`, `staking` (locked), `tokens`, `rewards`. Stripe (+ Connect) is the only thing that moves external money, and remains source of truth for charges; the ledger reconciles. "Token" is a ledger credit with a policy price — not a crypto asset, no chain, no speculation surface. A public `WalletApi` (credit/debit/hold/release with idempotency keys) is what `travel`, `delivery`, `economy`, `services`, and `partner` call; none of them ever touch Stripe directly.

**Decision 3 — identity is a vendor's answer, and the platform keeps only the verdict.** Proving a human is who they claim needs document-authenticity checks and a liveness match; a reviewer squinting at a phone photo of an ID card is not that, and the copies of everyone's passport it accumulates are a liability with no upside. So a platform **`kyc`** module owns the relationship with an IDV vendor (Sumsub) behind the `IdentityVerificationApi` SPECS §4 reserved, and the `kyc` schema stores a *decision* — status, reason, reject labels, the vendor's applicant id — and never the evidence. `partner` keeps the question a vendor cannot answer (should this **business** trade here), which stays a human approval. The interface is what makes the vendor swappable, and it is load-bearing in a second way: **unconfigured means the old path**, so an environment with no credentials still verifies by document upload and human review rather than being unable to onboard anyone. Every later pillar that needs a verified person — driver staking and payouts (Phase 3), sellers and providers (Phase 5) — reads the same API rather than growing its own check.

---

## 3. Enforcing the boundary: Spring Modulith

Use **Spring Modulith** instead of folder-structure convention alone:

- Each domain is a top-level package (`com.gojogo.social`, `com.gojogo.profile`, `com.gojogo.media`, …). A module may expose a public API package; everything else is package-private.
- `ApplicationModules.of(GojogoApplication.class).verify()` fails the build if a module reaches into another module's internals.
- Cross-module communication:
  1. **Synchronous public API** — e.g. `ProfileLookupApi.getUser(id)`.
  2. **Asynchronous domain events** — e.g. `PostCreated`, `OrderPlaced`, `UserFollowed` via `@ApplicationModuleListener`. In-process now; SQS/EventBridge later is config, not a rewrite.
- `@ApplicationModuleTest` boots one module in isolation — extraction stays low-risk.

**Live packages today:** `com.gojogo.auth`, `profile` (incl. business profiles + act-as resolution), `social`, `media`, `music`, `messaging`, `notifications`, `economy`, `delivery`, `watch`, `partner`, `kyc`, `payments`, `config` (plus app-level `SecurityConfig` / `ApiExceptionHandler`). `notifications` is the busiest cross-module event consumer (`social`'s `UserFollowed` / `PostLiked` / `PostCommented` / `StoryReacted` / `StoryReplied`, `messaging`'s `MessageSent` for chat push, and `partner`'s `PartnerReviewed` for an approval or rejection). `economy` publishes `ListingCreated` (still no consumer — search is a later slice), `delivery` publishes `OrderPlaced` (likewise) and `OrderStatusChanged` (**consumed since 2e M3**), and `payments` publishes `MoneyReceived` / `PayoutSent`, both consumed by `notifications`.

**Public cross-module APIs in use:** `ProfileApi` (now also `requireActingProfile` — the one server-side ownership check behind acting as a business — plus `businessesOwnedBy` / `findBusiness` / `setBusinessVerified`), `MediaApi` + `MediaDocumentApi`, `MusicApi`, `MessagingApi` (+ `ConversationContext`), `SocialGraphApi`, `MerchantProvisioningApi`, `IdentityVerificationApi` (the IDV seam — see §2b), and `WalletApi` / `FeeApi` / `PayoutApi` (the money seam: a vertical asks for a movement in minor units and never learns that Stripe exists) plus `ConfigApi` (effective-dated policy values, read with a compiled-in default so an empty table behaves like a populated one). Each is deliberately narrow — a consumer gets the one verb it needs, never the module's model. Where a vertical needs to *change* something another module owns (following, a chat, a catalog entry), it either sends the user to that module's own surface or asks for exactly one operation and gets an id back.

---

## 4. Data ownership rule

**Schema-per-module in one physical Postgres database:**

- Platform/vertical schemas as modules land: `profile.*`, `social.*`, `media.*`, `messaging.*` (Postgres side where needed), `notifications.*`, `economy.*`, `delivery.*`, `travel.*`, `partner.*`, `dispatch.*` (or Redis-primary with a thin Postgres ledger), `services.*`, `payments.*` (the GoJo Wallet double-entry ledger — live; Stripe is source of truth for external charges and is reconciled against it), `platform.*` (the config registry — live), `kyc.*` (identity **verdicts** only — the documents live with the IDV vendor, deliberately not here).
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
   social · watch(catalog) · travel · delivery · economy · services · partner · assistant

GoJoAdmin (separate web app, later) ──► the SAME Spring Boot REST APIs
   (owner-JWT for merchant self-service; platform-admin role for review/ops — see §10b)

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
| `HomeView`, `Post`, `Story`, `Comment`, `ComposePostView` | Vertical | `social` | `social` | Feed, likes, bookmarks, follows — **live**. Stories are the full Instagram surface since Phase 2c (photo/video/text frames, overlays, replies, reactions, viewers, mute, archive, highlights, close friends) |
| `ProfileView`, `GGUser`, `ProfileUser`, interests | Platform-ish | `profile` | `profile` | CRUD + by-handle — **live** |
| Presigned upload, post/story media | Platform | `media` | S3 (+ `media` metadata) | CloudFront deferred — **live** (S3 public-read interim). Two public APIs: `MediaApi` for that public product, and `MediaDocumentApi` (2b M6) for KYC papers, which presign into a **private** prefix and are read only through a short-lived signed GET |
| `ShortsView`, `WatchView`, `VideoItem`, `Short` | Vertical on platform | **`watch`** | `watch` | **Live** — long-form + shorts catalog, authored title/description/thumbnail, likes, saves, distinct-viewer view counts, comments, owner-only edit/delete. Reads `SocialGraphApi` so **subscribers = followers**. Playback is still the direct-S3 object; UGC HLS transcode = Phase 6 |
| `GojoTVView`, `TVShow` | Vertical on platform | `media` (+ later `watch` catalog) | `media` | Still SampleData on client |
| `GojoTravelView`, `TravelPlace`, `RideOption`, `TravelDriver` | Vertical | `travel` | `travel` | Uses platform `dispatch` + client Mapbox |
| `GojoDeliveryView`, restaurant/cart/courier | Vertical | `delivery` | `delivery` | Own `AppTab`; **live** (M4) — catalog, server-priced orders, fulfilment state machine. Restaurants enter the catalog only through a `partner` approval (2b M6); merchants manage their own storefront + menu. Will use platform `dispatch` for real couriers (Phase 4 M1) |
| `EconomyView`, `Product` | Vertical | `economy` | `economy` | Marketplace listings — **live**; `SellerListingsView` is the seller side (edit, pause, mark sold, delete, saves/views) |
| `MerchantDashboardView` (+ `MerchantPartnerView` shell) | Vertical | `partner` (+ owner-scoped `delivery`) | `partner` | **Live (2b M6, deploy confirmed 2026-07-30).** Onboarding (apply → private KYC upload → human review → provision) happens in **Gojo Admin**; the app keeps only the owner's dashboard — storefront, open/closed, menu editor — behind a chip shown to a restaurant's owner alone |
| `PartnerFlowView`, `PartnerDashboardView`, KYC/stake | Vertical | `partner` | `partner` | Driver/courier onboarding — the same application with `kind=DRIVER/COURIER`; still local-only in the app, and an approval is refused until Phase 3 `dispatch` gives it somewhere to land |
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
| Watch channel subscribe / dislike / download | Unowned | **Subscribe is follow** — one graph, in `social`, read by `watch` through `SocialGraphApi`; there is deliberately no second subscription table. Likes/saves/views/comments are `watch` engagement tables. Dislike + download stay client-local (a dislike is a personal ranking signal with no feed to feed yet; downloads are device-local unless offline sync is productized) |
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
- **Messaging polish (M3, live + complete):** reply-to linking, outbound typing, **send-later over the wire** (DynamoDB pending partition + a `@Scheduled` claim-and-deliver poller), **World-name reply snippets**, **backend group creation** (comma-separated recipients → 3+ participants). Live video uploads its poster frame (streamable in-chat playback stays with Phase 6's UGC video pipeline). Also fixed in the audit: profile edits + avatar upload now persist to the backend. Still open by design: streamable chat video (Phase 6), and per-message send-later precision is bounded by the 30s poller.
- **Chat attachments (M4, deployed 2026-07-24):** voice notes (record → `audio/m4a` presign → play in-bubble), system-keyboard stickers, real camera capture, and a real GPS pin. No wire-schema change: audio rides in the media item's file slot, a pin as a `geo:<lat>,<lon>` URI (the `media` module ignores non-S3 URIs). Same milestone hardened the socket — heartbeat ping, escalating backoff, foreground re-dial, and a re-sync of the list + open thread on reconnect, since API Gateway drops idle sockets. See PROGRESS.md "Phase 2 · Milestone 4".
- **Chat push + read receipts (M5, deployed 2026-07-24):** the `messaging` module publishes a public `MessageSent` event on every delivered message; `notifications` consumes it and fires an APNs alert to recipients the live socket missed (the first *chat-message* push — M3 pushed only the activity feed). `notifications`'s second event source, and the second cross-module event contract after `social`. Also persisted read receipts: `GET …/messages` returns `peerReadMessageId` (server high-water mark) so a "Read" survives reloads/offline gaps. See PROGRESS.md "Phase 2 · Milestone 5".
- Optional thin OpenSearch for people/handles only — full commerce search waits. **(not in M1)**

**M1 deferred to M2:** send-later over the wire (currently local-only for live threads), server-side reply-to linking (snippet renders sender-side only), outbound typing on keystroke, group/circle creation UI against the backend, and APNs. Live video-attachment upload is stubbed (photos/carousel upload works).

**Defer in this phase:** Stripe, delivery catalog, economy listings, partner KYC — unless a specific paid milestone says otherwise. Spreading across all of old “Phase 2” burns budget without a shippable loop.

### Phase 2b — Commerce (after messaging is live)

- `economy`: products, sell flow, seller chat via messaging API. **M3 deployed + verified (2026-07-24):** a listing conversation now carries a **reference card** back to the listing — `messaging` gained a generic public `ConversationContext` (kind/refId + a pre-rendered title/subtitle/imageUrl, vertical-agnostic so no messaging→economy dependency), stamped by `economy` in `openChat` and refreshed on thread reuse; surfaced on `ConversationDto`, rendered as a tappable card in the iOS thread. The `kind`/`refId` pointer is the seam a future checkout/order attaches to. **M2 deployed + verified (2026-07-24):** seller chat is live — `messaging` gained a public `MessagingApi` (one method: open the 1:1 between two people), `POST /v1/economy/listings/{id}/chat` returns the thread plus a prefilled opener and posts nothing itself, and iOS "Message seller" opens the real My World thread. First cross-vertical use of a platform module's public API; the boundary is enforced by `ModularityTests`. **M1 deployed + verified (2026-07-23):** the `economy` vertical module (listings CRUD, browse/keyset pagination, save/unsave, mine/saved) + iOS wiring (`EconomyStore` / `AppState+Economy`, live catalog + sell-with-photo) are live in prod; publishes `ListingCreated`; two-user curl E2E green. Deferred to later 2b slices: seller-chat over the messaging API, and the OpenSearch consumer. See PROGRESS.md "Phase 2b · Milestone 1".
- `delivery`: catalog, cart, order status (no live geo-dispatch yet). **M4 deployed + verified (2026-07-25):** the `delivery` vertical is live — seeded restaurant/menu catalog, **server-priced** orders (the client sends item ids + quantities; prices, fees and totals are read from the database and copied onto the order lines), one live order per user, order history, cancel-until-the-courier-moves, and a 1–5 rating. Cart stays client-side by design (the order is the transaction). Fulfilment is **simulated on a server-side timeline** — `OrderFulfilmentJob` walks each open order to where its `placedAt` says it should be and publishes `OrderStatusChanged` on every step — because platform `dispatch` doesn't exist until Phase 3; the state machine, events and API are the real thing, so dispatch replaces only that job. Being server-authoritative is what lets the tracking screen survive a relaunch and agree across devices. iOS `DeliveryStore` / `AppState+Delivery` replaced an empty SampleData catalog; verified by two-user curl E2E **and** a simulator pass on the live backend. **Follow-up the same day:** the seeded demo catalog was deleted (so the vertical now waits on `partner` merchant onboarding for real restaurants), and **saved delivery addresses** landed — a `delivery.address` table with one default per user enforced by a partial unique index, copied onto the order at order time so an edited address never rewrites an old receipt, with an iOS address sheet on the app's tinted-glass surfaces. See PROGRESS.md "Phase 2b · Milestone 4".
- Stripe + Connect; `payments` ledger. Now has three call sites waiting on it: a marketplace sale (M3's `ConversationContext`), a delivery order (M4, placed with no payment step), and the merchant an M6 approval creates, who is the payee.

### Phase 2c — Stories, properly

- `social` stories go from a stub (one image URL, 24h, seen flag) to the whole product: photo / video / text-card frames with a client-authored overlay spec, replies, reactions, a viewers list, mute, archive, highlights, and a close-friends audience. Four migrations (`V11`–`V14`), no new module and no new AWS infra — it reuses `media` presign and publishes two new events (`StoryReacted`, `StoryReplied`) that `notifications` consumes.
- **Music is a platform module, not a story feature.** `music` owns the shared track catalog (`music` schema) and exposes `MusicApi`; `social` resolves a track through it and then stores its **own snapshot** on the frame — no FK across schemas, and a story keeps playing the sound it shipped with after a track is pulled. Shorts and posts are the obvious next consumers. The catalog ships empty and has no ingest endpoint by design (there is no admin role); seeding it is a licensing decision — see PROGRESS.md "Seeding the music catalog".
- **Story replies stay in `social`, not `messaging`.** This is the one boundary call worth writing down: My World is a separate, phone-verified identity that will get its **own** stories, so routing a reply to a *social* story into a My World DM would cross two identities the app deliberately keeps apart. Seller chat goes through `MessagingApi` because a marketplace conversation genuinely is a conversation; a story reply is a private comment on a piece of content, and it belongs to the module that owns the content. See PROGRESS.md "Phase 2c".
- OpenSearch consumer for `PostCreated` / `ProductCreated`.
- `partner`: onboarding + KYC document upload. **Built + verified 2026-07-27 (not yet deployed), shipped as Phase 2b M6** — pulled forward out of 2c because it was the blocker for `delivery` being usable at all: the demo catalog was deleted, and the only way a restaurant could exist was a Flyway migration. The module owns the *business relationship* (an application, its KYC documents, and a status a human moves), and is generic by design — `kind` is `RESTAURANT | DRIVER | COURIER`, since a driver's application is the same object with somewhere else to land. On approval it **provisions into a vertical** through that vertical's public API: today only `delivery.MerchantProvisioningApi`, which returns the merchant id; `DRIVER`/`COURIER` are refused at approval time until Phase 3 `dispatch` exists, rather than approved into nothing. The dependency is one-way (`partner → delivery`) and the only trace left in delivery is an `owner_id` on the merchant row — which is the entire basis for its owner-scoped `/v1/delivery/merchants/mine` catalog surface, so delivery never learns that KYC exists. **Two boundary calls worth recording:** approval is a *human* act on a token-guarded surface outside the JWT chain (this app has no admin role — the same constraint that left the music catalog without an ingest endpoint), and **KYC documents are not `media`'s public product**. Everything `/v1/media/presign` mints lands under a world-readable prefix, so `media` gained a second public API, `MediaDocumentApi`, that presigns into a private prefix and hands a reviewer a short-lived signed GET; consumers store object keys, never URLs. **Restaurants are created in Gojo Admin, not in the app** (decided 2026-07-27). The applicant-facing iOS flow was removed; the module and its endpoints are unchanged, and the operator drives the same application → KYC → review → provision path from the admin tool. iOS keeps only the **merchant dashboard** — an owner running their own storefront and menu — gated by `AppState.merchantDashboardEnabled` pending a call on whether that moves to admin too. The one thing this implies and doesn't yet have: an **admin-side create**, since the applicant endpoints are caller-scoped. See PROGRESS.md "Phase 2b · Milestone 6".

### Phase 2e — Commerce spine: business identity, admin seam, wallet (GoJoAdmin-ready)

Goal: everything GoJoAdmin needs on its day one already exists as an API, and money can move. This is the highest-leverage phase in the vision plan — every later pillar (transport staking, delivery payment, commerce checkout, services booking) blocks on the wallet, and every economic player's journey starts with a business profile.

- **M1 — Business profiles (vision "Phase 1" for every economic player). Built 2026-07-30** — `V20`, act-as on every create endpoint, `partner.business_profile_id` gating the verified badge, `GET /v1/me/roles`, and the iOS switcher. Deviations worth recording: act-as also covers likes/follows server-side (the app uses creation only, since reads are decorated for the caller), and `maxBusinessesPerOwner` is a constant until the config registry lands in M3. See PROGRESS.md "Phase 2e · Milestone 1". `profile.kind = PERSON | BUSINESS` + business fields (category, description, address, opening hours, contact, links) + `owner_profile_id`; one migration. Followable/discoverable/content-publishing immediately, because a business *is* a profile (§2b decision 1). Owner acts-as the business on content mutations: an optional `actAsProfileId` on the existing create endpoints, server-verified against ownership — no second token, no client-side trust. iOS: "Create business profile" from own profile, a switcher chip, business badge on profile/feed surfaces. `partner` applications gain a `business_profile_id` link so an approval knows which public identity it commerce-enables.
- **M2 — Real admin principal + the missing admin-side create. Built + deployed 2026-07-30** — `platform-admin` Cognito group read from `cognito:groups`, `POST /v1/partner/admin/applications` (owner by id or handle, reusing the merchant's own write path), admin submit + document verbs + a per-document signed link, `isPlatformAdmin` on `/v1/me/roles`, and a `WEB_ALLOWED_ORIGINS` CORS allowlist. Original plan text follows. GoJoAdmin (and the human reviewer today) needs a real operator identity: a Cognito group (`platform-admin`) surfaced as a role in the JWT, honored by the existing `/v1/partner/admin/**` surface; `PARTNER_ADMIN_TOKEN` stays as break-glass. Add the **admin-side create** PROGRESS flags as missing (applicant endpoints are caller-scoped): `POST /v1/partner/admin/applications` on behalf of a business, plus list/filter and a document-view proxy over `MediaDocumentApi`'s signed GETs. This is the exact surface GoJoAdmin's review console will call.
- **M3 — Payments + GoJo Wallet. Built + deployed 2026-07-31** — `V22`–`V25`, the `payments` and `config` modules, delivery checkout, and the `OrderStatusChanged` consumer. Deviations worth recording: **card money always arrives as a wallet top-up** (a hosted Checkout session) rather than as a per-order card charge, so a vertical only ever has one payment path to integrate and no card data exists in this system; **the courier's delivery fee and tip settle to `PLATFORM` under their own ledger kinds** until Phase 4 M1 creates couriers, rather than being folded into commission; **a promotion is always funded by the merchant**, free-delivery included, which is what keeps a discount from ever reducing what the courier is paid; and **merchant balances and payouts live on `delivery`'s `/mine` surface**, not on payments' own — only the vertical that owns a payee can prove the caller owns it, and the reverse dependency would be a cycle. Refunds of a *settled* order are deliberately not built: cancelling before delivery releases the hold, and a post-delivery refund is SPECS §5's dispute flow (Phase 4). Original plan text follows. New platform `payments` module (`payments` schema): Stripe + Connect for external money; internal double-entry ledger with per-user buckets (`available` / `staking` locked / `tokens` / `rewards` / `escrow`) per §2b decision 2 and the capture/settlement table in SPECS §1. Public **`WalletApi`** (credit / debit / hold / release / capture / transfer, idempotency-keyed). First consumer: **delivery checkout** (orders are currently placed with no payment step) + tips + **promotions as order lines** (SPECS §6) + the `OrderStatusChanged` push consumer (SPECS §12); `economy`'s `ConversationContext` seam and the merchant payee from 2b M6 are the next two call sites already waiting. Refunds + transaction history round out the vision's wallet list. Fee/token/policy knobs live in the config registry (SPECS §14), created in this milestone.
- **M4 — Storefront config (the Studio contract). Built + deployed 2026-07-31** — `V26`, a new platform `storefront` module, both surfaces wired, and a read-only renderer in GojoDelivery. Deviations worth recording: the document lives in **its own module with one table keyed by (surface, owner)**, not on `delivery.merchant`, because `economy` and `services` get storefronts on the same contract and three verticals' worth of ad-hoc JSON is three renderers that disagree; the block set is **closed per surface** (`BUSINESS_HOME` takes no catalog blocks) rather than globally; validation is **split** — the platform module owns shape and the vertical owns reference ownership, passed in as a `StorefrontReferenceCheck` parameter so no save can skip it; POST/VIDEO refs are deliberately **unvalidated** (delivery has no `social`/`watch` dependency, and imported content renders through reads that enforce their own visibility); and the profile-home public read is embedded in **`social`'s** profile view, since that is where a profile is rendered from, while the write stays owner-scoped in `profile`. iOS skips `media_row` for now — the one block the server accepts and the app doesn't draw. See PROGRESS.md "Phase 2e · Milestone 4". Original plan text follows. A storefront is a versioned JSON block document from a closed block set (spec: SPECS §9) owned by the vertical that owns the catalog — `delivery.merchant` first — written through owner-scoped `/v1/delivery/merchants/mine/storefront`, rendered read-only in GojoDelivery. This is the write API GoJoAdmin's homepage builder drives later; iOS never edits it. Do Profile-Home block persistence (`profile`) in the same slice — same pattern, same JSON-blocks discipline.
- **M5 — Trust & safety baseline (gap the vision implies but never names; App Store UGC guideline 1.2 makes it a launch blocker).** Blocking in `social` (graph + content + messaging refusal via extended `SocialGraphApi`), a small platform **`moderation`** module (report any target kind, human-reviewed queue on the admin surface), and **account deletion** (Cognito disable → 30-day grace → anonymize). Share-token service (public live-trip/order tracking links for non-users) rides here too since SOS depends on it. Full spec: SPECS §10–§11.

### Phase 3 — Dispatch + Transportation (ride-hailing)

The full rider/driver vision, sequenced so each milestone is a shippable loop. Client keeps Mapbox for map UX; server `dispatch` is the authority (§5). Detailed mechanics — pricing, negotiation state machine, matching waves, staking/token/verification logic: SPECS §2–§4.

- **M1 — Platform `dispatch` module.** Redis GEO presence (driver/courier positions over the existing WebSocket infra), candidate search (proximity, availability, vehicle category), offer/assignment state, and per-kind provisioning registries. Public `DispatchApi` + `DriverProvisioningApi`/`CourierProvisioningApi` — the landing place `partner` approvals have been 409ing toward since 2b M6.
- **M2 — Driver onboarding completes.** The vision's full pipeline on existing seams: `partner` DRIVER application (live) + **vehicle registration** (category/make/model/year/color/plate + registration/insurance docs via `MediaDocumentApi`, photos via `media`; multiple vehicles, each verified separately) + **$30 stake** as a `WalletApi` hold into the `staking` bucket + **KYC fee** deducted from the stake + approval provisions into `dispatch`. Driver Mode dashboard in iOS: availability toggle, offers, earnings, performance, wallet.
- **M3 — The ride loop.** `travel` vertical live: request (pickup/destination/category) → dispatch candidates → driver accept / decline / **counteroffer** (fare negotiation is `travel` order state; suggested fare + custom offer + counter rounds) → confirm → live trip (driver position fan-out reuses messaging's WebSocket pattern) → complete → pay via `WalletApi` → mutual rating. Rider↔driver contact = a `messaging` thread with a `ConversationContext(kind=RIDE)`. Scheduled rides and book-for-someone-else reuse the send-later poller pattern and delivery's recipient fields.
- **M4 — Ride-hailing tokens.** Token packs purchased into the wallet's `tokens` bucket (Stripe → ledger credit); accepting an eligible ride debits tokens per a centrally-managed policy (no commission); balance/usage/history surfaces + low-balance push through `notifications`. Policy lives server-side so pricing changes are config, not client releases.
- **M5 — Community vehicle verification + safety pack.** `travel` publishes `TripCompleted`; `partner` invites the first passenger(s) to confirm driver/vehicle/plate match + roadworthiness, with optional photos (private prefix). Success → Verified Vehicle badge + passenger reward paid **from the driver's staking balance** (a `WalletApi` transfer); inconsistency → `SUSPENDED` + manual review through the admin surface. Safety pack: emergency contacts, live-trip share (a share link carried over `messaging`), SOS surface, verified-driver/vehicle badges everywhere a trip is shown.

### Phase 4 — Delivery at full vision

Detailed mechanics — sub-orders, handoff codes, scheduling, disputes: SPECS §5.

- **M1 — Real couriers.** `partner` COURIER approvals provision into `dispatch`; the simulated `OrderFulfilmentJob` is deleted and dispatch assignment drives the same state machine and `OrderStatusChanged` events — the swap 2b M4 was explicitly designed for. Courier *pay* is already separated out: 2e M3 settles the delivery fee and the tip to `PLATFORM` under the `COURIER_FEE` / `TIP` ledger kinds, so this milestone changes a payee and nothing else. Courier Mode: availability, offers, live navigation, earnings via wallet.
- **M2 — Handoff integrity + money.** Pickup verification (QR/order code at the merchant), delivery confirmation (PIN / photo / contactless), tips through the wallet, courier earnings + withdrawal. Courier↔customer contact = `messaging` thread with `ConversationContext(kind=ORDER)`.
- **M3 — Multi-merchant orders.** One checkout, one payment, sub-orders per merchant (each with its own preparation/fulfilment state), dispatch coordinating pickups/couriers, per-sub-order tracking. The unified-cart UX rides on the existing server-priced order model — sub-orders are the only schema change.
- **M4 — Breadth.** Scheduled orders + modify/cancel before preparation, order-for-someone-else (recipient fields + recipient-facing tracking), and category expansion — grocery, pharmacy, retail, flowers, package delivery, errands are merchant **categories + order kinds** on the same model, not new modules.

### Phase 5 — Commerce & Services marketplace

Detailed mechanics — product/inventory model, promotions, reviews, digital + ownership-transfer flows, booking rules, search contract: SPECS §6–§7, §13.

- **M1 — Merchant products in `economy`.** Alongside C2C listings: catalog products with variants/sizes/colors, inventory, pricing/discounts, shipping fields, media galleries — created by `partner`-provisioned sellers (`economy.SellerProvisioningApi`, the `MerchantProvisioningApi` pattern), bought through cart + wallet/Stripe checkout. Reviews on products; favorites already exist as saves.
- **M2 — Special catalogs.** Digital products (files/licenses/subscriptions; delivery = signed URL, no courier) and ownership-transfer listings (VIN/serial, documentation via `MediaDocumentApi`, a transfer-workflow state machine, buyer verification) — both are `economy` product kinds with extra tables, not new modules.
- **M3 — `services` vertical.** Provider profiles (qualifications, portfolio, service areas, languages), service catalog (duration, pricing, location kind), availability + booking calendar, book → pay (wallet) → complete → review. Provisioned via `partner` (`kind=SERVICE_PROVIDER` → `services.ProviderProvisioningApi`). Contact = `messaging` with `ConversationContext(kind=BOOKING)`.
- **M4 — Search & discovery, finally.** The OpenSearch consumers for events that have been publishing into the void (`PostCreated`, `ListingCreated`, product/merchant/video events): unified search across businesses, products, menus, services, content; category/location/rating facets. Recommendation surfaces (trending, personalized rails) read from it.

### Phase 6 — AI, video pipeline, platform intelligence

- `assistant`: Madeleine on Bedrock over the existing WebSocket; DynamoDB memory; co-watch rooms.
- UGC video: S3 → MediaConvert → HLS → CloudFront (unblocks streamable chat video + real Watch playback).
- Intelligence: recommendation ranking beyond the feed (merchants, products, services), demand prediction + driver-workload balancing inside `dispatch`, fraud heuristics on wallet/ledger events, support tooling. All behind existing module APIs — no new module until one earns it.

### Phase 7 — Extract what earned it

Likely order: `messaging` (already DynamoDB-heavy) → `dispatch` → `media` transcoding workers. Same event contracts; new deployables only when scaling or failure isolation demands it.

---

## 10b. GoJoAdmin integration contract (GoJoGo-side seams, build-ready)

GoJoAdmin (Dashboard · Studio · Economy · GoJoAds) is a separate web app, **not** part of this codebase. GoJoGo's obligation is to make sure that when it's built, it plugs into existing APIs with zero backend rework. The governing rule: **GoJoAdmin gets no private tables and no parallel data path** — everything it does goes through the same public REST surface, so the monolith stays the single system of record and the iOS app could in principle do anything admin can.

| Seam | GoJoGo-side contract | Status |
|---|---|---|
| **Identity** | Same Cognito pool. A business owner signs into GoJoAdmin with their GoJoGo account (vision: "signs in to GoJoAdmin using the same account"); GoJoAdmin discovers their businesses via the `owner_profile_id` link and `GET /v1/me/roles`. Platform operators carry the `platform-admin` Cognito group, honored by `/v1/partner/admin/**`. | **Live** (2e M1–M2) |
| **Onboarding / review** | `partner` is the backbone for *every* economic player (`RESTAURANT` live; `DRIVER`/`COURIER` Phase 3; `SELLER`/`SERVICE_PROVIDER` Phase 5). Admin surface = `/v1/partner/admin/**`, including create-on-behalf, submit and the document verbs; KYC docs stay on `MediaDocumentApi`'s private-prefix presign + short-lived signed GET. Restaurant creation already belongs to admin (decided 2026-07-27). | **Live** |
| **Provisioning** | Approval → per-vertical public API, returning an id: `delivery.MerchantProvisioningApi` (live), then `DriverProvisioningApi`/`CourierProvisioningApi` (Phase 3), `economy.SellerProvisioningApi` + `services.ProviderProvisioningApi` (Phase 5). One pattern, one direction (`partner → vertical`). | Pattern live |
| **Merchant self-service (Economy module)** | The owner-scoped `/mine` surfaces are the data plane GoJoAdmin calls with the owner's own JWT — `/v1/delivery/merchants/mine` (storefront, hours, menu CRUD — live) and its future economy/services siblings. No admin-only mirror of these endpoints. | Live (delivery) |
| **Studio (content)** | GoJoAdmin publishes through the same `social`/`watch`/`media` APIs, acting-as the business profile (2e M1). Homepage builder writes the storefront JSON-blocks document (2e M4). Content analytics = read endpoints over engagement counts that already exist (views, likes, comments, saves). | 2e M1/M4 |
| **Dashboard (analytics)** | Domain events are the feed: `OrderPlaced`/`OrderStatusChanged`, `ListingCreated`, `PostLiked`… already publish; aggregate read endpoints (sales, orders, followers, engagement) are added per vertical as GoJoAdmin needs them, scoped to the owner JWT. EventBridge export when out-of-process consumers appear (Phase 7 posture). | Events live |
| **Money** | Payouts/settlement via Stripe Connect; balances/earnings via `WalletApi`-backed read endpoints on the **vertical's own `/mine` surface** (`/v1/delivery/merchants/mine/wallet`, `…/payouts`), because only the module that owns a payee can prove the caller owns it. | **Live** (2e M3) |
| **GoJoAds** | Deferred entirely — no seam reserved beyond content/engagement events. Don't pre-build. | — |

**CORS/web note:** the backend currently serves only the iOS app; GoJoAdmin is a browser client, so its origin needs a CORS allowance when it exists — config, not architecture. **Built in 2e M2:** `WEB_ALLOWED_ORIGINS` (empty = no CORS headers, today's behaviour); pass `-c webAllowedOrigins=…` on the Fargate deploy when the console has a domain.

---

## 11. Session-to-session continuity

1. Read **[PROGRESS.md](PROGRESS.md)** first (what’s deployed, stubs, next action).
2. Use this file for **boundaries and sequencing**, not for live URLs or incident history.
3. Use **[SPECS.md](SPECS.md)** for the detailed logic of any Phase 2e+ milestone (money flows, state machines, config knobs) — it holds the decisions so a build session doesn't re-litigate them.
4. Update `PROGRESS.md` at the end of every milestone; update this file when module ownership or phase order changes; update `SPECS.md` when a build contradicts or refines a spec.

---

## 12. Cost notes

- Claude: prefer a capable default model per session; escalate only when stuck. Phase 1 took on the order of several focused sessions; Phase 2 messaging will be similar or larger because of WebSockets.
- AWS at current scale: roughly tens of dollars/month (App Runner + RDS + S3). Pause App Runner when idle. CloudFront waits on account verification (see `PROGRESS.md`).
- Prefer **one deep vertical per top-up** over parallel half-wired commerce surfaces.
