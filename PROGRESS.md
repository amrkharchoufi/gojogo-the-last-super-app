# GojoGo — Build Progress

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full architecture and milestone plan. This file tracks what's actually done.

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
- [x] **Milestone 5 — Buffer / hardening** ✅ — **Phase 1 complete.** Next: Phase 2 (realtime + commerce, see ARCHITECTURE.md §8) when budget is topped up.

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

## API surface (all require `Authorization: Bearer <Cognito ID token>` except health)

- `GET /actuator/health` (public)
- `POST /v1/auth/session` — create-or-fetch profile; returns profileId/handle
- `GET|PATCH /v1/profiles/me` — own profile (displayName, handle, bio, category, birthYear, avatarUrl, interests; PATCH = null field means unchanged; 409 on taken handle)
- `GET /v1/profiles/{id}` — profile view with postCount/followerCount/followingCount/isOwn/following
- `GET /v1/profiles/{id}/posts` · `POST|DELETE /v1/profiles/{id}/follow`
- `GET /v1/feed?before=<ISO8601>&limit=` — keyset-paginated; following+own, falls back to global recency when following no one; `nextBefore` cursor
- `POST /v1/posts` (text and/or ≤10 mediaItems `{imageUrl,videoUrl}`, imageAspect) · `GET|DELETE /v1/posts/{id}`
- `POST|DELETE /v1/posts/{id}/like` · `POST|DELETE /v1/posts/{id}/bookmark`
- `GET|POST /v1/posts/{id}/comments` · `POST|DELETE /v1/comments/{id}/like`
- `GET /v1/stories` (rings, own first, 24h expiry, per-viewer seen state) · `POST /v1/stories` (≤10 frameImageUrls) · `POST /v1/stories/frames/{id}/seen`
- `POST /v1/media/presign` `{contentType}` → `{uploadUrl, key, publicUrl, expiresSeconds}` — client PUTs bytes to `uploadUrl` (S3-direct, 15-min expiry, content-type enforced: jpeg/png/webp/heic/gif/mp4/mov → else 415), then references `publicUrl` in posts/stories/avatarUrl

Domain events `PostCreated` and `UserFollowed` are published in-process (`com.gojogo.social`); no consumers yet by design. When the first consumer arrives, switch `spring-modulith-starter-core` → `starter-jpa` for the event publication registry (needs an `event_publication` table migration).

## Verified end-to-end (2026-07-22)

Two-user curl flow against prod: sign-up/sign-in both users → A updates profile → A posts (text + 2 media) → B follows A → B's feed shows A's post with author/following decoration → B likes + comments (counts bump) → B's profile view of A shows counts + following → A posts story, B sees ring, marks seen, seen-state sticks → B unfollows (fixed: was 500) → B's feed falls back to discovery. Test users: `gojogo-m1-test@example.com` (A), `gojogo-m2-bob@example.com` (B), password `TestPass123456!`, in the pool with real content rows in prod DB.

## iOS wiring (Milestone 4)

- **`GojoGo/CoreNetworking/`** — `BackendConfig` (deployed URLs/ids), `KeychainStore`, `CognitoAuthClient` (native sign-up/confirm/sign-in/refresh over Cognito's JSON API — no Amplify), `APIClient` (async/await, Bearer ID token, one retry on 401 via refresh token, presigned media upload), `APIModels` (typed DTOs; timestamps parsed via `BackendDate`, which trims the backend's nanosecond fractions).
- **`GojoGo/Stores/`** — `SocialStore` (feed/posts/likes/bookmarks/comments/follows/stories + DTO→UI-model mapping; server UUIDs are reused as UI model ids) and `ProfileStore` (session/me/update/views). `AuthSession` actor owns tokens.
- **AppState stays the façade** the views bind to; its social/profile/auth methods now sync to the API (optimistic UI, fire-and-forget with DEBUG logging) via [AppState+Backend.swift](GojoGo/Models/AppState+Backend.swift). On launch with keychain tokens: cached UI first, then live session + feed/stories replace the Home content (other tabs keep SampleData by design). A full @Published store split was deliberately deferred — views are too coupled to AppState to split cheaply; revisit when more domains go live.
- **Email auth flow**: [EmailSignUpView](GojoGo/Auth/EmailSignUpView.swift) = email+password → (new users) emailed 6-digit code → onboarding pushes displayName/handle/birthYear/interests via PATCH. Existing users skip onboarding (routed by whether the profile has a displayName). Apple/Google buttons currently route to the email flow.
- **DEBUG auto-login hook** for headless E2E: `SIMCTL_CHILD_GG_AUTOLOGIN_EMAIL` / `..._PASSWORD` env vars on `simctl launch` (DEBUG builds only).
- **Verified in simulator (2026-07-22)**: bob signs in → routed to onboarding (no displayName); Alice signs in → straight to Home showing the real feed incl. the M3 S3-hosted photo; own posts show no Follow chip; identity/counts from the live profile.
- **Gotchas learned**: simulator keychain survives app uninstall (`xcrun simctl keychain <udid> reset` between test identities); `URL.appendingPathComponent` percent-encodes `?` (feed query briefly 404'd — build URLs with `URL(string:relativeTo:)`).
- **Not yet wired**: pull-to-refresh/pagination on the feed, avatar upload UI, Apple/Google (Sign in with Apple), push, other tabs (Watch/Shorts/Economy/Travel/Delivery — still SampleData per plan).

## Incidents & fixes log

- **M3 session:** CloudFront distribution creation is blocked — **the AWS account is unverified for CloudFront** (new-account restriction; only AWS Support can lift it). Interim: media served public-read directly from S3. When support verifies the account, flip `ENABLE_CLOUDFRONT = true` in [media-stack.ts](infra/lib/media-stack.ts) and redeploy `GojoGoMediaStack` + `GojoGoAppStack` — URLs keep their paths, only the domain changes. Also: a CDK env-var update to the App Runner service did **not** re-pull `:latest` — after pushing a new image, always run `aws apprunner start-deployment` even if a CFN update just deployed.

- **M2 session:** an interrupted `cdk deploy` had left `GojoGoAppStack` as a `REVIEW_IN_PROGRESS` shell with the App Runner service deleted — fixed by deleting the stack shell and redeploying (service URL changed as a result). Spring Data derived `deleteBy…` methods on `@IdClass` entities threw `ClassCastException` in prod — replaced with explicit `@Modifying @Query` deletes ([Repositories.java](backend/src/main/java/com/gojogo/social/internal/Repositories.java)).
- **Private networking attempt (user, reverted):** App Runner VPC egress routes *all* outbound traffic through the VPC, so an isolated VPC broke Cognito JWT validation. Real fix needs a NAT Gateway (~$32–35/mo) — deferred to the ECS/Fargate migration.

## Known issues / dev shortcuts to revisit

- **RDS publicly accessible** (5432 open, password-protected) — see NAT note above.
- **GitHub Actions workflow untested** — needs repo secrets `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`. Manual deploy: `cd backend && mvn -B -DskipTests compile jib:build -Djib.image=578109959809.dkr.ecr.us-east-1.amazonaws.com/gojogo-backend:latest -Djib.to.auth.username=AWS -Djib.to.auth.password="$(aws ecr get-login-password --region us-east-1)"` then `aws apprunner start-deployment --service-arn <arn above>`.
- **Signup requires `admin-confirm-sign-up`** or emailed code — decide UX before launch.
- Feed `following` decoration loads the full followee id set per request — fine now, cache/join later.
- App Runner bills ~24/7 (~$25/mo with RDS); `aws apprunner pause-service` when idle.
- **Media is served straight from S3** (public-read on `media/*`) until AWS Support verifies the account for CloudFront — see incidents log. Uploaded objects are never listed or deleted yet (no cleanup of orphaned uploads).
- **Simulator MCP panel blocked**: `xcode-select` doesn't point at Xcode — fix with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` (needs user password).
- All milestone work is committed locally; push to GitHub when ready (`git push`).

## To resume in a new session

Say: *"Read PROGRESS.md and ARCHITECTURE.md, start Phase 2."* Everything needed is in those two files. Outstanding user-only actions: add `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` GitHub repo secrets (untested deploy workflow), ask AWS Support to verify the account for CloudFront, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` for the live simulator panel.
