# GojoGo — Build Progress

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full architecture and milestone plan. This file tracks what's actually done.

## ⚠️ Needs YOU (things Claude can't do — external accounts, devices, money, policy)

These are the only open items that require you personally; everything else in Phase 1–2 is built + deployed + verified.

1. **APNs device test** — enable the **Push Notifications** capability on App ID `com.gojo.gojogo` (Apple Developer portal), then run the app on a **physical iPhone** to confirm a real push arrives. (Backend + key are done and verified against Apple.) Note: `APNS_PRODUCTION` is currently `true` in [app-stack.ts](infra/lib/app-stack.ts) — that's for TestFlight/App Store builds; a plain Xcode dev build mints a **sandbox** token, so use `false` for dev-device testing (redeploy `GojoGoAppStack`).
2. **CloudFront** — the AWS account is unverified for CloudFront; only AWS Support can lift it. Until then media is public-read from S3. (Flip `ENABLE_CLOUDFRONT` in media-stack when verified.)
3. **Real SMS OTP** — SNS SMS is in the account sandbox (only verified numbers). Get SNS SMS production access (AWS Support) + a sender id, or swap to Twilio/Vonage Verify. Then **clear `WORLD_OTP_DEV_CODE`** (currently `424242`) before launch.
4. **CI deploy** — add `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` GitHub repo secrets (the Actions workflow is untested).
5. **Cost/scaling decisions** — RDS is publicly reachable (a NAT Gateway ~$32/mo removes that); App Runner bills ~24/7 (`aws apprunner pause-service` when idle). Your call.
6. **Git** — nothing has been committed this session; commit when you're happy.

Rare/edge (decide if you care): account-linking is one-directional (Google-first → later email self-signup on the same address fails) and orphaned media uploads are never cleaned up — **both now have code pending live verification** (see Known issues): a clearer `PreSignUp_SignUp` error, and a report-only orphan sweep with reference tracking.

## Environment — ready

- **AWS account:** `578109959809`, region `us-east-1`
- **IAM user:** `gojogo-builder`, policy `GojoGoMilestone1Policy` at **v6** ([iam-policy-milestone1.json](iam-policy-milestone1.json) tracks it: v3–v4 added CDK bootstrap/lookup + App Runner SLR perms; v5–v6 added Secrets Manager on `gojogo/*`, CloudWatch Logs read on `/aws/apprunner/*`, VPC-creation perms from the reverted private-networking attempt)
- **Local tools:** Java 23, Maven 3.9.16, AWS CLI 2.36.5, CDK 2.1132.0 (`~/.npm-global/bin/cdk` — may need `export PATH="$HOME/.npm-global/bin:$PATH"`)
- **CDK bootstrapped** in us-east-1

## Milestone status

- [x] **Milestone 1 — Backend skeleton + auth** ✅
- [x] **Milestone 2 — Profiles + social API** ✅
- [x] **Milestone 3 — Media upload** ✅ (CloudFront deferred — see known issues)
- [x] **Milestone 4 — iOS wiring** ✅ auth/feed/social/profile/media wired to the live backend; verified in simulator
- [x] **Milestone 5 — Buffer / hardening** ✅ — **Phase 1 complete.**
- [x] **Phase 2 · Milestone 3 — APNs push + messaging polish** ✅ **deployed + verified, APNs ACTIVATED (2026-07-23)** — Apple push key (`.p8`, Key ID `9W7A69BV93`) loaded from Secrets Manager; verified the backend authenticates to Apple (a fake token returned `400 BadDeviceToken`, not `403 InvalidProviderToken`). Only a **physical-device test** remains (needs the Push capability on the App ID + a real device to mint a token). Messaging polish fully live + verified — reply-to linking, outbound typing, **send-later over the wire**, **World-name reply snippets**, **backend group creation**, live video poster upload. Plus audit fixes: **profile edits now sync to the backend** and **avatar upload UI** wired. See the Phase 2 M3 section below.
- [x] **Phase 2 · Milestone 2 — Notifications (activity feed)** ✅ **deployed + verified (2026-07-23)** — `notifications` module (first consumer of the social domain events) persists follow/like/comment activity; `ActivityView` wired off SampleData. Two-user E2E green. See the Phase 2 M2 section below.
- [x] **Phase 2 · Milestone 1 — My World messaging** ✅ **deployed + verified (2026-07-23)** — backend `messaging` module + `GojoGoMessagingStack` (DynamoDB + WebSocket API) + WS Lambdas + full iOS wiring. Two-user curl E2E green (create/dedupe, send, unread/preview, read, react, poll create+vote, 404 boundary) and the real-time WebSocket fan-out verified (B's socket received A's message live). See the Phase 2 section below.

## Milestone 5 additions

- Backend: `@RestControllerAdvice` for consistent `{"message"}` error bodies (+ `server.error.include-message: always`); `GET /v1/profiles/by-handle/{handle}` profile view lookup. Deployed + verified (error shapes, by-handle, cursor pagination).
- iOS: feed pagination (keyset cursor, loads more near the list bottom), pull-to-refresh on Home, loading spinner on first feed load, own-profile counts refresh on open, profile-by-handle fallback when the local id map misses. Verified in simulator incl. keychain session restore.

## What's deployed

| Thing | Value |
|---|---|
| API base URL | `https://f6kp8hx2j2.us-east-1.awsapprunner.com` (**changed** when the service was recreated) |
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
- `GET /v1/profiles/{id}` — profile view with postCount/followerCount/followingCount/isOwn/following
- `GET /v1/profiles/{id}/posts` · `POST|DELETE /v1/profiles/{id}/follow`
- `GET /v1/feed?before=<ISO8601>&limit=` — keyset-paginated; following+own, falls back to global recency when following no one; `nextBefore` cursor
- `POST /v1/posts` (text and/or ≤10 mediaItems `{imageUrl,videoUrl}`, imageAspect) · `GET|DELETE /v1/posts/{id}`
- `POST|DELETE /v1/posts/{id}/like` · `POST|DELETE /v1/posts/{id}/bookmark`
- `GET|POST /v1/posts/{id}/comments` · `POST|DELETE /v1/comments/{id}/like`
- `GET /v1/stories` (rings, own first, 24h expiry, per-viewer seen state) · `POST /v1/stories` (≤10 frameImageUrls) · `POST /v1/stories/frames/{id}/seen`
- `POST /v1/media/presign` `{contentType}` → `{uploadUrl, key, publicUrl, expiresSeconds}` — client PUTs bytes to `uploadUrl` (S3-direct, 15-min expiry, content-type enforced: jpeg/png/webp/heic/gif/mp4/mov → else 415), then references `publicUrl` in posts/stories/avatarUrl

Domain events published in-process (`com.gojogo.social`): `PostCreated`, `UserFollowed`, and (added in Phase 2 M2) `PostLiked`, `PostCommented`. **First consumer:** the `notifications` module (see Phase 2 M2). It consumes via plain `@TransactionalEventListener(AFTER_COMMIT)` + `@Transactional(REQUIRES_NEW)` — deliberately *not* the durable Modulith registry (`starter-jpa` + `event_publication` table), which stays a later upgrade if at-least-once delivery across crashes is needed. `PostCreated` still has no consumer (search comes later).

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

## Incidents & fixes log

- **Notifications deploy (2026-07-23):** first roll **auto-rolled-back** — startup `ConflictingBeanDefinitionException`: both `messaging.internal.CurrentProfile` and `notifications.internal.CurrentProfile` took the default bean name `currentProfile`. Neither `mvn compile` nor the `ModularityTests` boot the full Spring context, so it only surfaced at runtime; App Runner's health check caught it and rolled back to the prior image (no downtime — `/v1/world/*` kept serving). Fixed by renaming to `NotificationCurrentProfile`. **Lesson:** two `@Component`s with the same simple class name across modules collide; keep bean class names unique (or set an explicit `@Component("name")`).

- **Social sign-in deploy (2026-07-23):** first `cdk deploy GojoGoAuthStack` failed with a **circular dependency** — the pool referenced the trigger Lambda (`lambdaTriggers`) while `userPool.grant(lambda, …)` put the pool's generated ARN in the Lambda's role policy. Fixed by scoping that grant to a static `arn:aws:cognito-idp:<region>:<account>:userpool/*` ([auth-stack.ts](infra/lib/auth-stack.ts)) instead of `userPool.userPoolArn` (the PreSignUp Lambda reads the real pool id from the trigger event anyway). Redeployed clean. The app-client updated in place (id preserved). App Runner service update took ~4.5 min.

- **M3 session:** CloudFront distribution creation is blocked — **the AWS account is unverified for CloudFront** (new-account restriction; only AWS Support can lift it). Interim: media served public-read directly from S3. When support verifies the account, flip `ENABLE_CLOUDFRONT = true` in [media-stack.ts](infra/lib/media-stack.ts) and redeploy `GojoGoMediaStack` + `GojoGoAppStack` — URLs keep their paths, only the domain changes. Also: a CDK env-var update to the App Runner service did **not** re-pull `:latest` — after pushing a new image, always run `aws apprunner start-deployment` even if a CFN update just deployed.

- **M2 session:** an interrupted `cdk deploy` had left `GojoGoAppStack` as a `REVIEW_IN_PROGRESS` shell with the App Runner service deleted — fixed by deleting the stack shell and redeploying (service URL changed as a result). Spring Data derived `deleteBy…` methods on `@IdClass` entities threw `ClassCastException` in prod — replaced with explicit `@Modifying @Query` deletes ([Repositories.java](backend/src/main/java/com/gojogo/social/internal/Repositories.java)).
- **Private networking attempt (user, reverted):** App Runner VPC egress routes *all* outbound traffic through the VPC, so an isolated VPC broke Cognito JWT validation. Real fix needs a NAT Gateway (~$32–35/mo) — deferred to the ECS/Fargate migration.

## Known issues / dev shortcuts to revisit

- **RDS publicly accessible** (5432 open, password-protected) — see NAT note above.
- **GitHub Actions workflow untested** — needs repo secrets `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`. Manual deploy: `cd backend && mvn -B -DskipTests compile jib:build -Djib.image=578109959809.dkr.ecr.us-east-1.amazonaws.com/gojogo-backend:latest -Djib.to.auth.username=AWS -Djib.to.auth.password="$(aws ecr get-login-password --region us-east-1)"` then `aws apprunner start-deployment --service-arn <arn above>`.
- **Signup requires `admin-confirm-sign-up`** or emailed code — decide UX before launch.
- Feed `following` decoration loads the full followee id set per request — fine now, cache/join later.
- App Runner bills ~24/7 (~$25/mo with RDS); `aws apprunner pause-service` when idle.
- **Account linking is one-directional** (email → federated). The Lambda links a *new* Google/Apple sign-in to an *existing* email user. The reverse — someone who used **Google first** and later tries to **self-sign-up with email/password** on the same address — still hits the email-alias uniqueness and fails at sign-up (they should keep using Google). **Code added, pending live verification:** a `PreSignUp_SignUp` handler in [auth-triggers/index.mjs](infra/lambda/auth-triggers/index.mjs) now detects the pre-existing federated user and returns a clear "continue with Google/Apple" message instead of an opaque Cognito failure (it can't silently merge — a native password can't be attached to a federation-only user from a trigger). **To ship:** `cdk deploy GojoGoAuthStack`, then E2E-test Google-first-then-email-signup on device and confirm the message renders in `CognitoAuthClient`. Still open by design: if Apple withholds the email (private-relay off), that Apple identity gets a synthetic `@appleid.gojogo` username and won't link to a real-email account.
- **Media is served straight from S3** (public-read on `media/*`) until AWS Support verifies the account for CloudFront — see incidents log. **Orphan cleanup — code added, pending live verification:** presigned keys are now tracked in `media.upload_object` ([V5 migration](backend/src/main/resources/db/migration/V5__media_uploads.sql)); modules call `MediaApi.markReferenced` when they persist a URL (posts, stories, message attachments, social + World avatars); [MediaCleanupJob](backend/src/main/java/com/gojogo/media/internal/MediaCleanupJob.java) sweeps daily. **Ships report-only** (`MEDIA_CLEANUP_DELETE=false`): it logs the orphans it *would* delete and removes nothing. **To ship:** `cdk deploy GojoGoAppStack` (adds the S3 delete grant + env var), watch App Runner logs for `Media orphan sweep (report-only)` to confirm no in-use media is flagged, then set `MEDIA_CLEANUP_DELETE=true`. Note: pre-V5 uploads aren't tracked, so they're never flagged or deleted (conservative).
- **My World OTP has a dev bypass code** `WORLD_OTP_DEV_CODE=424242` (App Runner env, set in [app-stack.ts](infra/lib/app-stack.ts)) that verifies any number without a real SMS — because SNS SMS is almost certainly still in the account's **sandbox** (only verified destination numbers, ~$1/mo cap). Real delivery needs SNS SMS production access (AWS Support) + a registered origination/sender id; then **clear `WORLD_OTP_DEV_CODE`** before launch. The World profile is separate from the social profile by design (WhatsApp model).
- **~~Simulator MCP panel blocked~~ (resolved)**: `xcode-select` now points at Xcode 26.2; the app builds via `xcodebuild`. Original note: `xcode-select` doesn't point at Xcode — fix with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` (needs user password).
- All milestone work is committed locally; push to GitHub when ready (`git push`).

## To resume in a new session

Phase 2 · **Milestones 1 (My World messaging + setup), 2 (notifications), 3 (APNs push + reply/typing polish) are deployed.** APNs is activated (key in Secrets Manager, verified against Apple) — only a physical-device test remains (enable Push on the App ID, run on a device). Remaining messaging polish (deferred): true send-later (needs a scheduler), backend-backed group/circle creation UI, live video-attachment upload, World-name reply snippets. Then **Phase 2b commerce** (economy/delivery/Stripe). Consider swapping the My World OTP to Twilio/Vonage Verify when going live (SMS provider options discussed 2026-07-23). Outstanding user-only actions: add `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` GitHub repo secrets (untested deploy workflow), ask AWS Support to verify the account for CloudFront. (`xcode-select` is now correctly pointed at Xcode 26.2 — the iOS app builds via `xcodebuild`; the live simulator MCP panel needs a booted simulator.)

**On-device / simulator My World check still pending** — the curl + Node WebSocket E2E passed, but the SwiftUI live path (real thread replacing SampleData in `MyWorldView`, `@handle`-start, socket-driven UI updates) hasn't been exercised in a running app. Worth a simulator pass next session with two signed-in identities.
