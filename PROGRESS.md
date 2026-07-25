# GojoGo — Build Progress

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full architecture and milestone plan. This file tracks what's actually done.

## ⚠️ Needs YOU (things Claude can't do — external accounts, devices, money, policy)

These are the only open items that require you personally; everything else in Phase 1–2 is built + deployed + verified.

1. **APNs device test** — enable the **Push Notifications** capability on App ID `com.gojo.gojogo` (Apple Developer portal), then run the app on a **physical iPhone** to confirm a real push arrives. (Backend + key are done and verified against Apple.) Note: `APNS_PRODUCTION` is currently `true` in [app-stack.ts](infra/lib/app-stack.ts) — that's for TestFlight/App Store builds; a plain Xcode dev build mints a **sandbox** token, so use `false` for dev-device testing (redeploy `GojoGoAppStack`).
2. **CloudFront** — the AWS account is unverified for CloudFront; only AWS Support can lift it. Until then media is public-read from S3. (Flip `ENABLE_CLOUDFRONT` in media-stack when verified.)
3. **Real SMS OTP** — SNS SMS is in the account sandbox (only verified numbers). Get SNS SMS production access (AWS Support) + a sender id, or swap to Twilio/Vonage Verify. Then **clear `WORLD_OTP_DEV_CODE`** (currently `424242`) before launch.
4. ~~**CI deploy**~~ — **working as of 2026-07-25.** A push to `main` touching `backend/**` auto-deployed end to end (tests → image → task definition revision → rollout → health check), so the repo secrets are in place and the workflow is no longer untested.
5. **Cost/scaling decisions** — RDS is publicly reachable (a NAT Gateway ~$32/mo removes that); App Runner bills ~24/7 (`aws apprunner pause-service` when idle). Your call.
6. **Git** — nothing has been committed this session; commit when you're happy.
7. ~~**IAM for the new deploy path**~~ — **applied 2026-07-25.** `iam:PassRole` for `ecs-tasks.amazonaws.com` is granted, so `scripts/deploy-backend.sh` (and CI) can register a task definition again. Not yet re-exercised end to end: the first deploy after this will be the proof.

Rare/edge (decide if you care): account-linking is one-directional (Google-first → later email self-signup on the same address fails) and orphaned media uploads are never cleaned up — **both deployed 2026-07-23, pending behavioral E2E** (see Known issues): a clearer `PreSignUp_SignUp` error, and a report-only orphan sweep with reference tracking.

## Environment — ready

- **AWS account:** `578109959809`, region `us-east-1`
- **IAM user:** `gojogo-builder`, policy `GojoGoMilestone1Policy` at **v6** ([iam-policy-milestone1.json](iam-policy-milestone1.json) tracks it: v3–v4 added CDK bootstrap/lookup + App Runner SLR perms; v5–v6 added Secrets Manager on `gojogo/*`, CloudWatch Logs read on `/aws/apprunner/*`, VPC-creation perms from the reverted private-networking attempt)
- **Local tools:** Java 23, Maven 3.9.16, AWS CLI 2.36.5, CDK 2.1132.0 (`~/.npm-global/bin/cdk` — may need `export PATH="$HOME/.npm-global/bin:$PATH"`)
- **CDK bootstrapped** in us-east-1

## Milestone status

- [x] **Phase 2c — Full Instagram stories** 🟡 **built + simulator-verified (2026-07-25), NOT deployed** — stories went from "a list of image URLs with a 24h expiry" to the whole product: photo / video / **text-card** frames with draggable text + sticker overlays, a real composer, per-frame playback timing (a video's progress bar follows actual playback, not a parallel timer), **replies kept inside `social` as private story comments** (the author reads all of them, a viewer reads only their own — deliberately *not* routed to a My World DM, since My World has its own identity and will get its own stories), quick emoji reactions, a "Seen by" viewers list, mute-without-unfollowing, and the persistence layer: your **archive**, profile **highlights**, and a **close-friends** audience enforced on read. Four migrations (`V11`–`V14`), two new domain events (`StoryReacted`, `StoryReplied`) consumed by `notifications` for activity rows + APNs. `ModularityTests` green; iOS builds and the composer / archive / close-friends flows are simulator-verified **against the live pre-V11 backend** — which also proved the optional-decode forward-compat and the optimistic-post rollback — but the new story endpoints 400/404 until this is rolled. See the Phase 2c section below.
- [x] **Phase 2b · Milestone 5 — Seller listing management** 🟡 **built + simulator-verified (2026-07-25), NOT deployed** — the seller's side of the marketplace. Listings gained a real lifecycle (`V10`: `status` ACTIVE/PAUSED/SOLD + `view_count` + `updated_at`, replacing the write-only `active` flag, which is left in place for rolling-deploy safety), plus owner-only `PUT` edit and `PUT` status, and a `/mine/stats` aggregate. iOS adds **"Your listings"** off a `Selling N` chip in the Economy chrome: stat tiles, status segments, and per-row edit / pause / mark-sold / relist / delete with optimistic moves that revert and explain themselves on failure. Browse now filters on status, so a sold item leaves the grid but stays on the seller's shelf and on a buyer's saved list (badged). Verified in the simulator **against the live pre-V10 backend** — which also proves the optional-decode forward-compat — but the mutation endpoints 404 until this is rolled. See the Phase 2b M5 section below for the deploy + the curl E2E it still needs.
- [x] **Phase 2b · Milestone 4 — Delivery vertical** ✅ **deployed + verified (2026-07-25)**, plus a same-day follow-up (demo catalog dropped, real saved addresses, error surface — see below) — new backend `delivery` module (Postgres `delivery` schema, Flyway `V8__delivery.sql` + `V9__delivery_addresses.sql`): restaurant/menu catalog (**now empty — the demo seed was deleted; merchant onboarding is `partner`, later**), **server-priced orders** (the client sends item ids + quantities, never prices), a real fulfilment state machine, order history, cancel and rate. GojoDelivery was the last vertical still bound to an *empty* `SampleData` catalog; it now runs on live data end to end. Fulfilment is **simulated on a server-side timeline** until the platform `dispatch` module exists (Phase 3) — but it's server-authoritative, so the countdown, the assigned courier and the courier's progress survive a relaunch and match on a second device. Prod two-user curl E2E green (52/52) **plus a simulator pass on the live backend** — first milestone whose SwiftUI path is verified in a running app, not just by build + curl. See the Phase 2b M4 section below.
- [x] **Phase 2b · Milestone 3 — Listing context on the thread** ✅ **deployed + verified (2026-07-24)** — a seller conversation now carries a **listing reference card**: `messaging` gained a generic public `ConversationContext` (kind/refId + pre-rendered title/subtitle/imageUrl — no messaging→economy dependency), stamped by `economy` in `openChat` and **refreshed on thread reuse** to whatever listing the buyer is asking about now. Surfaced on `ConversationDto`; iOS renders a tappable card pinned under the chat header (→ opens the live listing detail). This is the hook payments/orders will hang off. Two-user prod curl E2E green (buyer + seller both see the same card; reuse refreshes it; "on ask" → "On ask" subtitle). See the Phase 2b M3 section below.
- [x] **Phase 2b · Milestone 2 — Seller chat over messaging** ✅ **deployed + verified (2026-07-24)** — new `MessagingApi` public interface (first cross-vertical use of the messaging module); `POST /v1/economy/listings/{id}/chat` opens/reuses the buyer↔seller 1:1 and returns a prefilled opener without posting anything; iOS "Message seller" now lands in the real My World thread. Two-user prod curl E2E green. See the Phase 2b M2 section below.
- [x] **Phase 2b · Milestone 1 — Economy marketplace** ✅ **deployed + verified (2026-07-23)** — new backend `economy` vertical module (Postgres `economy` schema, Flyway `V6__economy.sql`): listings CRUD, browse (keyset pagination + category filter), save/unsave, mine/saved, publishes `ListingCreated` for the future search index. iOS `EconomyStore` + `AppState+Economy` wire `EconomyView`/`SellListingSheet` to the live catalog (sell-with-photo, save-sync); SampleData is the offline fallback. Two-user prod curl E2E green (create ±price, seller-decorated browse, category filter, save/`/saved`/`/mine`, unsave, 403 non-owner delete, 204→404). Fixed a save-count double-bump found in the first E2E (see incidents log). Seller-chat-over-messaging + Stripe/payments are the next 2b slices. See the Phase 2b M1 section below.
- [x] **Phase 2 · Milestone 5 — chat push notifications + persisted read receipts** ✅ **deployed + verified (2026-07-24)** — a new `messaging.MessageSent` domain event (published on every delivered message, immediate and send-later) is consumed by the `notifications` module to fire an **APNs alert to every recipient the live socket missed** (the first chat-message push — M3 only pushed the activity feed); iOS suppresses the banner for a thread you already have open. Plus **persisted "Read" receipts**: `GET …/messages` now returns `peerReadMessageId`, a server-computed high-water mark, so the receipt survives an app reload / offline gap instead of relying on a live socket event. Two-user prod curl E2E green (peerReadMessageId null→M2 after read; chat push authenticated to Apple, fake token pruned `BadDeviceToken`). See the Phase 2 M5 section below.
- [x] **Phase 2 · Milestone 4 — My World chat attachments + realtime resilience** ✅ **deployed + verified (2026-07-24)** — voice notes (hold-to-record, waveform playback, `audio/m4a` upload), system-keyboard stickers, the real camera, and a real GPS location pin carried as a `geo:` URI. Socket hardened (ping/backoff/foreground re-dial + re-sync) and the thread merge now keeps on-device media. Also fixed a pre-existing bug that permanently broke a 1:1 after both sides left it (see incidents log). Two-user prod curl E2E green. See the Phase 2 M4 section below.
- [x] **Milestone 1 — Backend skeleton + auth** ✅
- [x] **Milestone 2 — Profiles + social API** ✅
- [x] **Milestone 3 — Media upload** ✅ (CloudFront deferred — see known issues)
- [x] **Milestone 4 — iOS wiring** ✅ auth/feed/social/profile/media wired to the live backend; verified in simulator
- [x] **Milestone 5 — Buffer / hardening** ✅ — **Phase 1 complete.**
- [x] **Phase 2 · Milestone 3 — APNs push + messaging polish** ✅ **deployed + verified, APNs ACTIVATED (2026-07-23)** — Apple push key (`.p8`, Key ID `9W7A69BV93`) loaded from Secrets Manager; verified the backend authenticates to Apple (a fake token returned `400 BadDeviceToken`, not `403 InvalidProviderToken`). Only a **physical-device test** remains (needs the Push capability on the App ID + a real device to mint a token). Messaging polish fully live + verified — reply-to linking, outbound typing, **send-later over the wire**, **World-name reply snippets**, **backend group creation**, live video poster upload. Plus audit fixes: **profile edits now sync to the backend** and **avatar upload UI** wired. See the Phase 2 M3 section below.
- [x] **Phase 2 · Milestone 2 — Notifications (activity feed)** ✅ **deployed + verified (2026-07-23)** — `notifications` module (first consumer of the social domain events) persists follow/like/comment activity; `ActivityView` wired off SampleData. Two-user E2E green. See the Phase 2 M2 section below.
- [x] **Phase 2 · Milestone 1 — My World messaging** ✅ **deployed + verified (2026-07-23)** — backend `messaging` module + `GojoGoMessagingStack` (DynamoDB + WebSocket API) + WS Lambdas + full iOS wiring. Two-user curl E2E green (create/dedupe, send, unread/preview, read, react, poll create+vote, 404 boundary) and the real-time WebSocket fan-out verified (B's socket received A's message live). See the Phase 2 section below.

## Performance & infra hardening — "instant feed" (2026-07-24)

Goal: the feed should feel "already there" (Instagram-style), never a spinner. Split across client, backend, and infra.

**Deployment status (2026-07-24):**
- ✅ **Ranked feed + Cache-Control — LIVE** (`/actuator/health` 200; verified in a two-scroll simulator pass that remote images render with no spinner).
- ✅ **iOS prefetch** — ships with the next app build (client-only, no server dependency).
- ✅ **Private RDS — DONE, on ECS/Fargate.** RDS is now `PubliclyAccessible: false` in private VPC subnets, and the backend runs on **ECS/Fargate** behind an **ALB** (`https://api.gojogo.app`), reaching the private DB directly. Verified: full `/actuator/health` (real DB round-trip) returns 200 through the ALB, RDS private. **App Runner was abandoned** for this — its VPC-egress mode couldn't sustain the private-DB connection (health passed but instances died + ECR replacement failures). See [infra/FARGATE_MIGRATION.md](infra/FARGATE_MIGRATION.md) and the post-mortem below.
- **Backend runtime changed:** App Runner (`GojoGoAppStack`) → **ECS/Fargate (`GojoGoFargateStack`)**. New API base URL `https://api.gojogo.app` (ALB + ACM cert; DNS external). `BackendConfig.apiBaseURL` updated. Old App Runner stack is retired.

**iOS — the perceived-instant win.** Images used to load only when a cell appeared (`.task` on `CachedAsyncImage`), so a freshly-refreshed or scrolled-to post flashed a spinner. Added [`ImagePrefetcher`](GojoGo/DesignSystem/CachedAsyncImage.swift) (actor, bounded concurrency 4, in-flight de-dupe, free skip for memory-cache hits) that warms `ImageCache` *ahead* of the scroll. Wired in [AppState+Backend](GojoGo/Models/AppState+Backend.swift): `prefetchFeedImages` warms the first screenful on every `refreshSocial` and on each freshly-arrived page; `prefetchAround` look-aheads the next 6 posts from each cell's `onAppear` (folded into `loadMoreFeedIfNeeded`); pagination now triggers 6 rows out (was 3) so the next page is in hand early. Cold launch also warms the disk-restored feed (`applyCachedSession`), so the first screenful is decoded before the live refresh returns.

**Backend — ranked feed ("smart algo").** [`PostService.feed`](backend/src/main/java/com/gojogo/social/internal/PostService.java) was pure reverse-chronological; now each recency window is re-ranked in memory by `score = W_recency·e^(−ageHours/12) + W_engagement·ln(1+likes+2·comments) + W_affinity·(author followed)`. The keyset cursor stays on `createdAt` (stable pagination — no skips/dupes; `nextBefore` still the oldest post by time), so ranking only reorders *within* the fetched window — zero pagination risk, no post dropped, no new query. Also **deduped a double DB load**: `feed` computed `followeeIds` and then `decorate` fetched it again — `decorate` now takes the precomputed set (new overload; the create/get/byAuthor path keeps the single-fetch form).

**Backend — media cacheable forever.** Uploaded keys are content-addressed (`media/{profile}/{uuid}.{ext}`), so [`PresignService`](backend/src/main/java/com/gojogo/media/internal/PresignService.java) now stamps `Cache-Control: public, max-age=31536000, immutable` on the presigned PUT and returns it on the presign DTO; iOS replays the (signed) header on upload ([APIClient](GojoGo/CoreNetworking/APIClient.swift)). Makes media cacheable at the OS/URLCache layer now and at the **CloudFront edge** the moment the account is verified (prerequisite that was missing).

**Infra — explicit App Runner autoscaling.** [`app-stack.ts`](infra/lib/app-stack.ts) now declares a `CfnAutoScalingConfiguration` (min 1 / max 4 / concurrency 80) wired to the service, replacing the opaque AWS default (min 1 / max 25 / conc 100). `minSize: 1` matches the existing warm floor (same bill), but the floor/ceiling/concurrency are now codified and tunable — raise `minSize` before a launch spike.

**Infra — private RDS + NAT (IaC ready, NOT deployed).** The reverted private-networking attempt is now done correctly. [`data-stack.ts`](infra/lib/data-stack.ts) creates a dedicated VPC (2 AZ, public + PRIVATE_WITH_EGRESS, **1 NAT Gateway**), moves RDS into private subnets (`publiclyAccessible: false`), and locks the DB security group to **App Runner ingress only** (was `anyIpv4:5432`). [`app-stack.ts`](infra/lib/app-stack.ts) adds a `CfnVpcConnector` + `networkConfiguration.egressType: VPC` so the backend reaches the private DB; because App Runner routes *all* egress through the VPC, the NAT default route is what keeps Cognito / Apple JWKS / APNs / SNS reachable (the exact thing the first attempt lacked). **S3 + DynamoDB use free VPC gateway endpoints**, so only true internet egress hits the NAT. `cdk synth` verified: 1 NatGateway, 2 gateway endpoints, `PubliclyAccessible: false`, VpcConnector + wired ARN. **Deploying this REPLACES the RDS instance** (new VPC → new subnet group → replace; test data lost, acceptable per the DB note) and starts the ~$33/mo NAT charge — hence left for you. Cost: see [COSTS.md](COSTS.md). Construct/secret bumped V3→V4 per the in-place-replace convention; App Runner reads the endpoint + secret dynamically, so it re-wires automatically.

**Deploy: see [infra/PRIVATE_RDS_MIGRATION.md](infra/PRIVATE_RDS_MIGRATION.md)** — it's a staged migration (Phase 1 decouple = done + live; Phase 2 = the real move), and Phase 2 is **blocked until you apply the updated `iam-policy-milestone1.json` (v7) as admin/root** (adds NAT/EIP/IGW/VPC-endpoint perms the deploy user lacks). Phase 2 is destructive (DB replace, ~15 min downtime, +~$33/mo).

**Verified (2026-07-24):** backend `ModularityTests` green (Corretto 21); iOS `xcodebuild -sdk iphonesimulator` → **BUILD SUCCEEDED**; `cdk synth` clean; **two-scroll simulator pass on the live backend** — every remote post image rendered already-decoded, no spinner (the prefetch confirmed working end-to-end). The ranked-feed + Cache-Control image is **rolled to prod** (App Runner RUNNING, health 200).

**Deploy history / how it went (2026-07-24):**
- Ranked feed + Cache-Control: pushed the image + `aws apprunner start-deployment` → live. Zero-risk, non-destructive.
- Private-RDS/NAT one-shot **failed twice-over and rolled back cleanly (no data loss)**: first on a CDK *"Cannot delete export … in use by GojoGoAppStack"* deadlock (renaming `PostgresV3`→`V4` while AppStack imports its secret/endpoint), then the underlying IAM gap (no NAT/EIP/IGW/VPC-endpoint perms). Recovered by deploying **Phase 1** (AppStack DB-export decouple — live, health 200) and staging **Phase 2** for the user. See [infra/PRIVATE_RDS_MIGRATION.md](infra/PRIVATE_RDS_MIGRATION.md). **Lesson:** renaming a cross-stack-referenced resource needs a decouple deploy first; and probe IAM perms for brand-new resource *types* before a destructive deploy — an early export-check failure masked the missing NAT perms.

iOS changes ship with the next app build — no server dependency (the `cacheControl` presign field is optional-decoded, so an un-rolled backend still works).

## Milestone 5 additions

- Backend: `@RestControllerAdvice` for consistent `{"message"}` error bodies (+ `server.error.include-message: always`); `GET /v1/profiles/by-handle/{handle}` profile view lookup. Deployed + verified (error shapes, by-handle, cursor pagination).
- iOS: feed pagination (keyset cursor, loads more near the list bottom), pull-to-refresh on Home, loading spinner on first feed load, own-profile counts refresh on open, profile-by-handle fallback when the local id map misses. Verified in simulator incl. keychain session restore.

## What's deployed

| Thing | Value |
|---|---|
| API base URL | `https://api.gojogo.app` (ALB → ECS/Fargate; ACM cert, external DNS CNAME → ALB). **Was** App Runner `https://f6kp8hx2j2.us-east-1.awsapprunner.com` (retired) |
| Backend runtime | **ECS/Fargate** cluster `gojogo`, service `gojogo-backend` (1 task, 1 vCPU / 2 GB, private subnets), behind an internet-facing ALB. Stack `GojoGoFargateStack`. Replaced App Runner (`GojoGoAppStack`, retired) |
| Cognito user pool / client | `us-east-1_ImKOJoJaA` / `5gouehsu6bgaur82gcebiubvt0` (issuer `https://cognito-idp.us-east-1.amazonaws.com/us-east-1_ImKOJoJaA`) |
| RDS Postgres 16 | `gojogodatastack-postgresv3115c0d74-saoihc0u0yjf.ccpumiyo88o1.us-east-1.rds.amazonaws.com:5432/gojogo` — **replaced during the private-networking attempt; data reset was fine (test rows only)** |
| DB credentials | Secrets Manager `gojogo/db-credentials-v3` (RDS-generated; App Runner injects `DB_PASSWORD` via `runtimeEnvironmentSecrets`; `infra/.env.deploy` is obsolete) |
| ECR repo | `578109959809.dkr.ecr.us-east-1.amazonaws.com/gojogo-backend` |
| App Runner service | `gojogo-backend`, arn `...service/gojogo-backend/a33d8b2ac276407babdfdb27a5c2a940` |
| Stacks | `GojoGoAuthStack`, `GojoGoDataStack`, `GojoGoEcrStack`, `GojoGoMediaStack`, `GojoGoAppStack` — no deploy parameters needed (password comes from Secrets Manager) |
| Media bucket | `gojogo-user-media-578109959809` — presigned PUT writes; `media/*` objects public-read from S3 (interim, until CloudFront) |
| Media public domain | `gojogo-user-media-578109959809.s3.us-east-1.amazonaws.com` (App Runner env `MEDIA_BUCKET` / `MEDIA_CDN_DOMAIN`) |
| Messaging table (Phase 2) | DynamoDB `gojogo-messaging` (single-table, GSI `gsi1`, `ttl`) — App Runner env `MESSAGING_TABLE` |
| Messaging WebSocket (Phase 2) | `wss://ialc1dg00l.execute-api.us-east-1.amazonaws.com/prod` (id `ialc1dg00l`); `@connections` env `MESSAGING_WS_ENDPOINT`; Lambdas `gojogo-ws-authorizer` + `gojogo-ws-connections`; stack `GojoGoMessagingStack` |
| APNs key (Phase 2 M3) | Secrets Manager `gojogo/apns-key` (base64 .p8) → App Runner `APNS_KEY_BASE64`; plain env `APNS_KEY_ID=9W7A69BV93` / `APNS_TEAM_ID=T8348X4CNY` / `APNS_BUNDLE_ID=com.gojo.gojogo` / `APNS_PRODUCTION=false`. Device tokens in `notifications.device_token` (Flyway V4). |

## API surface (all require `Authorization: Bearer <Cognito ID token>` except health)

- `GET /actuator/health` (public)
- `POST /v1/auth/session` — create-or-fetch profile; returns profileId/handle
- `POST /v1/auth/apple` (**public**) — native Sign in with Apple: validates Apple's identity token, admin-creates/links the Cognito user, returns a Cognito token set `{idToken, accessToken, refreshToken, expiresIn}`
- `GET|PATCH /v1/profiles/me` — own profile (displayName, handle, bio, category, birthYear, avatarUrl, interests; PATCH = null field means unchanged; 409 on taken handle)
- `PUT /v1/profiles/me/handle` `{handle}` — change username (2-month cooldown after the free sets; 429 too-soon / 409 taken / 400 too-short) · `GET /v1/profiles/me/handle-status` → `{handle, handleChangedAt, changeAvailableAt, canChangeNow}` · `GET /v1/profiles/me/handle-available?handle=` → `{available, reason, normalized}` (reason ok|taken|invalid|current). See "Username change" below.
- `GET /v1/profiles/{id}` — profile view with postCount/followerCount/followingCount/isOwn/following
- `GET /v1/profiles/{id}/posts` · `POST|DELETE /v1/profiles/{id}/follow`
- `GET /v1/feed?before=<ISO8601>&limit=` — keyset-paginated; following+own, falls back to global recency when following no one; `nextBefore` cursor
- `POST /v1/posts` (text and/or ≤10 mediaItems `{imageUrl,videoUrl}`, imageAspect) · `GET|DELETE /v1/posts/{id}`
- `POST|DELETE /v1/posts/{id}/like` · `POST|DELETE /v1/posts/{id}/bookmark`
- `GET|POST /v1/posts/{id}/comments` · `POST|DELETE /v1/comments/{id}/like`
- `GET /v1/stories` (rings, own first, 24h expiry, per-viewer seen state) · `POST /v1/stories` (≤10 frames) · `POST /v1/stories/frames/{id}/seen` — plus the full stories surface added in Phase 2c (see that section)
- `POST /v1/media/presign` `{contentType}` → `{uploadUrl, key, publicUrl, expiresSeconds}` — client PUTs bytes to `uploadUrl` (S3-direct, 15-min expiry, content-type enforced: jpeg/png/webp/heic/gif/mp4/mov → else 415), then references `publicUrl` in posts/stories/avatarUrl

Domain events published in-process (`com.gojogo.social`): `PostCreated`, `UserFollowed`, (added in Phase 2 M2) `PostLiked`, `PostCommented`, and (Phase 2c) `StoryReacted`, `StoryReplied`. **First consumer:** the `notifications` module (see Phase 2 M2). It consumes via plain `@TransactionalEventListener(AFTER_COMMIT)` + `@Transactional(REQUIRES_NEW)` — deliberately *not* the durable Modulith registry (`starter-jpa` + `event_publication` table), which stays a later upgrade if at-least-once delivery across crashes is needed. `PostCreated` still has no consumer (search comes later).

## Verified end-to-end (2026-07-22)

Two-user curl flow against prod: sign-up/sign-in both users → A updates profile → A posts (text + 2 media) → B follows A → B's feed shows A's post with author/following decoration → B likes + comments (counts bump) → B's profile view of A shows counts + following → A posts story, B sees ring, marks seen, seen-state sticks → B unfollows (fixed: was 500) → B's feed falls back to discovery. Test users: `gojogo-m1-test@example.com` (A), `gojogo-m2-bob@example.com` (B), password `TestPass123456!`, in the pool with real content rows in prod DB.

## iOS wiring (Milestone 4)

- **`GojoGo/CoreNetworking/`** — `BackendConfig` (deployed URLs/ids), `KeychainStore`, `CognitoAuthClient` (native sign-up/confirm/sign-in/refresh over Cognito's JSON API — no Amplify), `APIClient` (async/await, Bearer ID token, one retry on 401 via refresh token, presigned media upload), `APIModels` (typed DTOs; timestamps parsed via `BackendDate`, which trims the backend's nanosecond fractions).
- **`GojoGo/Stores/`** — `SocialStore` (feed/posts/likes/bookmarks/comments/follows/stories + DTO→UI-model mapping; server UUIDs are reused as UI model ids) and `ProfileStore` (session/me/update/views). `AuthSession` actor owns tokens.
- **AppState stays the façade** the views bind to; its social/profile/auth methods now sync to the API (optimistic UI, fire-and-forget with DEBUG logging) via [AppState+Backend.swift](GojoGo/Models/AppState+Backend.swift). On launch with keychain tokens: cached UI first, then live session + feed/stories replace the Home content (other tabs keep SampleData by design). A full @Published store split was deliberately deferred — views are too coupled to AppState to split cheaply; revisit when more domains go live.
- **Email auth flow**: [EmailSignUpView](GojoGo/Auth/EmailSignUpView.swift) = email+password → (new users) emailed 6-digit code → onboarding pushes displayName/handle/birthYear/interests via PATCH. Existing users skip onboarding (routed by whether the profile has a displayName).
- **Social sign-in** (see the Google + Apple section below): the WelcomeView Apple button runs native Sign in with Apple; the Google button runs the Cognito Hosted-UI OAuth flow. Both converge on `AppState.applyTokens(_:email:)` — the same onboarding/app routing as email. WelcomeView shows a "Signing you in…" overlay + inline error while `authBusy`.
- **Image caching**: [CachedAsyncImage](GojoGo/DesignSystem/CachedAsyncImage.swift) (memory `NSCache` + disk store keyed by URL hash, 400 MB cap) replaces `AsyncImage` in `MediaImage`/`UserAvatar`, so remote media (avatars, post/story images) no longer re-downloads or re-decodes on every scroll/appearance. Shared `URLCache` also bumped at launch. Video streaming is unchanged.
- **DEBUG auto-login hook** for headless E2E: `SIMCTL_CHILD_GG_AUTOLOGIN_EMAIL` / `..._PASSWORD` env vars on `simctl launch` (DEBUG builds only).
- **Verified in simulator (2026-07-22)**: bob signs in → routed to onboarding (no displayName); Alice signs in → straight to Home showing the real feed incl. the M3 S3-hosted photo; own posts show no Follow chip; identity/counts from the live profile.
- **Gotchas learned**: simulator keychain survives app uninstall (`xcrun simctl keychain <udid> reset` between test identities); `URL.appendingPathComponent` percent-encodes `?` (feed query briefly 404'd — build URLs with `URL(string:relativeTo:)`).
- **Not yet wired**: the Collections verticals (Watch/Shorts/Economy/Travel/Delivery/Madeleine — still SampleData per plan, Phase 2b/3). (Feed pagination/refresh, Google/Apple sign-in, messaging + My World, notifications, APNs, and avatar/profile-edit upload are all now wired.)

## Social sign-in — Google + Apple (deployed 2026-07-23)

Two different mechanisms, both landing on the **same Cognito token model** so the resource server and `/v1/auth/session` are unchanged:

- **Google → Cognito Hosted UI** (OAuth authorization-code + PKCE). iOS opens `/oauth2/authorize?identity_provider=Google` in an `ASWebAuthenticationSession` ([GoogleSignInClient](GojoGo/CoreNetworking/SocialAuthClients.swift)), gets a code back at `gojogo://auth/callback`, exchanges it at `/oauth2/token` (public client, no secret) → Cognito tokens. Google is a Cognito IdP (federated user).
- **Apple → native**. iOS runs `ASAuthorizationController` ([AppleSignInClient](GojoGo/CoreNetworking/SocialAuthClients.swift)) with a hashed nonce, posts Apple's identity token to `POST /v1/auth/apple`. The backend ([AppleAuthService](backend/src/main/java/com/gojogo/auth/AppleAuthService.java)) validates it (Nimbus, Apple JWKS, iss/aud/nonce), then mints tokens via a **passwordless `CUSTOM_AUTH` flow** whose single challenge answer is the Apple token — re-validated by the [auth-triggers Lambda](infra/lambda/auth-triggers/index.mjs). No Apple IdP in Cognito; the exchange lives in the Spring `auth` module + one Cognito trigger Lambda.

**Account linking (email as the key).** The pool is `UsernameAttributes=email`, so one human = one Cognito user keyed by email, and each provider maps to that same user:
- The Apple `CUSTOM_AUTH` flow authenticates the email-keyed user **without ever setting/resetting its password** (a random permanent password is set *only* when creating a brand-new Apple-only user) — so an email/password account and Apple sign-in coexist non-destructively on the same account.
- Google (Hosted-UI federated) is linked to the existing email user on first sign-in by the same Lambda's `PreSignUp_ExternalProvider` trigger (`AdminLinkProviderForUser`).
- Net: email/password + Google + Apple with the same verified email all resolve to one Cognito user → one app profile.

**Why native Apple isn't a Cognito IdP:** Cognito user pools only federate Apple through the Hosted UI (a web sheet). To get the native black Apple button (App Store guideline 4.8) *and* real user-pool tokens *and* non-destructive linking, the backend validates Apple's token and drives `CUSTOM_AUTH` (the Lambda is the gate) — see [ARCHITECTURE.md §8].

**Deployed & verified (2026-07-23):** `GojoGoAuthStack` + `GojoGoAppStack` deployed; backend image pushed and App Runner rolled (RUNNING, `/actuator/health` UP). `POST /v1/auth/apple` is public and live (empty body → 400 validation; bad token → 401). The app-client id (`5gouehsu6bgaur82gcebiubvt0`) and Hosted-UI domain (`gojogo-auth.auth.us-east-1.amazoncognito.com`) were **unchanged** by the deploy, so `BackendConfig.swift` needed no edit. Google IdP created with a live OAuth client (project `537033269656`).

### Remaining to be fully usable

1. **Confirm the Google OAuth client's redirect URI** = `https://gojogo-auth.auth.us-east-1.amazoncognito.com/oauth2/idpresponse` (else Google returns `redirect_uri_mismatch`). The `argon-radius` project also has an unused `GojoGo iOS (Cognito Hosted UI)` client created during setup — safe to delete.
2. **Apple capability** (only needed to build/run the iOS app **on a device**; the backend works regardless): in the Apple Developer portal enable **Sign in with Apple** on App ID `com.gojo.gojogo` (team `T8348X4CNY`). The app already ships the entitlement ([GojoGo/GojoGo.entitlements](GojoGo/GojoGo.entitlements)). No Services ID / key needed — native flow validates against the bundle id. (Xcode "Automatic signing" adds the capability to the provisioning profile on first device build.)
3. **End-to-end test** on a device/simulator: tap Google and Apple on the Welcome screen.

<details><summary>Original one-time setup / redeploy commands</summary>

- Google OAuth client: Google Cloud Console → APIs & Services → Credentials → OAuth client ID → **Web application**, redirect URI as above.
- Deploy: `cdk deploy GojoGoAuthStack -c googleClientId=… -c googleClientSecret=… --require-approval never` → `cdk deploy GojoGoAppStack --require-approval never` → `mvn … jib:build …` → `aws apprunner start-deployment …`.
- If the app-client id or domain change on a future deploy, sync `cognitoClientId` / `hostedUIDomain` in [BackendConfig.swift](GojoGo/CoreNetworking/BackendConfig.swift).
</details>
3. **Deploy Cognito** with the Google creds (never commit them):
   ```
   cd infra && cdk deploy GojoGoAuthStack \
     -c googleClientId=xxxxx.apps.googleusercontent.com \
     -c googleClientSecret=yyyyy
   ```
   If the default domain prefix `gojogo-auth` is taken, add `-c authDomainPrefix=<unique>` and update `BackendConfig.hostedUIDomain` to match.
4. **Deploy the app stack** (adds Cognito admin perms + new env vars to App Runner): `cdk deploy GojoGoAppStack`, then push a fresh backend image and `aws apprunner start-deployment` (env changes are read at startup).
5. **Sync client ids**: if the app client's id changed, update `cognitoClientId` (and `hostedUIDomain`) in [BackendConfig.swift](GojoGo/CoreNetworking/BackendConfig.swift) from the `GojoGoAuthStack` outputs.

**Note:** adding OAuth + `custom` auth flow to the existing `IosAppClient`, and adding the `lambdaTriggers` to the pool, should be in-place updates (ids preserved), but CDK/CloudFormation *may* replace the client — check the diff; a replacement changes the client id (step 5) and invalidates existing refresh tokens (users re-sign-in once). `GojoGoAuthStack` now also creates the `gojogo-auth-triggers` Lambda; no separate action.

## Phase 2 · Milestone 1 — My World messaging (deployed + verified 2026-07-23)

Real-time private messaging (ARCHITECTURE.md §10 Phase 2). Store = **DynamoDB single table**; real-time = **API Gateway WebSocket** (server→client fan-out). Durable writes live in the Spring monolith; only the socket connection lifecycle is in Lambdas. **Deployed to prod and verified** — backend `mvn compile` + modularity test pass; `cdk synth` clean; iOS `xcodebuild` succeeds; two-user REST E2E green; WebSocket fan-out delivered live.

**Deployed coordinates** — WebSocket API `wss://ialc1dg00l.execute-api.us-east-1.amazonaws.com/prod` (id `ialc1dg00l`; `@connections` at the `https://` form), DynamoDB table `gojogo-messaging`, Lambdas `gojogo-ws-authorizer` + `gojogo-ws-connections`. App Runner env `MESSAGING_TABLE` / `MESSAGING_WS_ENDPOINT` set by CDK; iOS `BackendConfig.messagingSocketURL` synced. App-client id + pool unchanged.

**Backend — `com.gojogo.messaging` module** (new): DynamoDB single-table access (`MessagingRepository`), `MessagingService` (auth = must be a participant), REST controller, and `Fanout` (`@connections` PostToConnection). Added SDK deps `dynamodb` + `apigatewaymanagementapi`; config `MESSAGING_TABLE` / `MESSAGING_WS_ENDPOINT`. Single-table key design:

| Item | pk / sk | gsi1 |
|---|---|---|
| Conversation meta | `CONV#{cid}` / `META` | — |
| Direct-pair dedupe | `DIRECT#{a}#{b}` / `META` | — |
| Membership | `USER#{uid}` / `CONV#{cid}` | `USERCONV#{uid}` / `{lastActivity}` |
| Message | `CONV#{cid}` / `MSG#{mid}` | `CONVMSG#{cid}` / `{createdAt}` |
| Connection (Lambda-written) | `SUB#{sub}` / `CONN#{connId}` (+`ttl`) | — |

Connections are keyed by **Cognito subject** (all the `$connect` authorizer proves); `Fanout` bridges recipient profileId → sub via `ProfileApi` before pushing.

**API surface** (all Bearer-authed): `GET|POST /v1/conversations`, `GET|POST /v1/conversations/{id}/messages`, `POST|DELETE …/messages/{mid}/reactions`, `POST …/messages/{mid}/poll/vote`, `POST …/{id}/read`, `POST …/{id}/typing`, `POST …/{id}/pin`, `DELETE /v1/conversations/{id}` (leave). 1:1 auto-dedupes; groups/circles supported.

### My World setup — WhatsApp-style identity (deployed + verified 2026-07-23)

My World is its own phone-verified space, **separate from the app/social account** — first-run onboarding + phone number + World name/avatar, gated on entering the section. Backend lives in the same `messaging` module + DynamoDB table (`WORLDUSER#`, `WORLDPHONE#`, `WORLDOTP#` items); OTP is a 6-digit code (SHA-256 hashed, 10-min TTL, ≤5 attempts) sent by **SNS SMS** with a `WORLD_OTP_DEV_CODE` fallback (currently `424242`) so it's testable while SNS SMS is sandboxed. Conversations/messages now display the **World** name+avatar (fallback to the social profile).

- `GET /v1/world/me` → `{setupComplete, phone, displayName, avatarUrl}` (drives the iOS gate)
- `POST /v1/world/phone/start` `{phone}` → `{sent}` (E.164-normalized; texts the code)
- `POST /v1/world/phone/verify` `{phone, code}` → 204 (dev code or real SMS code; wrong → 401, expired/too-many → 400/429)
- `PUT /v1/world/me` `{displayName, avatarUrl}` → profile (setupComplete once phone verified + name set)
- `GET /v1/world/by-phone/{phone}` → `{profileId, displayName, avatarUrl}` (start a chat by number; 404 if unknown)

**iOS**: `WorldSetupView` (GojoGo design, not WhatsApp's — `IMColor`/ink bg, `AccentButton`, thin underlined fields): 3 intro pages → phone → 6-digit code → World name + photo (`PhotosPicker`). Gated in [RootView](GojoGo/Navigation/RootView.swift) via `app.needsWorldSetup` (backend `world/me` is source of truth; offline falls back to the demo). New Message resolves a **phone number or @handle** to a real World account (`/v1/world/by-phone`, `/v1/profiles/by-handle`) and opens a live thread. "Later" escapes back to Collections; setup resumes mid-flow (phone known → jumps to the profile step).

**Verified (2026-07-23):** `world/me` false→phone→(incomplete)→name→complete; wrong code 401; unknown phone 404; B resolves A by phone; a new conversation shows World display names, not social names.

**Infra — `GojoGoMessagingStack`** ([messaging-stack.ts](infra/lib/messaging-stack.ts)): DynamoDB table `gojogo-messaging` (PAY_PER_REQUEST, one GSI `gsi1`, `ttl`), WebSocket API `gojogo-messaging` with a Cognito-JWT `$connect` authorizer (token in query string) + `$connect`/`$disconnect` handler Lambdas ([infra/lambda/ws](infra/lambda/ws)). App stack grants the App Runner instance role table RW + `execute-api:ManageConnections` and injects `MESSAGING_TABLE` / `MESSAGING_WS_ENDPOINT`.

**iOS**: `MessagingModels` (DTOs), `MessagingStore` (REST + DTO→`WorldConversation`/`WorldMessage` mapping, `liveConversationIds`), `WorldSocket` (`URLSessionWebSocketTask`, token in query string, reconnect). `AppState+Messaging.swift` bridges the existing My World UI: on `connectBackend` it loads live conversations and opens the socket; live threads send over REST + receive over the socket (text/emoji/photo/carousel/poll/reactions/read/typing), and the **fake canned auto-reply is suppressed** for them (SampleData demo threads keep it). `addWorldContact` on a connected backend resolves a `@handle` via `/v1/profiles/by-handle` and opens a real 1:1. Remote photos render via `MediaImage(url:)`. Added optional `imageURL` to `WorldMessage`/`WorldCarouselItem`.

### Redeploy runbook (done once on 2026-07-23; repeat after backend changes — DynamoDB ~$0 idle, WS API + Lambdas pay-per-use)

```
export PATH="$HOME/.npm-global/bin:$PATH"
cd infra && cdk deploy GojoGoMessagingStack GojoGoAppStack --require-approval never
# then rebuild + roll the backend so it reads MESSAGING_* env (App Runner reads env at startup):
cd ../backend && mvn -B -DskipTests compile jib:build \
  -Djib.image=578109959809.dkr.ecr.us-east-1.amazonaws.com/gojogo-backend:latest \
  -Djib.to.auth.username=AWS -Djib.to.auth.password="$(aws ecr get-login-password --region us-east-1)"
aws apprunner start-deployment --service-arn <ServiceArn from PROGRESS>
```

**Post-deploy sync (already done):** [`BackendConfig.messagingSocketURL`](GojoGo/CoreNetworking/BackendConfig.swift) = `wss://ialc1dg00l.execute-api.us-east-1.amazonaws.com/prod` (the `GojoGoMessagingStack` output `WebSocketUrl`). Only re-sync if a future deploy changes the WS API id. App Runner env is wired by CDK; app-client id/pool unchanged.

**Verified (2026-07-23):** two-user curl flow (test users `gojogo-m1-test@example.com` / `gojogo-m2-bob@example.com`, `TestPass123456!`) — A `@handle`→1:1 create/dedupe, send text, B sees unread+preview, reads, reacts (heart persists), replies, marks read, A sends a poll, B votes (tally correct); GET unknown conv → 404. Real-time: a Node WebSocket client with B's ID token connected (authorizer accepted), A POSTed a message, B's socket received the `{"type":"message"}` fan-out. Scratchpad `verify_messaging.sh` / `ws_smoke.mjs` (session-local) captured the runs.

## Phase 2 · Milestone 4 — chat attachments + realtime resilience (deployed + verified 2026-07-24)

Makes the My World composer's attachments real rather than decorative, and stops the socket from quietly going stale. **No new AWS infra** — one content type added to the media whitelist; everything else is client work plus two preview labels.

**Attachments (iOS)**

| Surface | What it does now (was) |
|---|---|
| **Voice notes** | Hold the composer mic → live level meter + running time inline, slide left to cancel, release to send. The bubble is a real player: play/pause, a deterministic waveform that fills with playback, running time; one clip plays at a time across the app; remote clips download once into `Library/Caches/world-audio`. The m4a uploads via presign (`audio/m4a`) and the CDN URL is stamped onto the optimistic bubble. (Was: a modal recorder that sent a fake `durationLabel` and no audio.) [ChatAudio.swift](GojoGo/Screens/ChatAudio.swift) |
| **Stickers** | A sheet whose top half is a `UITextView` bridge to the **system keyboard's sticker tab** (also paste + drag-drop) — iOS 18 adaptive image glyphs and classic attachments both — so the user's own Memoji / Live Stickers send as PNG-with-alpha, rendered bare (no bubble). Recents cached on disk; an emoji grid stays as the fallback. (Was: a random emoji from a hardcoded array.) [StickerPicker.swift](GojoGo/Screens/StickerPicker.swift) |
| **Camera** | The drawer's Camera row opens the actual camera (photo + video, poster frame extracted, downscaled JPEG) and falls back to the library with a notice where there's no camera, e.g. the Simulator. (Was: it opened the photo picker.) [CameraCaptureView.swift](GojoGo/Screens/CameraCaptureView.swift) |
| **Location** | A one-shot CoreLocation fix + reverse-geocoded place name, sent as real coordinates; the bubble is an `MKMapSnapshotter` thumbnail (cached per coordinate — a live `MKMapView` per bubble is what made scrolling stutter) and taps through to Maps. Permission-denied / no-fix surface as a composer notice. (Was: a hardcoded Casablanca pin.) [LiveLocationProvider.swift](GojoGo/CoreNetworking/LiveLocationProvider.swift), [StaticLocationMap.swift](GojoGo/Screens/StaticLocationMap.swift) |

**Wire format (no schema change).** A message's media item is the only file slot, so: audio rides in `videoUrl` with `isVideo:false`; a pin rides there as a `geo:<lat>,<lon>` URI with the place name in `durationLabel` (`WorldLocationPayload` encodes/decodes it). `MediaReferenceService.keyFor` ignores non-S3 URIs, so a `geo:` item is passed through untouched and never tracked as media.

**Realtime resilience.** [WorldSocket](GojoGo/CoreNetworking/WorldSocket.swift) is `@MainActor`, pings every 30s (a failed ping cancels the task so a half-open socket reconnects in seconds), backs off 0.4s→8s instead of a flat 3s, exposes `isConnected` (the chat header shows "Connecting…") and an `onReconnect` hook. `RootView` re-dials on foreground — API Gateway drops idle sockets after 10 min, so a backgrounded app always came back stale. On reconnect/foreground the app re-syncs the list *and* the open thread; the merge is field-by-field so a refresh no longer blanks the open conversation, and on-device media (staged photo bytes, the local recording) survives both the reload and the server echo. The Messages list also polls every 30s as a safety net and derives its own relative timestamps.

**My World settings + contact page (also in this slice).** [WorldSettingsView](GojoGo/Screens/WorldSettingsView.swift) is a real settings screen: the World profile card saves over the wire (`PUT /v1/world/me`, avatar uploaded first — a failure surfaces rather than silently keeping the old name), plus privacy / notifications / appearance / storage / about. Device-scoped preferences (push on this device, typing pings, whether Location is offered in the drawer, default wallpaper, per-thread mutes) live in `UserDefaults` via [WorldPreference](GojoGo/Models/WorldPreference.swift) — they're about *this device*, not the account — and `AppState` mirrors each as a `@Published`. Muting is device-local by design: push fan-out has no per-thread flag. [WorldContactView](GojoGo/Screens/WorldContactView.swift) is rebuilt on live data — the other side's World identity + public GojoGo profile (a second, optional hop), the group roster, and shared photos/locations/links pulled from the thread instead of SampleData.

**Backend** — [PresignService](backend/src/main/java/com/gojogo/media/internal/PresignService.java) accepts `audio/m4a`; `MessagingService.previewFor` gained `sticker` → "Sticker" and `location` → "Location".

**Verified (2026-07-24)** — iOS `xcodebuild -sdk iphonesimulator` → BUILD SUCCEEDED; backend `ModularityTests` green under Corretto 21. Prod two-user curl E2E (`verify_attachments.sh`, session-local): `audio/m4a` presign → 200, a real `say`-recorded m4a PUT → 200 and public GET → 200; A sends audio / sticker / location → B's fetch round-trips all three with `mediaItems` intact (the `geo:33.5731,-7.5898` URI byte-identical); B's conversation preview updates; `audio/wav` still → **415** (whitelist not widened). Plus the leave/re-create regression case below.

**Not covered:** in-chat video playback (still a poster frame + play glyph — Phase 3's UGC video pipeline), and the SwiftUI live path is still only exercised by build + curl, not a two-identity simulator run (see the note at the end of this file).

## Phase 2 · Milestone 5 — chat push + persisted read receipts (deployed + verified 2026-07-24)

Two small, related closes on the My World messaging loop. **No new AWS infra** — reuses the existing APNs sender + DynamoDB read state.

**1. Chat-message push.** M3 pushed the *activity feed* (follow/like/comment) but a new **chat message** never rang a device the socket wasn't connected to. Now `MessagingService.sendMessage` (and the send-later `deliverConversation` poller) publishes a new public event [`messaging.MessageSent`](backend/src/main/java/com/gojogo/messaging/MessageSent.java) `(conversationId, senderId, senderName, preview, recipientIds)` after fan-out. The `notifications` module consumes it via [MessageNotificationListener](backend/src/main/java/com/gojogo/notifications/internal/MessageNotificationListener.java) → [`ApnsPushSender.notifyMessage`](backend/src/main/java/com/gojogo/notifications/internal/ApnsPushSender.java) (title = World sender name, body = message snippet, `type:"message"` + `conversationId` in the payload). It **pushes only** — a chat message isn't an activity-feed row, so nothing is persisted. Recipients exclude the sender.
- **Module seam:** `MessageSent` lives in the `messaging` module root (the API package, like `MessagingApi`) so `notifications → messaging` stays a public-API dependency (`ModularityTests` green). Unlike the social listeners it's a plain `@EventListener`, not `@TransactionalEventListener` — messaging writes to DynamoDB outside any JPA transaction, so an AFTER_COMMIT listener would never fire.
- **iOS:** `AppDelegate.willPresent` suppresses the foreground banner for a `type:"message"` push whose `conversationId` matches the thread already on screen (tracked by `PushRegistrar.activeConversationID`, set/cleared in `AppState.openWorldConversation` / `closeWorldConversation`). Other chats still banner.

**2. Persisted "Read" receipts.** Read state was previously only delivered as a live socket event, so a sender who was offline when the peer read never saw the receipt, and a reload reverted it to "Delivered". `GET /v1/conversations/{id}/messages` now returns **`peerReadMessageId`** — the newest message every *other* participant has read up to (`MessagingService.peerReadCutoff`: the slowest peer's read high-water mark; null while anyone still has the caller's messages unread, so a group only shows "Read" once everyone has). iOS `applyReadCutoff` stamps "Read" on the caller's own messages up to that id on every fetch/poll, and the field-by-field merge now carries a client-side "Read" across a reload (`mergeMessage`). Cheap point lookups per peer (read state already lives in each membership row).

**Verified (2026-07-24)** — `ModularityTests` green (Corretto 21), iOS `xcodebuild` → BUILD SUCCEEDED. Prod two-user curl E2E (`verify_chatpush_reads.sh`, session-local): B registers a device token → A sends two messages → A's own `GET messages` shows `peerReadMessageId = null` → B `POST /read` up to M2 → A's next fetch shows `peerReadMessageId = M2` (exact match). Chat push proven the M3 way: A's sends logged `APNs pruned dead token …(400): {"reason":"BadDeviceToken"}` in App Runner — Apple **accepted the provider JWT** and rejected only the fake device token, so the `MessageSent` → listener → APNs path signs + authenticates correctly. (No activity events fired in the run, so the prune is unambiguously the chat push.)

**Not covered:** live device delivery (same pending physical-device step as M3 — the simulator can't mint a real token) and the two-identity simulator UI pass.

## Phase 2 · Milestone 3 — APNs push + messaging polish (deployed 2026-07-23)

**APNs push (config-gated).** Delivers the M2 activity notifications to devices. All in the `notifications` module (no new AWS infra; Flyway `V4__device_tokens.sql`). `ApnsPushSender` signs an ES256 provider JWT with the `.p8` key (Nimbus, cached ~50 min) and POSTs to APNs over HTTP/2 (JDK `HttpClient`), fire-and-forget on a small executor; a 410/BadDeviceToken prunes the dead token. `NotificationService.record` calls it best-effort. **Entirely gated on config** (`APNS_KEY_ID` / `APNS_TEAM_ID` / `APNS_BUNDLE_ID` / `APNS_KEY_BASE64` / `APNS_PRODUCTION`) — with none set it no-ops, so nothing changes until a key exists.

- `POST /v1/push/register` `{token, platform}` (upsert, re-assigns the token to the caller), `POST /v1/push/unregister` `{token}`.
- iOS: `AppDelegate` registers for remote notifications + is the `UNUserNotificationCenter` delegate (foreground banners + tap → refresh feed); `PushRegistrar` sends the hex token to the backend once signed in; `AppState.enablePushNotifications()` requests permission on connect. Added the `aps-environment` entitlement.

**Messaging polish (fully live).** Live My World threads now: (1) **reply-to linking** — recipients see the quoted message; (2) **outbound typing** — composer pings `POST /typing` (throttled ~3s).

**Deferred polish — completed + verified (2026-07-23):**
- **Send-later over the wire** — a live thread's scheduled message is stored *pending* (DynamoDB `SCHED#DUE` partition, hidden from the feed) and delivered at its time by a `@Scheduled` poller (every 30s; each due message is claimed with a conditional delete so multi-instance App Runner delivers once). Verified: a message scheduled ~45s out was absent from the feed immediately, then present after the poller ran.
- **World-name reply snippets** — reply `authorName` now uses the World display name (verified `"Alice in My World"`, not the social name).
- **Backend group creation** — the New Message field accepts comma-separated handles/numbers; `startLiveGroup` resolves each to a real account and `POST /v1/conversations` with 3+ participants → a `group` (verified `type=group`, 3 participants, title set).
- **Live video** — a video attachment in a live thread now uploads its **poster frame** so the recipient's bubble renders (the video bubble is a decorative poster + play glyph everywhere; streamable in-chat playback is Phase 3's UGC video pipeline).

**Audit fixes (2026-07-23):**
- **Profile edits now persist** — `EditProfileSheet` "Save" was local-only; `updateProfile` now `PATCH`es `/v1/profiles/me` (displayName/bio/category) when connected.
- **Avatar upload UI** — the edit-profile avatar is now a `PhotosPicker`; pick → `uploadMedia` → `PATCH avatarUrl` (`syncProfileAvatar`). (World setup already had its own avatar picker.)

**Verified (2026-07-23):** `push/register` + `unregister` → 204; a reply with `replyToMessageId` round-trips `replyTo` `{messageId, authorName, preview}`; `typing` → 204. **APNs key verified live:** the `.p8` is stored in Secrets Manager `gojogo/apns-key` (base64) and injected as `APNS_KEY_BASE64` via `runtimeEnvironmentSecrets` (like `DB_PASSWORD`); non-secret `APNS_KEY_ID` (`9W7A69BV93`) / `APNS_TEAM_ID` (`T8348X4CNY`) / `APNS_BUNDLE_ID` / `APNS_PRODUCTION=false` are plain env in [app-stack.ts](infra/lib/app-stack.ts). A push to a fake token logged `APNs pruned dead token …(400): {"reason":"BadDeviceToken"}` — i.e. Apple **accepted the provider token (key)** and only rejected the (fake) device token, proving JWT signing + HTTP/2 + Apple auth all work. Scratchpad `verify_apns_polish.sh`.

### APNs — remaining to deliver to a real phone (your actions)

The key is configured and working; two device-only steps remain:
1. On App ID `com.gojo.gojogo`, enable the **Push Notifications** capability in the Apple Developer portal (Xcode automatic signing adds it to the profile on the next device build; the `aps-environment` entitlement already ships).
2. Run the app **on a physical device** (push doesn't route to the simulator), grant the permission prompt → the token registers via `POST /v1/push/register` → a follow/like/comment from another account delivers a banner. For a TestFlight/App Store build, redeploy with `APNS_PRODUCTION=true` (production APNs host).

**Rotate the key** anytime: `aws secretsmanager put-secret-value --secret-id gojogo/apns-key --secret-string "$(base64 -i AuthKey_XXXX.p8 | tr -d '\n')"`, update `APNS_KEY_ID` in app-stack, `cdk deploy GojoGoAppStack`.

## Phase 2 · Milestone 2 — Notifications / activity feed (deployed + verified 2026-07-23)

Platform `notifications` (ARCHITECTURE.md §10) — the **first consumer of the social domain events**. No new AWS infra (reuses RDS; Flyway `V3__notifications.sql` runs on startup).

**Backend** — new `com.gojogo.notifications` module (Postgres `notifications.notification` table). Added `PostLiked` / `PostCommented` events in `social` and publish them (with post-author id) from `PostService.like` / `CommentService.create`; `UserFollowed` already existed. `NotificationListeners` consumes all three via `@TransactionalEventListener` (AFTER_COMMIT) + `@Transactional(REQUIRES_NEW)` → persists a row for the recipient. Self-actions never notify. REST (Bearer-authed):

- `GET /v1/notifications?before=&limit=` — keyset-paginated, actor-decorated (name/handle/avatar via `ProfileApi`), server-generated text ("liked your post" / "commented on your post" / "started following you")
- `GET /v1/notifications/unread-count` → `{count}`
- `POST /v1/notifications/read` → mark all read (204)

**iOS** — `NotificationStore` + DTOs; `AppState.refreshNotifications()` replaces `SampleData.notifications` with live rows on connect and when the Activity sheet opens; `markActivityRead()` also `POST`s `/read` so the badge stays cleared across launches/devices. `ActivityView`/`unreadActivityCount` unchanged (already bind to `notifications`). Offline keeps the sample fallback.

**Verified (2026-07-23):** A self-likes → no notification; B follows + likes + comments on A → A's `unread-count` = 3, feed shows comment/like/follow newest-first with actor + text; mark-read → count 0. Scratchpad `verify_notifications.sh`.

## Phase 2b · Milestone 1 — Economy marketplace (deployed + verified 2026-07-23)

First slice of Phase 2b commerce (ARCHITECTURE.md §10). The `economy` **vertical** owns its listing data, decorates sellers via the `profile` public API, marks listing images referenced via `media`, and publishes a domain event for the future search index. No new AWS infra — reuses RDS; Flyway `V6__economy.sql` runs on startup (creates the `economy` schema).

**Backend — `com.gojogo.economy` module** (new): entities `Listing` / `ListingMedia` / `SavedListing`; `ListingService` (auth = seller-scoped for delete; save is idempotent); `EconomyController`; `EconomyCurrentProfile` (uniquely named — **not** `CurrentProfile[s]`, per the notifications bean-collision incident). Publishes `com.gojogo.economy.ListingCreated` on create (no consumer yet — mirrors `social.PostCreated`, first consumer = OpenSearch in a later 2b slice).

Schema (`economy` schema, no cross-schema FKs — seller_id/user_id are plain UUIDs):

| Table | Columns |
|---|---|
| `economy.listing` | id, seller_id, title, price_cents (nullable = "on ask"), currency, category, condition, location_label, description, active, save_count, created_at |
| `economy.listing_media` | id, listing_id (FK, cascade), sort_order, image_url |
| `economy.saved_listing` | listing_id (FK) + user_id PK, created_at |

**API surface** (all Bearer-authed):
- `GET /v1/economy/listings?category=&before=<ISO8601>&limit=` — active listings, keyset-paginated (createdAt desc), optional category filter, `nextBefore` cursor, seller-decorated + `saved`/`isOwn`
- `GET /v1/economy/listings/{id}` · `POST /v1/economy/listings` (sell) · `DELETE /v1/economy/listings/{id}` (owner only)
- `POST|DELETE /v1/economy/listings/{id}/save` (bump/decrement save_count, idempotent)
- `GET /v1/economy/listings/mine` · `GET /v1/economy/saved`

**iOS** — `EconomyModels` (DTOs) + `EconomyStore` (REST + DTO→`Product` mapping; price cents↔display string, stable seller gradient, `remoteListingIds` gate) + `AppState+Economy.swift`. On `connectBackend` → `refreshEconomy()` replaces the SampleData catalog with live listings (newest = featured hero, rest = grid); an empty prod keeps the samples. `SellListingSheet` now has a `PhotosPicker` and routes publish → `createListing` (uploads the photo via `media/presign`, POSTs the listing); `toggleSaveProduct` → `syncListingSave` for server-backed products. Offline degrades to the local draft/sample path.

**Verified (2026-07-23):** backend `mvn -Dtest=ModularityTests test` green under Corretto 21 (module boundaries intact); iOS `xcodebuild -scheme GojoGo -sdk iphonesimulator` → `BUILD SUCCEEDED`. **Prod two-user curl E2E green** (test users A=`gojogo-m1-test@example.com` / B=`gojogo-m2-bob@example.com`, `TestPass123456!`): A creates a listing with price + a second "on ask" (null price) → B's browse shows it seller-decorated (`isOwn=false`, `saved=false`) → category=Cameras filter returns it → B saves (idempotent, 3× → `save_count`=1 after the fix) → B's `/saved` returns it → A's `/mine` returns both → B unsaves (`/saved` empties, count→0) → B deleting A's listing → **403** → A deletes → **204**, subsequent GET → **404**. Test listings cleaned up afterward. Scratchpad `verify_economy.sh` + `verify_savecount.sh` (session-local).

### Deploy runbook (executed 2026-07-23; repeat after backend changes)

```
# 1. Backend only (no CDK/infra change — economy adds no AWS resources):
export JAVA_HOME=/Users/mac/Library/Java/JavaVirtualMachines/corretto-21.0.5/Contents/Home
cd backend && mvn -B -DskipTests compile jib:build \
  -Djib.image=578109959809.dkr.ecr.us-east-1.amazonaws.com/gojogo-backend:latest \
  -Djib.to.auth.username=AWS -Djib.to.auth.password="$(aws ecr get-login-password --region us-east-1)"
# 2. Roll App Runner (V6 Flyway migration applies on startup):
aws apprunner start-deployment --service-arn arn:aws:apprunner:us-east-1:578109959809:service/gojogo-backend/a33d8b2ac276407babdfdb27a5c2a940
```

**Deferred (next 2b slices):** ~~seller-chat over the `messaging` API~~ — **done in M2 below (2026-07-24)**. Still open: Stripe + Connect checkout + `payments` ledger, the OpenSearch consumer of `ListingCreated`, and economy listing pagination in the grid UI (`loadMoreEconomyIfNeeded` exists but the grid caps at 8 cards today).

## Phase 2b · Milestone 2 — seller chat over messaging (deployed + verified 2026-07-24)

Closes the marketplace loop: "Message seller" on a live listing now opens a **real My World thread** with the seller instead of the canned demo. No new AWS infra — this is the first cross-vertical use of the `messaging` module.

**The module seam.** New public API [`MessagingApi`](backend/src/main/java/com/gojogo/messaging/MessagingApi.java) (module root, like `ProfileApi` / `MediaApi`) with exactly one method — `openDirectConversation(callerId, otherId)` — implemented by `MessagingApiAdapter` over the same `MessagingService` the REST controller uses, so a listing thread is indistinguishable from one started in My World (same 1:1 dedupe, same WebSocket fan-out). Verticals get "put these two people in a thread"; they don't get to drive chat. `ModularityTests` confirms `economy → messaging` goes through the public API only.

**API** — `POST /v1/economy/listings/{id}/chat` → `{conversationId, sellerId, suggestedMessage}`; `400` on your own listing, `404` on an unknown one. It **posts nothing**: the opener ("Hi — is the Leica M6 (12 000 MAD) still available?", price omitted for "on ask") is prefilled in the buyer's composer, so browsing a listing never leaves the seller an empty thread and the buyer still chooses to send.

**iOS** — `EconomyStore.startChat` + `ListingChatDTO`; the store now also tracks `ownListingIds` (from `isOwn`) so the detail sheet shows a flat "Your listing" instead of a Message button on your own item. `AppState.openSellerChat` routes: live listing + session → `openLiveSellerChat` (fetch the thread → refresh conversations → leave the marketplace → open the thread with the draft prefilled); anything else (SampleData catalog, signed out, or a failed call) keeps the local demo chat, so the button is never dead. A buyer who hasn't done My World setup has the thread **parked** and opened for them the moment setup completes.

**Verified (2026-07-24)** — `ModularityTests` green (Corretto 21), iOS `xcodebuild` → BUILD SUCCEEDED, and a prod two-user curl E2E (`verify_seller_chat.sh`, session-local): A lists → B opens the chat (`sellerId` = A, opener `"Hi — is the Leica M6 (12,000 MAD) still available?"`) → asking again returns the **same** conversation → **three** opens add **zero** messages to the thread (17 → 17: nothing is posted on the buyer's behalf) → B sends the opener and it lands in **A's** list (`unread=1`, preview set) → A on their own listing → **400**, unknown listing → **404** → an "on ask" listing yields a price-free opener.

**Deferred (next 2b slices):** ~~listing-context metadata on the thread~~ — **done in M3 below (2026-07-24)**. Still open: Stripe + Connect checkout and the `payments` ledger, the OpenSearch consumer of `ListingCreated`, and the `delivery` vertical.

## Phase 2b · Milestone 3 — listing context on the thread (deployed + verified 2026-07-24)

Gives a seller conversation a **reference back to the listing it's about**. Until now the thread carried no listing link (the M2 opener text was the only clue); now both buyer and seller see a listing card pinned to the thread, and the conversation holds a machine-readable pointer — the seam a checkout/order will hang off. No new AWS infra (the card is a JSON attribute on the existing conversation meta item).

**The module seam — a generic context card.** New public [`messaging.ConversationContext`](backend/src/main/java/com/gojogo/messaging/ConversationContext.java) `(kind, refId, title, subtitle, imageUrl)` — deliberately vertical-agnostic (a `delivery` order or `travel` ride would carry the same shape), so `messaging` never gains a dependency on `economy`. It's **opaque to messaging**: `kind`/`refId` let the client (and later payments) resolve the real object; title/subtitle/imageUrl are the pre-rendered card so drawing it needs no cross-module read. Stored as `contextJson` on the `CONV#{cid}/META` item; echoed on `ConversationDto`. `MessagingApi` gained an overload `openDirectConversation(caller, other, context)` (the old 2-arg form delegates with `null`); `ModularityTests` confirms `economy → messaging` is still public-API-only.

**Refresh-on-reuse.** The buyer↔seller 1:1 is deduped by pair (M2), so a buyer who messages the same seller about a *second* listing reuses the thread — and `createConversation` now **overwrites the card** (`repo.updateContext`) to the listing being asked about now. Both sides see the update on their next fetch/poll. (Trade-off: one thread per pair means the card reflects the most-recent listing, not a per-listing thread; matches the existing "one My World 1:1 per person" model and is what a single order/checkout wants to attach to.)

**Economy** — [`ListingService.openChat`](backend/src/main/java/com/gojogo/economy/internal/ListingService.java) builds the card from the listing: `subtitle` = the grouped price label or `"On ask"` for a null price, `imageUrl` = the first listing image. `POST /v1/economy/listings/{id}/chat` is otherwise unchanged (still returns `{conversationId, sellerId, suggestedMessage}` and posts nothing).

**iOS** — `ConversationContextDTO` + `ConversationDTO.context`; UI model `WorldListingContext` (parses `refId`→`listingID` when `kind=="listing"`) on `WorldConversation`, mapped in `MessagingStore`. [WorldChatView](GojoGo/Screens/WorldChatView.swift) renders an opaque, tappable card pinned under the chat header (thumbnail + title + price + "View ›"); the thread's top inset grows so messages clear it. Tapping → `AppState.openListingContext` fetches the listing (`EconomyStore.get`, since it may not be in the loaded catalog page), seeds the catalog so `ProductDetailView` resolves it, and opens the detail — with a card-derived fallback product if the fetch fails, so the tap is never dead. The field-by-field conversation merge leaves the card server-authoritative (the incoming row carries it).

**Verified (2026-07-24)** — `ModularityTests` green (Corretto 21), iOS `xcodebuild -sdk iphonesimulator` → BUILD SUCCEEDED, and a prod two-user curl E2E (`verify_listing_context.sh`, session-local): A lists a priced Leica + an "on ask" lens → B opens chat on the Leica → **B's** conversation shows `context {kind:listing, refId:<leica>, title, subtitle:"12,000 MAD"}` → **A (seller)** sees the identical card → B opens chat on the "on ask" lens → **same thread** (`conversationId` unchanged) with the card **refreshed** to `refId:<lens>, subtitle:"On ask"`. Test listings cleaned up (204s).

**Not covered:** no listing card yet on the *conversation list* row (only inside the open thread); a live socket push of a context change on reuse (the seller learns the refreshed card on next fetch/poll, not instantly); and the SwiftUI card is exercised by build + curl, not a two-identity simulator run (same pending on-device pass as the rest of 2b).

## Phase 2b · Milestone 4 — delivery vertical (deployed + verified 2026-07-25)

The other half of commerce (ARCHITECTURE.md §10 Phase 2b). GojoDelivery was the last vertical wired to an **empty** `SampleData` catalog — the tab showed its empty state — so this milestone is the whole loop: browse → menu → cart → order → track → rate → order again. No new AWS infra (reuses RDS; `V8__delivery.sql` runs on startup and creates the `delivery` schema).

**Backend — `com.gojogo.delivery` module** (new): entities `Merchant` / `MenuSection` / `MenuItem` / `CustomerOrder` / `OrderLine`; `DeliveryService`, `DeliveryController`, `DeliveryTimeline`, `OrderFulfilmentJob`, and `DeliveryCurrentProfile` (uniquely named per the bean-collision incident). Publishes public `delivery.OrderPlaced` and `delivery.OrderStatusChanged` — no consumer yet, mirroring `economy.ListingCreated`; `OrderStatusChanged` is the hook an "your food is on the way" APNs push hangs off (`notifications` already consumes `messaging.MessageSent` that way).

Decisions worth keeping straight:

- **The server prices the order.** The request carries `{menuItemId, qty}` only; names and unit prices are read from the menu, copied onto the order lines (so a re-priced dish never rewrites an old receipt), and the delivery fee comes from the merchant row. The client's cart total is a preview — `DeliveryRestaurant` gained `feeCents` so that preview matches instead of the old hardcoded `$1.49`.
- **Cart stays on the device.** A per-tap cart sync buys nothing here and costs a request per `+`; the order is the transaction, and it's whole-cart.
- **One live order per user** — a second `POST` while one is in flight is a `409`, matching a UI that tracks exactly one order.
- **Fulfilment is simulated, but the state machine is real.** Offsets from `placedAt` (config `gojogo.delivery.timeline.*`, default 20s → 75s → 150s → 330s) say where an order *should* be; `OrderFulfilmentJob` (every 10s) walks each open order there and publishes every step it passes through. Because state is recomputed from `placedAt` rather than accumulated, a missed tick, a restart or a slow deploy catches up instead of stranding an order in "Preparing". `CustomerOrder` carries a `@Version` so two backend instances can't both advance the same order. When `dispatch` lands (Phase 3), this job is the only thing it replaces.
- **Cancel window**: allowed through `COURIER_TO_RESTAURANT`, `409` once the food is moving (`DELIVERING`) — the same rule the UI's cancel button already assumed.

Schema (`delivery` schema, no cross-schema FKs — `user_id` is a plain UUID):

| Table | Columns |
|---|---|
| `delivery.merchant` | id, name, cuisine, rating, review_count, eta_minutes, delivery_fee_cents, image_url, promo, latitude, longitude, active, created_at |
| `delivery.merchant_category` / `merchant_tag` | (merchant_id, category) / (merchant_id, tag) — categories are the browse filter, tags are display chips |
| `delivery.menu_section` · `delivery.menu_item` | section: merchant_id, name, sort_order · item: section_id, name, detail, price_cents, image_url, popular, available, sort_order |
| `delivery.customer_order` | id, user_id, merchant_id, status, subtotal/delivery_fee/service_fee/total cents, currency, address_label, note, courier_*, rating, placed_at, status_changed_at, eta_at, closed_at, version |
| `delivery.order_line` | order_id, menu_item_id, name, unit_price_cents, qty, sort_order |

**Seeded catalog** — 6 Casablanca restaurants (Atlas Burger Co., Forno Nero, Kaido Sushi, El Tapeo, Verde Bowl, Maison Sucrée), 12 menu sections, 25 items, covering the category strip the app already shipped. Fixed UUIDs, so a rebuilt database keeps the same item ids. Merchant self-onboarding belongs to `partner` in a later phase; images are null for now and render as the app's placeholder.

**API surface** (all Bearer-authed):
- `GET /v1/delivery/merchants?category=&q=&limit=` — active restaurants, fastest first; menus omitted
- `GET /v1/delivery/merchants/{id}` — the only response carrying the menu
- `POST /v1/delivery/orders` `{merchantId, lines[{menuItemId, qty}], addressLabel, note}` → 201 (409 if one is live, 400 on an item that isn't on that menu)
- `GET /v1/delivery/orders/active` → `{order}` (null when nothing is in flight — a 404 would be noise on a poll) · `GET /v1/delivery/orders?limit=` (history) · `GET /v1/delivery/orders/{id}`
- `POST /v1/delivery/orders/{id}/cancel` · `POST /v1/delivery/orders/{id}/rate` `{rating}` (1–5, delivered only)

**iOS** — `DeliveryModels` (DTOs) + `DeliveryStore` (REST + DTO→`DeliveryRestaurant`/`DeliveryMenuItem`/`DeliveryCourier` mapping, `remoteMerchantIds` gate) + [AppState+Delivery.swift](GojoGo/Models/AppState+Delivery.swift). `connectBackend` → `refreshDelivery()` swaps in the live catalog, re-attaches to an order already in flight, and loads history into the "Order again" rail. Opening a restaurant lazily fetches its menu. Checkout routes to `placeLiveDeliveryOrder` for a server-backed restaurant (optimistic tracking screen; a failed call hands the cart back), and the tracking screen then **mirrors the backend** — status, ETA, courier, and the moving-pin progress all come from the poll (every 5s, by order id so a delivered order stays up for its rating) instead of the on-device timer. Cancel and the star rating post to the API; a `409` on a too-late cancel puts the tracking screen back rather than pretending. SampleData restaurants (i.e. offline) keep the original local simulation untouched.

**Verified (2026-07-25)** — backend `ModularityTests` green (Corretto 21); iOS `xcodebuild -sdk iphonesimulator` → BUILD SUCCEEDED; V8 applied on the Fargate roll and the context started clean (so Hibernate `validate` accepted the new mappings). **Prod two-user curl E2E green, 52/52** (`verify_delivery.sh`, session-local): catalog count/order/fee, category + text filters, menu-only-on-detail, unknown restaurant 404 → A orders (subtotal `2×890+390`, fee 149, service 99, total **2418** — all server-computed), second order 409, B can't read A's order (404), cross-restaurant item 400, empty cart 400 → A's order reaches PREPARING, cancels (200), cancel again 409, rating a cancelled order 409 → B rides an order through COURIER_TO_RESTAURANT (courier assigned) and DELIVERING (progress climbing 0.04→1.0, ETA counting 6→1) to DELIVERED, with a cancel attempt during DELIVERING correctly **409**, rate-before-delivery 409, rating 9 → 400, rating 5 → 200 → history holds both users' orders, receipts and note intact, and neither sees the other's.

**Also verified in the simulator on the live backend** (the on-device pass the earlier 2b milestones never got): signed in as test user A → GojoDelivery showed the **live** catalog (Verde Bowl 4.5 · 17 min · *Delivery free*, El Tapeo's "20% off" promo) → opening Verde Bowl lazily loaded its menu (Bowls/Juices, `$11.40`/`$12.90`/`$6.20`, "Popular" badge, Gluten free / Vegan tags) → adding items drove the cart bar and a checkout whose fee lines matched the merchant (Free delivery, $0.99 service, **$12.39**) → "Place order" created the order in prod (curl confirmed `Verde Bowl`, `1239`, address label `Home · 12 Rue Atlas`) → the tracking screen showed the **server's** 6-minute ETA (not the catalog's 17) and, ~90s later, advanced by itself to "Courier picking up · 4 min" with courier **Amine T. ★4.91 · On foot** from the backend roster → "Cancel order" returned to browse and the server showed the order `CANCELLED` with nothing active. A second order (2× bowl, `$23.79`) was then ridden all the way through in the UI: the pin walked the route, the cancel button disappeared at "On the way", "Delivered" showed with the star prompt, and 5 stars + Done wrote `rating: 5` to the order and put it in the **"Order again"** rail (`6m · $23.79`) — with the two cancelled orders correctly absent from that rail.

**Not covered / deferred:** no per-item options/extras; no live courier geo (the map animates the pin along a synthetic route — real positions come with Phase 3 `dispatch`); and `OrderPlaced` / `OrderStatusChanged` have no consumer yet (order push is the obvious next slice). The two gaps this section originally listed — no error surface, and a hardcoded delivery address — are closed in the follow-up below.

### Follow-up (2026-07-25): demo catalog dropped, real addresses, error surface

Three changes on top of M4, deployed together as `V9__delivery_addresses.sql`.

**1. The seeded demo catalog is gone.** V8's six restaurants were scaffolding to prove the loop; they're deleted (along with the E2E orders that referenced them — `customer_order` has a plain FK to `merchant`, so those had to go first). V8 is deliberately left untouched: it has already run in prod, and rewriting an applied migration breaks Flyway's checksum, so a fresh database inserts the seed and V9 removes it. **GojoDelivery now shows its empty state until real merchants exist** — a merchant-onboarding surface (the `partner` vertical) is what unblocks it.

**2. Delivery addresses are real.** New `delivery.address` table (label, street, courier note, optional coordinates, `is_default`) with **one default per user enforced by a partial unique index**, not by application hope. The order copies the address onto itself at order time — same rule as line prices, so editing or deleting a saved address never rewrites an old receipt (`customer_order` gained `address_id`, `address_line`, `address_note`, and coordinates; there is deliberately no FK back to `address`).
- `GET /v1/delivery/addresses` · `POST /v1/delivery/addresses` · `PUT /v1/delivery/addresses/{id}` · `POST /v1/delivery/addresses/{id}/default` · `DELETE /v1/delivery/addresses/{id}`
- `POST /v1/delivery/orders` takes `addressId`; omitting it uses the caller's default, and an order with **no** address is a `400` ("Add a delivery address first"). The old free-text `addressLabel` is still accepted so an older client keeps working.
- Rules that make the UI simple: the first address a user saves becomes their default automatically, and deleting the default promotes the next one — a user with addresses left always has one selected.
- **iOS** — [DeliveryAddressSheet](GojoGo/Screens/DeliveryAddressSheet.swift): saved addresses as tinted-glass rows (`.glass(tint:)`, the app's Liquid-Glass modifier) with a house/office/pin icon, DEFAULT chip, checkmark on the selected one, and an ellipsis menu for edit/delete; an inline add/edit form with Home/Work/Other label chips, street + courier-note fields, and **"Use my current location"** (one-shot GPS + reverse geocode, reusing the provider behind chat location pins). Opens from the browse header's "Deliver to" row and from checkout — checkout presents its own copy so it stacks over the sheet instead of fighting the root view's sheet slot, and the place-order button reads "Add a delivery address" (and opens the sheet) when there's nowhere to deliver.

**3. GojoDelivery can admit failure.** A tinted-glass notice banner (top of the section, auto-dismisses, tap-to-close) now surfaces: a failed order placement (the cart is handed back and *says so*), a refused cancel, and address save/delete failures — preferring **the backend's own message** ("Too late to cancel — your courier is on the way") over a generic one. A failed save also re-reads the address list, so a screen that just proved itself stale reconciles instead of lingering.

**Verified (2026-07-25)** — `ModularityTests` green, iOS `xcodebuild` → BUILD SUCCEEDED, V9 applied on the Fargate roll with a clean startup (Hibernate `validate` accepted the new table and columns). **Prod two-user curl E2E green, 33/33** (`verify_addresses.sh`, session-local): catalog is empty and a seeded restaurant id is now `404`, its orders are gone → create/edit/delete addresses, first-is-default, `makeDefault` switching (always exactly one default, listed first), delete-the-default promotes the survivor, blank street `400`, and B can neither read, edit, nor delete A's addresses (`404` each). **Simulator pass on the live backend:** the delivery tab shows "No restaurants yet"; the header reads "Add a delivery address"; adding one through the sheet wrote it to prod (curl-confirmed) and the header updated; the saved row rendered with its DEFAULT chip and checkmark; deleting from the ellipsis menu emptied it server-side. The notice banner was exercised for real — an address deleted behind the app's back made "Save" fail, and the banner showed the backend's own **"No such address"** while the list reconciled itself.

**Known limits of this follow-up:** with an empty catalog there is no way to place an order in prod, so the *order-carries-address* path (address copied onto the receipt, missing-address `400`) is compile- and review-verified only — it will be exercised the first time a real merchant exists. The address form is free text (no autocomplete/map pin beyond "use my location"), and the notice banner floats over the "Deliver to" row while it's up.

### Deploy runbook (executed 2026-07-25; the backend now runs on ECS/Fargate, **not** App Runner)

**Superseded 2026-07-25 by [scripts/deploy-backend.sh](scripts/deploy-backend.sh)** — see "Deploying the backend" below. The hand-rolled version this milestone used was:

```
export JAVA_HOME=/Users/mac/Library/Java/JavaVirtualMachines/corretto-21.0.5/Contents/Home
cd backend && mvn -B -DskipTests compile jib:build \
  -Djib.image=578109959809.dkr.ecr.us-east-1.amazonaws.com/gojogo-backend:latest \
  -Djib.to.auth.username=AWS -Djib.to.auth.password="$(aws ecr get-login-password --region us-east-1)"
aws ecs update-service --cluster gojogo --service gojogo-backend --force-new-deployment --region us-east-1
```

(Older milestone runbooks in this file end with `aws apprunner start-deployment` — that service is retired.)

## Deploying the backend (2026-07-25)

Both paths run the same script, so CI and a laptop deploy can't drift.

**Automatic** — any push to `main` touching `backend/**` deploys it ([.github/workflows/deploy-backend.yml](.github/workflows/deploy-backend.yml), concurrency-limited to one at a time). The workflow previously ended with `apprunner start-deployment` against the service the Fargate migration destroyed, so pushes built an image and then silently failed to deploy it; it now just calls the script.

**Manual** — `./scripts/deploy-backend.sh`. Preflight → `mvn test` → Jib push → new task definition revision → rollout wait → health check, stopping at the first failure.

**⚠️ Blocked on an IAM change (2026-07-25) — needs an admin.** Registering a task definition hands ECS the task + execution roles, so it needs `iam:PassRole` with `iam:PassedToService` including `ecs-tasks.amazonaws.com`. The old deploy path (`force-new-deployment` on a mutable tag) never passed a role, so this was never needed. The first CI run failed exactly there — tests green, image `e0e1ad6` pushed, then `AccessDeniedException ... iam:PassRole`.

`iam-policy-milestone1.json` now carries the fix. Two traps found while preparing it, both fixed in the file: it had drifted **behind** the applied policy (it was missing the live `CloudFrontForMediaCdn` and `S3ForUserMediaBuckets` statements, so applying it verbatim would have *revoked* media permissions), and it used a literal `ACCOUNT_ID` placeholder that the documented `create-policy-version` command would have installed as-is. The file is now a faithful mirror of the applied **v9** plus `ecs.amazonaws.com` / `ecs-tasks.amazonaws.com`, with real account ids. Apply as admin:

```bash
aws iam create-policy-version \
  --policy-arn arn:aws:iam::578109959809:policy/GojoGoMilestone1Policy \
  --policy-document file://iam-policy-milestone1.json --set-as-default
```

(On the 5-version limit: `aws iam delete-policy-version --policy-arn <arn> --version-id vN` for the oldest non-default.) Then re-run the deploy — it reuses the image already in ECR rather than rebuilding.

**Images are pinned by immutable tag, and that's the point.** The service used to run `:latest`, which every deploy overwrote — so "roll back to the previous task definition" got you the same broken image, and rollback was effectively manual archaeology. Each deploy now pushes `<git-sha>` and registers a task definition revision pinned to it (`latest` still gets pushed, but nothing runs from it). Revision N-1 therefore still references exactly what it shipped:

```
./scripts/deploy-backend.sh --list       # revisions, their images, which is live
./scripts/deploy-backend.sh --rollback   # back one revision, no rebuild
```

Consequences worth knowing:

- **A clean tree is required.** A dirty tree would tag an image with a commit that doesn't contain the code, which is exactly what breaks rollback later. `--allow-dirty` overrides and tags `<sha>-dirty-<timestamp>` so it can never be mistaken for the commit.
- **Re-deploying an existing tag is refused** — moving a tag would silently change what a deployed revision means. Commit and deploy the new SHA, or `--rollback` to the revision already running it.
- **`cdk deploy GojoGoFargateStack` re-asserts the task definition** and would knock the service back to a mutable tag. `imageTag` is now a required prop (context-driven, defaulting to `latest` for a cold bootstrap), so pass the running one:
  ```
  cdk deploy GojoGoFargateStack -c imageTag=$(./scripts/deploy-backend.sh --current) \
    -c domainName=api.gojogo.app -c certificateArn=...
  ```
- **A failed deploy is not an outage.** `desiredCount 1` / `minHealthyPercent 100` means the new task must go healthy before the old drains, so a bad build (or a failed Flyway migration, which looks identical) stalls the rollout while the previous version keeps serving. The script times out at 10 minutes and prints the two commands that diagnose it, plus the rollback.

## Phase 2b · Milestone 5 — seller listing management (built + simulator-verified 2026-07-25, NOT deployed)

Selling was one-way: publish and hope. A seller could create a listing and delete it, and nothing else — no edit, no way to say "sold", and no sight of whether anyone was interested. This milestone is the seller's side of the marketplace: **"Your listings"**, reached from a `Selling N` chip in the Economy chrome (and from "Manage listing" on your own listing detail).

**The status model is the core of it.** `active BOOLEAN` couldn't express this: *paused* and *sold* are both "not in browse" but mean opposite things to the seller, and to a buyer who saved the item. So `V10__economy_listing_management.sql` adds `status VARCHAR(16)` (`ACTIVE` / `PAUSED` / `SOLD`, CHECK-constrained), `view_count`, and `updated_at`, backfilling status from `active`. **`active` is deliberately left in place**, unread by the new code — dropping it would break the tasks still serving traffic mid-roll, whose entity maps the column. It keeps `NOT NULL DEFAULT true`, so inserts from either version succeed; a later migration can drop it once nothing maps it.

Decisions worth keeping straight:

- **Browse filters on status, everywhere.** The repository queries switched from `active = true` to `status = ACTIVE`, and `EconomyView.catalog` filters client-side too. That second filter is what makes it safe to *seed* a paused or sold listing into the catalog — which `openListingContext` (a thread's listing card) and "View in marketplace" both have to do, because `ProductDetailView` resolves through `liveProduct(id:)`.
- **Editing is a full replacement.** `PUT` posts every field back, photos included, so a cleared description means cleared. Status is *not* in the edit form — pause/relist/mark-sold are row actions, which keeps a relist one tap instead of a form round-trip.
- **Views count buyers, not the seller.** `GET /listings/{id}` bumps `view_count` only when the viewer isn't the owner. The response carries the pre-bump number; the shelf re-reads its own via `/mine`.
- **Totals come from the server.** `/mine/stats` aggregates across *every* listing, so the tiles aren't limited to the page in hand. A stats failure can't take the shelf down — the tiles fall back to counting what loaded.
- **Status changes move optimistically and revert.** The segment a row lives in is the whole point of the tap, so it moves immediately; a refused call puts the row and the catalog back *and says so*.

**API surface** (all Bearer-authed, owner-only on the mutations):
- `PUT /v1/economy/listings/{id}` — full replacement → the updated listing (403 non-owner, 404 gone)
- `PUT /v1/economy/listings/{id}/status` `{status}` — ACTIVE / PAUSED / SOLD (400 on an unknown value)
- `GET /v1/economy/listings/mine/stats` → `{total, active, paused, sold, saves, views}`
- `GET /v1/economy/listings/mine` — unchanged, but now returns paused and sold listings too (it's the only place they appear), and every `ListingResponse` gained `status` / `viewCount` / `updatedAt`

**iOS** — new [SellerListingsView.swift](GojoGo/Screens/SellerListingsView.swift): stat tiles (live / saves / views / sold), status segments with counts, and a row per listing carrying price, a status pill, saves + views, a one-tap primary action (Mark sold, or Relist when it's down), Edit, and an ellipsis menu (edit · view in marketplace · every other status · delete). Delete is alert-confirmed and says what makes it different from "sold". The edit form is the same sheet, swapped in with a transition — the pattern `DeliveryAddressSheet` already uses — with a multi-photo strip (upload to S3 first, cover badge on the first), title, price, category, condition, pickup area, and details. New `SellerListing` view model + `ListingStatus` enum in [EconomyModels.swift](GojoGo/Stores/EconomyModels.swift); shelf/edit/status wiring in [AppState+Economy.swift](GojoGo/Models/AppState+Economy.swift), which also reconciles all three surfaces a listing shows on (shelf, catalog, open detail) from the server's response.

**Forward-compatible with the un-rolled backend:** `status` and `viewCount` are optional-decoded (same convention as the presign `cacheControl` field), so the app runs against the currently-deployed jar — which is exactly how it was verified below.

**Verified (2026-07-25)** — backend `ModularityTests` green (Corretto 21, 1/1); iOS `xcodebuild -sdk iphonesimulator` → BUILD SUCCEEDED. **Simulator pass on the live (pre-V10) backend**, which doubles as the forward-compat test: signed in → Economy showed the `Selling` chip → the empty shelf rendered (0/0/0/0 + "Nothing listed yet") → published *Leica M6 rangefinder / $1,200* against prod → the chip became **`Selling 1`** and the shelf showed the row (LIVE pill, "Listed just now", 0 saves · 0 views) with the stat tiles at Live 1 → the edit form opened pre-filled, price round-tripped from cents as `1200` → "Mark sold" against the missing route **reverted the row to LIVE, left the counts untouched, and surfaced the failure banner** — the optimistic-rollback path, confirmed by a real failure rather than a mock.

**Two bugs this pass caught and fixed:** the notice banner rendered only in `EconomyView`, i.e. *behind* the seller sheet, so a refused edit failed silently — the sheet now renders its own; and it overlapped the header and stat tiles, so it's in the layout rather than over it. Also added `listingMessage(from:fallback:)`, which suppresses a 404 body — a route miss or a deleted listing otherwise showed the seller raw Spring text ("No static resource v1/economy/listings/…").

**Not covered / deferred:** photo *reordering* (you can add and remove; the first is the cover); no "price dropped" notification to people who saved the listing (`SOLD` would be a natural `notifications` consumer, alongside the existing `ListingCreated`); and the shelf is a single 100-item fetch with client-side filtering — fine now, but a seller past that needs the paged, server-filtered `/mine`.

**To deploy:** V10 is non-destructive (adds columns, backfills, leaves `active`), so it's the standard roll — push the image, then
```bash
aws ecs update-service --cluster gojogo --service gojogo-backend --force-new-deployment --region us-east-1
```
The mutation endpoints (`PUT …/{id}`, `PUT …/{id}/status`, `GET …/mine/stats`) are **unverified against a real backend** — they 404 until this lands. A two-user curl E2E in the style of the earlier 2b milestones should follow the deploy: owner edits, non-owner gets 403, status round-trip ACTIVE→SOLD→ACTIVE, sold listing absent from browse but present in `/mine` and `/saved`, view count bumping for a non-owner and not for the owner.

## Phase 2c — Full Instagram stories (built + simulator-verified 2026-07-25, NOT deployed)

Stories existed since Phase 1 M2 but were a stub: one image URL per frame, a 24h expiry, and a seen flag. This slice builds the actual product. It stays entirely inside the `social` module — no new AWS infra, no new module, and it reuses `media` presign for every upload.

**The one product decision worth recording.** A story reply is *not* routed into a My World DM. My World is a separate, phone-verified identity with its own profile (and will get its own stories), so a reply to a *social* story landing in a My World thread would cross two identities that the app deliberately keeps apart. Replies are therefore **story comments owned by `social`**, read back with Instagram's privacy: the frame's author sees every reply, any other viewer sees only the ones they sent. It's a real row in `social.story_comment`, so making replies public later is a change to one query, not a migration.

**Schema — four migrations.**
- `V11__story_media.sql` — `story_frame` gains `media_type` (IMAGE/VIDEO/TEXT), `video_url`, `duration_ms`, `caption`, `overlays_json`, `background`, `audience`, `deleted_at`; `image_url` drops NOT NULL (a text card has no media) and a CHECK enforces "the right media for the type" instead. `story_view` gains `viewed_at` (the viewers list is ordered by it). **Deletion is soft** — a highlight keeps a frame alive past its expiry and `story_view` cascades, so a hard delete would silently take the seen-state and the viewers list with it.
- `V12__story_engagement.sql` — `story_reaction` (PK frame+viewer, so a second emoji replaces the first), `story_comment`, `story_mute` (its own table, not a flag on `follow`: you can mute someone you don't follow, and an unfollow/refollow shouldn't silently un-mute them).
- `V13__story_notifications.sql` — `notification.story_frame_id`, because a story notification points at a frame, not a post.
- `V14__story_highlights.sql` — `close_friend` (one-directional, indexed both ways since rings asks "whose list am I on?"), `story_highlight`, `story_highlight_frame`.

**API** (all under the existing auth): `GET /v1/stories` (rings — now ordered you → unseen → seen → muted, with viewer/reply counts on your own frames only) · `POST /v1/stories` (frame specs; **still accepts the old `frameImageUrls` body** so an app build from before this roll keeps posting) · `POST /v1/stories/frames/{id}/seen` · `DELETE /v1/stories/frames/{id}` · `PUT|DELETE /v1/stories/frames/{id}/reaction` · `GET|POST /v1/stories/frames/{id}/replies` · `DELETE /v1/stories/replies/{id}` · `GET /v1/stories/frames/{id}/viewers` (owner-only) · `POST|DELETE /v1/stories/mute/{profileId}` · `GET /v1/stories/archive` · `GET|POST|PUT|DELETE /v1/stories/highlights[/{id}]` · `GET|PUT /v1/stories/close-friends`.

**Module boundary.** `social` publishes `StoryReacted` / `StoryReplied`; `notifications` consumes both (its third and fourth event contract) into activity rows plus an APNs alert. `ModularityTests` green — no new cross-module reach.

**Overlays are a spec, never burned in.** Text and stickers are stored as normalized JSON (position 0…1 of the canvas, font size as a fraction of its width) and rendered live at view time. Flattening them into the image was the alternative, but a video frame can't be flattened without re-encoding it — one render path for all three kinds beats two. The backend treats `overlays_json` as opaque, the same way `messaging.ConversationContext` is opaque to messaging.

**iOS** — new `StoriesStore` (split out of `SocialStore`, which was about to double), `AppState+Stories.swift`, `StoryModels.swift`, and screens: `StoryComposer` (gallery / camera / text card, draggable-pinchable-rotatable overlays, audience toggle), `StoryCanvas` (the shared renderer — the composer previews the *actual* thing the viewer plays), a rewritten `StoryViewer` (video, overlays, reply bar, reaction row, "Seen by", owner menu), `StoryInsightsSheet`, `StoryArchiveView` + highlight editor/picker, `CloseFriendsView`. Highlights render on `ProfileView`; the Home rail and browser gained a close-friends badge and mute on long-press.

**Two things worth knowing about the design.** Text-card backgrounds are **tonal, not colorful** — the app's palette is monochrome by design (`GGColor`), so Instagram's rainbow gradients would have been the only saturated surface in the product; same reason the close-friends marker is a glyph rather than a green ring. Say the word if you want real color here and it's a one-file change (`StoryBackground`).

**Verified (2026-07-25)** — backend compiles + `ModularityTests` green on Corretto 21; iOS `xcodebuild -sdk iphonesimulator` → BUILD SUCCEEDED; simulator pass on the **live pre-V11 backend**: the composer opens from Home and the browser, the text card renders and auto-sizes live, the audience toggle flips, and Archive / Close friends open with their empty states. Posting correctly **failed and rolled back with a notice** — the old backend rejects the new body, which is exactly the intended path and also proves the optimistic-insert revert. Fixed during that pass: source-button labels wrapped at 402pt, and the archive/close-friends/composer sheets couldn't present while the stories browser sheet was up (they now declare their own copies, the same way `ProfileView` already does for the post viewer).

### Music on a story

Sound is a **platform** capability, not a story feature — hence a new `com.gojogo.music` module (`music` schema, `V15`) rather than a column on `story_frame`. Shorts and posts are the obvious next consumers; stories are just the first.

- `GET /v1/music/tracks?q=&limit=` — trending (hand `trending_rank` first, then `use_count`) when `q` is blank, otherwise a title/artist match · `GET /v1/music/tracks/{id}`.
- Public `MusicApi` (`find` / `recordUse`) is the only way `social` touches the catalog — the same seam `economy → MessagingApi` uses. `ModularityTests` confirms it.
- `V16` adds a **snapshot** of the track to `story_frame` (`music_title`/`artist`/`artwork_url`/`audio_url` + the clip window), not a foreign key: no FK may cross a schema (ARCHITECTURE §4), a story must keep playing the sound it was posted with after a track is pulled, and drawing the music sticker must not need a cross-module read. A CHECK stops a half-populated snapshot.
- **The client sends only `musicTrackId` + the window.** Title, artist, artwork and audio URL are all resolved server-side, so a frame can't claim to be a song it isn't. The clip is clamped to ≤15s and to the track's real length.
- iOS: `MusicStore`, `MusicPickerSheet` (search + preview, then a waveform scrubber for the 15s window), `StoryMusicSticker`, and `StoryMusicController` (seeks to the clip start, loops on a boundary observer). A frame with a sound plays its **video muted** — two audio tracks at once is noise. A still carrying a sound holds the screen for the clip's length instead of 5s. The waveform is deterministic from the track id: real sample analysis would mean downloading and decoding the whole file just to draw a scrubber.

**Seeding the music catalog — your call, and a licensing one.** The table ships **empty** and there is deliberately **no ingest endpoint**: this app has no admin role, so a catalog writer would be unauthenticated. Upload an audio file through the existing media presign (or straight to S3), then insert the row:

```sql
INSERT INTO music.track (title, artist, artwork_url, audio_url, duration_ms, trending_rank)
VALUES ('Track title', 'Artist', 'https://…/artwork.jpg', 'https://…/audio.m4a', 214000, 1);
```

`is_active = false` pulls a track from search **without** breaking the stories that already carry its snapshot. Only add music you hold the rights to distribute — nothing in this code checks that, and the app is the distributor.

**Placeholder tracks are currently seeded (`V17`).** Four tracks by "GojoGo Sound" — `Night Drive`, `Casablanca Blue`, `Atlas Morning`, `Medina Late` — live in the catalog so the picker can be tested. They are **synthesised**: generated from sine/saw math with no source recording, sample pack or third-party audio anywhere in them, so there is nothing to license. Audio and cover art sit in the media bucket under `media/music/`. They sound like placeholder loops because that is what they are — replace them before anyone real sees the app:

```sql
UPDATE music.track SET is_active = false WHERE artist = 'GojoGo Sound';  -- hide
DELETE FROM music.track WHERE artist = 'GojoGo Sound';                   -- or drop
```

Dropping them is safe: no foreign key points at a track, and any story that used one keeps its own snapshot and goes on playing.

**Verified against a real backend (2026-07-25) — two-user E2E, 58/58 green.** Run on a **local Postgres 18** with all sixteen migrations applied from scratch (`V1`→`V16`, "Successfully applied 16 migrations… now at version v16") and the real Spring app booted against it, so Hibernate `ddl-auto: validate` accepted every new mapping — the `@Embedded` music snapshot, both enums, and all the V11–V14 columns. Auth used real Cognito tokens for the existing test users. Script: scratchpad `e2e_stories.sh`.

**The upgrade path was tested separately, which matters more than the fresh install** — prod already holds story rows, and `V11` alters that table. A second database was taken to `V10` (the shape prod is in today), seeded with legacy image-only frames and a `story_view` with no timestamp, and then `V11`→`V16` were applied over it: legacy frames come out `media_type=IMAGE` / `audience=ALL` / no music, the legacy view gets a backfilled `viewed_at`, all four new CHECK constraints apply cleanly against the existing rows, and a legacy row is still updatable afterwards (no CHECK trap on soft delete).

What it covers: the music catalog (trending order, search by artist, a pulled `is_active=false` track hidden from browse *and* rejected on attach) · frame creation for IMAGE/TEXT with per-kind 400s · **the legacy `frameImageUrls` body still mapping to an IMAGE frame**, which is what makes the rolling deploy safe · music snapshots resolved server-side (title/artist/audio URL come from the catalog, never the client) with the clip clamped to 15s *and* to a 9s track's real length · `viewerCount` present for the author and null for everyone else · seen-state not duplicating on a re-mark (the `existsById` guard) · reactions replacing rather than stacking, visible as `myReaction` only to the reactor · **reply privacy — the author reads both replies, B reads only their own** · close friends gating a restricted frame and *revoking* access when B is removed · mute flagging the ring, sorting it last, and leaving it reachable · a deleted frame leaving the ring while its highlight keeps playing (what the soft delete is for) · 403s for reading another author's viewers, deleting their frame, or highlighting it · the archive excluding deleted frames and being own-only.

**Deployed to prod and re-verified against it (2026-07-25).** The push to `main` auto-deployed via the Actions workflow — so the CI path works and the `iam:PassRole` grant is confirmed good. All sixteen migrations applied to prod on first boot. With the placeholder catalog seeded (below), the iOS surfaces that had never been exercised with real data were walked in the simulator **against prod**: the picker lists tracks with artwork streaming from S3, the clip scrubber drags and reports its window, the music sticker renders on the frame, and posting a story with a sound round-trips — a clip scrubbed to ~0:15 came back from `GET /v1/stories` as `startMs=15985, durationMs=15000`, with title/artist resolved server-side.

**Still unverified:** video story frames. The `mp4/mov` presign path is the one posts already use, but the story-specific poster → stream swap and the progress-driven bar have only run locally — a real video story has never been posted.

## Username change — 2-month cooldown with grace (deployed + verified 2026-07-23)

Users can change their `@handle` from **Edit profile → Username**. Policy: the **first two sets are free** (the onboarding pick + one grace change — e.g. to fix a typo), after which a change is allowed **once every 2 calendar months**. Enforced entirely server-side in the `profile` module (Flyway `V7` adds `handle_changed_at` + `handle_change_count` to `profile.user_profile`; no new AWS infra).

- **One central guard** (`ProfileService.applyHandleChange`) runs for **both** `PATCH /v1/profiles/me` and the dedicated `PUT /v1/profiles/me/handle` — so the cooldown can't be bypassed via PATCH. Rules: no-op if unchanged (doesn't consume a free set); free while `handle_change_count < 2`; after that requires `now ≥ handle_changed_at + 2 months`; target must be valid + un-taken. `409` taken / `429` cooldown (message carries the next-eligible date) / `400` too short. The auto-generated signup handle is not a user change (count starts 0).
- **Availability + status endpoints**: `handle-available` (format + case-insensitive not-taken-by-another, `reason` ok|taken|invalid|current) and `handle-status` (`canChangeNow` / `changeAvailableAt`) drive the iOS UI gate.
- **iOS** — [ChangeUsernameSheet](GojoGo/Screens/ChangeUsernameSheet.swift): debounced live availability (green available / red taken / neutral "current"), a cooldown banner + disabled field when gated, "Save username" → `AppState.changeUsername` (`PUT`, surfaces the backend 429/409 message). Wired into [EditProfileSheet](GojoGo/Screens/ActivityView.swift) (replaced the old "handle can't be changed in the prototype" placeholder). `ProfileStore.handleStatus/checkHandle/changeHandle` + DTOs added.

**Verified (2026-07-23)** — non-destructive prod E2E on user A (`verify_handle.sh`, session-local): availability check returns current/taken/invalid/ok correctly; change to a taken handle → **409**; free set #1 (change away) → 200, still `canChangeNow=true`; grace set #2 (change back, restores A) → 200, then `canChangeNow=false` with `changeAvailableAt` = +2 months; 3rd change → **429** (read-only reject, A unchanged); no-op PUT of the current handle → 200 (not rate-limited); A's handle restored to `gojogom1test` at the end (A's `handle_change_count` is now 2, so A is gated until 2026-09-23 — a real test-data side effect, harmless to other flows).

## Incidents & fixes log

- **A left 1:1 could never be reopened (2026-07-24, found by the M4 E2E, pre-existing since Phase 2 M1):** `DELETE /v1/conversations/{id}` deletes the caller's membership row, but nothing rewrites the `DIRECT#{a}#{b}` dedupe pointer. The next `POST /v1/conversations` for that pair resolved the pointer to the dead thread and then `orElseThrow`'d on the missing membership → **500 "Membership missing"**, permanently, for that pair. A quieter second half: the per-send membership bump is a DynamoDB `Update`, which *recreates* a deleted membership item — but only with the attributes in the expression, so the resurrected row had no `convId` (unreadable: NPE in `readMembership`) and no `gsi1pk` (invisible to the `gsi1` list query). Messages sent to someone who had left went nowhere. **Fixed** in [MessagingService.createConversation](backend/src/main/java/com/gojogo/messaging/internal/MessagingService.java) (reuse the pointer only when the conversation still exists *and* still lists the caller; otherwise create fresh and overwrite it; a caller with no membership row is rejoined via `repo.rejoin`) and [MessagingRepository.appendMessage](backend/src/main/java/com/gojogo/messaging/internal/MessagingRepository.java) (the bump re-states `convId` + `gsi1pk` every time). Re-verified: both leave → re-create returns the thread → A's list has it → A sends → **B's list gets the row back** with the new preview. **Lesson:** in a single-table design a dedupe pointer is a second source of truth — validate what it resolves to; and a DynamoDB `Update` is an upsert, so any expression that can run against a deleted item must write enough to leave a *valid, index-visible* item.

- **Economy save-count double-bump (2026-07-23, caught in the first E2E, fixed before sign-off):** `ListingService.save` used `saveAndFlush(new SavedListing(...))` in a `try/catch (DataIntegrityViolationException)` to be idempotent, then `bumpSaveCount(+1)`. But `SavedListing` (like `PostLike`/`PostBookmark`/`CommentLike`) uses an `@IdClass` with **assigned** (non-generated) ids, so Spring Data `save()` runs a JPA **merge** (select-then-update), *not* a persist/insert — a duplicate save never throws, silently UPDATEs the row, and the count bumps again (E2E showed `save_count`=2 after two saves). **Fixed** by guarding on `saves.existsById(new SavedListing.Key(...))` before the save+bump (try/catch kept only as a concurrent-insert backstop). Re-verified 3× save → count 1. **Lesson:** for assigned-id join entities, don't rely on a duplicate-key exception for idempotency — check existence first. The **same latent bug exists in `social`** (`PostService.like`/`bookmark`, `CommentService.like`) — flagged as a separate task (pre-existing; the double-like count case was never exercised).

- **Notifications deploy (2026-07-23):** first roll **auto-rolled-back** — startup `ConflictingBeanDefinitionException`: both `messaging.internal.CurrentProfile` and `notifications.internal.CurrentProfile` took the default bean name `currentProfile`. Neither `mvn compile` nor the `ModularityTests` boot the full Spring context, so it only surfaced at runtime; App Runner's health check caught it and rolled back to the prior image (no downtime — `/v1/world/*` kept serving). Fixed by renaming to `NotificationCurrentProfile`. **Lesson:** two `@Component`s with the same simple class name across modules collide; keep bean class names unique (or set an explicit `@Component("name")`).

- **Social sign-in deploy (2026-07-23):** first `cdk deploy GojoGoAuthStack` failed with a **circular dependency** — the pool referenced the trigger Lambda (`lambdaTriggers`) while `userPool.grant(lambda, …)` put the pool's generated ARN in the Lambda's role policy. Fixed by scoping that grant to a static `arn:aws:cognito-idp:<region>:<account>:userpool/*` ([auth-stack.ts](infra/lib/auth-stack.ts)) instead of `userPool.userPoolArn` (the PreSignUp Lambda reads the real pool id from the trigger event anyway). Redeployed clean. The app-client updated in place (id preserved). App Runner service update took ~4.5 min.

- **M3 session:** CloudFront distribution creation is blocked — **the AWS account is unverified for CloudFront** (new-account restriction; only AWS Support can lift it). Interim: media served public-read directly from S3. When support verifies the account, flip `ENABLE_CLOUDFRONT = true` in [media-stack.ts](infra/lib/media-stack.ts) and redeploy `GojoGoMediaStack` + `GojoGoAppStack` — URLs keep their paths, only the domain changes. Also: a CDK env-var update to the App Runner service did **not** re-pull `:latest` — after pushing a new image, always run `aws apprunner start-deployment` even if a CFN update just deployed.

- **M2 session:** an interrupted `cdk deploy` had left `GojoGoAppStack` as a `REVIEW_IN_PROGRESS` shell with the App Runner service deleted — fixed by deleting the stack shell and redeploying (service URL changed as a result). Spring Data derived `deleteBy…` methods on `@IdClass` entities threw `ClassCastException` in prod — replaced with explicit `@Modifying @Query` deletes ([Repositories.java](backend/src/main/java/com/gojogo/social/internal/Repositories.java)).
- **Private networking attempt (user, reverted):** App Runner VPC egress routes *all* outbound traffic through the VPC, so an isolated VPC broke Cognito JWT validation. Real fix needs a NAT Gateway (~$32–35/mo) — deferred to the ECS/Fargate migration.

## Known issues / dev shortcuts to revisit

- **RDS publicly accessible** (5432 open, password-protected) — **Phase 1 of the private-networking migration is deployed; Phase 2 is blocked on an IAM policy update only you (admin/root) can apply**, then a staged deploy replaces the DB + starts the ~$33/mo NAT. Full runbook: [infra/PRIVATE_RDS_MIGRATION.md](infra/PRIVATE_RDS_MIGRATION.md).
- **GitHub Actions workflow untested** — needs repo secrets `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`. Manual deploy: `cd backend && mvn -B -DskipTests compile jib:build -Djib.image=578109959809.dkr.ecr.us-east-1.amazonaws.com/gojogo-backend:latest -Djib.to.auth.username=AWS -Djib.to.auth.password="$(aws ecr get-login-password --region us-east-1)"` then `aws apprunner start-deployment --service-arn <arn above>`.
- **Signup requires `admin-confirm-sign-up`** or emailed code — decide UX before launch.
- Feed `following` decoration loads the full followee id set per request — **now loaded once** per feed request (was twice: `feed` + `decorate`; deduped 2026-07-24). Still an in-memory set per request; cache/join if the followee count ever gets large.
- App Runner bills ~24/7 (~$25/mo with RDS); `aws apprunner pause-service` when idle.
- **Account linking is one-directional** (email → federated). The Lambda links a *new* Google/Apple sign-in to an *existing* email user. The reverse — someone who used **Google first** and later tries to **self-sign-up with email/password** on the same address — still hits the email-alias uniqueness and fails at sign-up (they should keep using Google). **Deployed 2026-07-23 (`GojoGoAuthStack`), pending behavioral E2E:** a `PreSignUp_SignUp` handler in [auth-triggers/index.mjs](infra/lambda/auth-triggers/index.mjs) now detects the pre-existing federated user and returns a clear "continue with Google/Apple" message instead of an opaque Cognito failure (it can't silently merge — a native password can't be attached to a federation-only user from a trigger). **To test:** Google-first-then-email-signup on device; confirm the message renders in `CognitoAuthClient`. Still open by design: if Apple withholds the email (private-relay off), that Apple identity gets a synthetic `@appleid.gojogo` username and won't link to a real-email account.
- **Media is served straight from S3** (public-read on `media/*`) until AWS Support verifies the account for CloudFront — see incidents log. **Orphan cleanup — deployed 2026-07-23 (`GojoGoAppStack` + backend image; V5 migration applied, health UP), running report-only:** presigned keys are now tracked in `media.upload_object` ([V5 migration](backend/src/main/resources/db/migration/V5__media_uploads.sql)); modules call `MediaApi.markReferenced` when they persist a URL (posts, stories, message attachments, social + World avatars); [MediaCleanupJob](backend/src/main/java/com/gojogo/media/internal/MediaCleanupJob.java) sweeps daily at 03:30 UTC. Live env `MEDIA_CLEANUP_DELETE=false` → it logs the orphans it *would* delete and removes nothing. **To enable deletion:** after the daily sweep, check App Runner logs for `Media orphan sweep (report-only)` and confirm no in-use media is flagged, then set `MEDIA_CLEANUP_DELETE=true`. Note: pre-V5 uploads aren't tracked, so they're never flagged or deleted (conservative).
- **My World OTP has a dev bypass code** `WORLD_OTP_DEV_CODE=424242` (App Runner env, set in [app-stack.ts](infra/lib/app-stack.ts)) that verifies any number without a real SMS — because SNS SMS is almost certainly still in the account's **sandbox** (only verified destination numbers, ~$1/mo cap). Real delivery needs SNS SMS production access (AWS Support) + a registered origination/sender id; then **clear `WORLD_OTP_DEV_CODE`** before launch. The World profile is separate from the social profile by design (WhatsApp model).
- **Marketplace test-data cleanup is an opt-in endpoint** — `GET /v1/economy/admin/listings` and `POST /v1/economy/admin/listings/purge` ([EconomyAdminController](backend/src/main/java/com/gojogo/economy/internal/EconomyAdminController.java)) list and delete listings for clearing test data. They sit **outside the JWT chain** (one curl, no user token) and guard themselves with the `X-Economy-Admin-Token` header against `ECONOMY_ADMIN_TOKEN`; with no token — the deployed default, since [fargate-stack.ts](infra/lib/fargate-stack.ts) sets it to `''` unless `-c economyAdminToken=…` is passed — every path under `/v1/economy/admin` 404s. **Enable only for the deploy that does the wipe, then deploy again without the flag** (a plain deploy turns it back off on its own). Purge takes the listing's photos and saves with it via `ON DELETE CASCADE`; the S3 images are left to MediaCleanupJob's orphan sweep.
- **~~Simulator MCP panel blocked~~ (resolved)**: `xcode-select` now points at Xcode 26.2; the app builds via `xcodebuild`. Original note: `xcode-select` doesn't point at Xcode — fix with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` (needs user password).
- All milestone work is committed locally; push to GitHub when ready (`git push`).

## To resume in a new session

**Phase 2 is complete and deployed** — M1 (My World messaging + setup), M2 (notifications), M3 (APNs push + reply/typing/send-later polish), M4 (chat attachments + socket resilience), M5 (chat-message push + persisted read receipts). APNs is activated (key in Secrets Manager, verified against Apple for both activity-feed *and* chat pushes); only a physical-device test remains (enable Push on the App ID, run on a device). **Phase 2b is under way** — M1 (economy marketplace), M2 (seller chat over the messaging API), M3 (listing context on the thread), and M4 (delivery vertical) are live.

**Next 2b slices, in the order they make sense:**
1. **Stripe + Connect checkout + a `payments` ledger** — needs your Stripe account and keys (user action) before anything can be built past the ledger schema. Two things now hang off it: the M3 conversation `ConversationContext` (kind/refId) for a marketplace sale, and the M4 delivery order, which is currently placed without any payment step.
2. **Order push notifications** — `delivery.OrderStatusChanged` is published on every transition and has no consumer; `notifications` already consumes `messaging.MessageSent` the same way, so "your food is on the way" is a small, self-contained slice.
3. **OpenSearch consumer of `ListingCreated`** — a cost decision (an OpenSearch domain is ~$25+/mo on top of current spend), so it's your call whether it happens in 2b or waits.
4. **Listing-context polish** — carry the card onto the conversation-list row too (M3 only shows it inside the open thread), and fan out a live socket update when the card is refreshed on reuse (the seller currently learns it on next fetch).
5. **Merchant onboarding (`partner`)** — now the blocker for delivery being usable at all: the demo catalog was deleted on 2026-07-25, so GojoDelivery is empty until real restaurants can sign up (or an admin surface can add them). Everything downstream of a merchant — menus, orders, fulfilment, saved addresses — is already live.
6. **Delivery follow-ons** — item options/extras, address autocomplete / map-pin picking, and live courier geo (that one waits for Phase 3 `dispatch`).

Also consider swapping the My World OTP to Twilio/Vonage Verify before going live (SMS provider options discussed 2026-07-23). Outstanding user-only actions: add `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` GitHub repo secrets (untested deploy workflow), ask AWS Support to verify the account for CloudFront, enable Push on the App ID + test on a device.

**On-device / simulator check still pending (except 2b M4)** — 2b M4's delivery loop *was* driven in the simulator against prod (see its section). Every other slice is verified by build + prod curl (and a Node WebSocket client for fan-out), and those SwiftUI live paths have still never been exercised in a running app: My World live threads replacing SampleData, socket-driven UI updates, the new attachment surfaces (hold-to-record, sticker keyboard, camera, location permission), the Economy → seller-chat hand-off, and the M3 listing-context card + its tap-through to the listing detail. Worth a simulator pass with two signed-in identities — note the camera and the system sticker keyboard need a **real device**, and the Simulator falls back to the photo library by design.
