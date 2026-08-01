# GoJoGo — Vision Gap Specs (missing logic, filled)

Companion to [ARCHITECTURE.md](ARCHITECTURE.md). That file owns boundaries + phase sequencing; this file owns the **detailed logic** each vision-driven milestone needs, written down *before* building so a milestone session starts from decisions, not questions. Everything here is GoJoGo-side; GoJoAdmin consumes these APIs per ARCHITECTURE §10b.

Conventions: money is integer **minor units** in a single platform currency (`PLATFORM_CURRENCY`, default config). Values marked **CONFIG** are server-side policy knobs (env/config table), never client constants. Defaults given are starting points, not commitments.

---

## 1. Money flows (payments / GoJo Wallet) — **BUILT 2026-07-31**

Refinements the build made to this spec (§11.4: update SPECS when a build refines it):
- **Card money always arrives as a wallet top-up**, never as a per-order card charge. The capture table below still holds — an order is charged at placement — but the charge is against the *wallet*, and the card only ever fills the wallet through a Stripe-hosted Checkout session. One payment path for every vertical to integrate, and no card data anywhere in this system.
- **The courier's delivery fee and tip settle to `PLATFORM`** under their own ledger kinds (`COURIER_FEE`, `TIP`) until Phase 4 M1 creates couriers. Phase 4 changes a payee, not a model.
- **A promotion is funded by the merchant**, free-delivery included — the discount always comes off the merchant's side of a settlement, so no campaign can reduce what the courier or the platform is paid.
- **Merchant balances and payouts live on the vertical's `/mine` surface**, not on payments' own REST: only the module that owns a payee can prove the caller owns it, and payments→delivery would be a dependency cycle. Phase 3's drivers arrive the same way.
- **Payouts debit first and transfer second, in two transactions.** A payout that paid out without debiting is unrecoverable; one that debited and failed is a FAILED row and a reversing entry.
- **Refunds of a settled order are not built.** Cancelling before delivery releases the hold (the money never left the customer's own escrow); a post-delivery refund is the dispute flow in §5, which is Phase 4. `REFUND` exists as a ledger kind and `WalletApi.refund` is implemented — nothing calls them yet.
- Buckets are as specified; `EXTERNAL` was added as a fifth owner kind and is the only account allowed a negative balance, since money arriving from outside has to come from somewhere for the entries to balance.


One `payments` schema, double-entry: every movement is a `ledger_entry` (id, idempotency key, debit account, credit account, amount, kind, ref kind/id, created). Accounts are `(user_id | merchant_id | PLATFORM, bucket)` with buckets `AVAILABLE`, `STAKING`, `TOKENS`, `REWARDS`, `ESCROW`. Balances are materialized per account and must equal the entry sum (verified by a nightly job).

**`WalletApi` (public):** `credit`, `debit`, `hold` (→ ESCROW), `release` (ESCROW → back), `capture` (ESCROW → payee), `transfer`, `balanceOf`. All idempotency-keyed; all refuse cross-currency. Verticals call this API only — no vertical touches Stripe.

**Stripe boundary:** external money in/out only. Card charge → ledger credit to the payer's flow (or direct capture); payout = Stripe Connect transfer mirrored as a ledger debit. Stripe is source of truth for charges; the ledger reconciles (webhook-driven). Connect accounts are attached at provisioning time for **every payee kind**: merchant (2e), driver, courier (Phase 3/4), seller, service provider (Phase 5).

**Capture model per transaction type:**

| Transaction | When charged | Escrow? | Settlement |
|---|---|---|---|
| Delivery / multi-merchant order | At placement (card or wallet) | Yes — held until `DELIVERED` | Capture splits: merchant sub-totals, courier fee, platform fee (fee policy), tip → courier 100% |
| Marketplace product | At placement | Yes — held until delivery confirmation (or auto-release after **CONFIG** 72h) | Seller minus platform fee |
| Digital product | At purchase | No — instant capture | Seller minus platform fee; entitlement granted atomically with capture |
| Ride | At completion (fare fixed at confirmation; stops re-quote) | No | Driver 100% of fare (token model, no commission); tip 100% |
| Service booking | Held at booking, captured at completion | Yes | Provider minus platform fee; cancellation fees per policy (§7) |
| Token pack | At purchase | No | Stripe → `TOKENS` credit at pack rate |
| Driver stake | At application | `STAKING` (locked) | KYC fee debited from stake; verification reward transferred from stake; remainder refundable **CONFIG** 30 days after account closure with no open disputes |

**Fees:** `payments.fee_policy` — per vertical: percentage bps + fixed minor units, effective-dated. Rides have fee 0 (tokens are the platform's revenue). **Refunds** reverse the original entries (partial allowed), Stripe refund mirrored. **Cash** (vision: "where available"): DEFERRED — spec'd as a `CASH` payment method that creates a courier/driver receivable ledger entry; do not build until a market needs it.

**Receipts:** the order/trip record *is* the receipt (API-rendered); PDF/download deferred to a later polish slice.

---

## 2. Ride lifecycle + fare negotiation (`travel`)

**Pricing engine (suggested fare):** `travel.pricing_config` per vehicle category: base + per-km + per-min (+ optional surge multiplier later, **CONFIG**). Distance/duration from the routing provider (§3). Suggested fare is advisory; the agreed fare is whatever negotiation lands on, floored at **CONFIG** min-fare.

**State machine (`travel.ride`):**

`DRAFT → REQUESTED → NEGOTIATING → CONFIRMED → ARRIVING → IN_TRIP → COMPLETED | CANCELLED_RIDER | CANCELLED_DRIVER | EXPIRED`

- **REQUESTED:** rider submits pickup, destination, category, and either accepts the suggested fare or a custom offer. Dispatch (§3) opens a candidate wave.
- **NEGOTIATING:** offers are rows (`ride_offer`: driver, amount, state PENDING/ACCEPTED/DECLINED/EXPIRED/WITHDRAWN, TTL). A driver may accept the rider's price (instant match), or counter; the rider may accept a counter, counter back (one more round max — **CONFIG** `maxNegotiationRounds=2`), or ignore. Offer TTL **CONFIG** 30s; request TTL **CONFIG** 5 min → `EXPIRED`. First acceptance in either direction wins atomically (conditional update); all other offers auto-expire.
- **CONFIRMED:** fare frozen; driver token debit happens **here** (§4); rider sees driver/vehicle/plate/ETA; a `messaging` thread opens with `ConversationContext(kind=RIDE, refId=rideId)`.
- **ARRIVING / IN_TRIP:** driver position fan-out over the existing WebSocket (same pattern as chat); pickup confirmed by driver tap (+ optional rider PIN **CONFIG**, default off). **Add stop:** allowed IN_TRIP; re-quotes via pricing engine; rider must accept the new fare in-app before rerouting; declined → original route stands.
- **COMPLETED:** fare charged (§1), mutual rating window opens (**CONFIG** 7 days), `TripCompleted` event published (consumed by `partner` §5 community verification, `notifications`).
- **Cancellation:** rider free until CONFIRMED; after CONFIRMED a **CONFIG** cancel fee applies once the driver moved; driver cancel refunds tokens + reopens the request (one automatic re-dispatch wave).

**Scheduled rides:** `scheduledAt` on the ride; a claim-and-fire poller (the send-later pattern from messaging) promotes it to REQUESTED at T − **CONFIG** lead (default 10 min). **Book for someone else:** recipient name + phone on the ride; recipient gets tracking via share link (§10) + SMS when SNS is unblocked; the booker pays.

---

## 3. Dispatch matching (platform `dispatch`) — **BUILT 2026-08-01**

Refinements the build made to this spec (§11.4: update SPECS when a build refines it):

- **Presence is Postgres, not Redis GEO.** The read is "available workers of kind K within N km", over a table already narrowed by kind, status and suspension. The database runs a **bounding box** (plain index-friendly comparisons, padded so it is never tighter than the circle) and the real great-circle distance is measured in Java over what comes back. Redis is right when thousands of workers are moving; there are zero, an ElastiCache cluster bills by the hour regardless, and moving the presence columns later changes one repository method and no caller.
- **Positions arrive over REST**, not the WebSocket. The socket that exists is API Gateway with `$connect`/`$disconnect` Lambdas owning a connection registry — there is no inbound message route, and building one belongs in the milestone where a position is *watched* (M3's live trip) rather than merely stored. `POST /v1/dispatch/me/position` returns 204 with no body; the reporting interval is told by the server, since the cost of it is the server's.
- **One `dispatch.worker` table with a `kind`**, not `dispatch.driver` and `dispatch.courier`. A dual-mode person is one human with two rows, which is what makes "an accepted job in either mode makes you busy in both" a one-line rule, and why a position report fans out to every registration they hold.
- **Ranking is a pure function over a shortlist**, not SQL — nothing on the build machine can execute JPQL, and this is the last logic in the system that should first run in production. Weights normalise each term before applying (proximity 60 / rating 25 / idle 15): a raw kilometre and a raw star are not comparable. The idle term is a **tiebreak, not a queue** — an hour of waiting outranks a driver about as close, and does not outrank one two kilometres nearer.
- **A lost race is `WITHDRAWN`, never `EXPIRED`.** Both end with the worker not doing the job, but only one is about the worker, and counting a withdrawal against an acceptance rate punishes people for races nobody told them they were in. Likewise **performance rates are null until there is something to divide by**, and a new worker's 5.00 is display rather than a rating — the first real one replaces it.
- **First acceptance is settled by a JPA `@Version` on the job**, not by the service's state check: two accepts a millisecond apart both pass an in-memory test. The loser is told plainly and nothing is published.
- **The wave clock doubles as the courier trigger.** `readyAt − pickupLead` is not a separate mechanism — it is a job whose first wave is scheduled in the future, and a scheduled ride is the same thing with a longer wait. The request TTL runs from the start of the search, not the booking.
- **Routing/ETA authority is not built.** Distances are straight-line; Mapbox Directions arrives with the live trip that needs a polyline (M3). **Rating floor ships at 0** — a floor is meaningless before enough ratings exist for one to mean anything.
- **Fare negotiation is not here.** An accept is an accept; §2's counter-offer rounds are `travel` order state layered on top of an offer, not inside it.

### Original spec

Owns: driver/courier presence + assignment. Redis GEO for positions (updated over WebSocket, **CONFIG** every 5s while available); Postgres (or thin ledger) for assignments and provisioning registries.

- **Provisioning registries:** `dispatch.driver` / `dispatch.courier` rows created by `DriverProvisioningApi`/`CourierProvisioningApi` at partner approval: vehicle category(ies), active vehicle, availability flag, home region. A dual-mode user is one person with both rows; **mode toggle** = availability flags (both may be on; an accepted job in either flips the other to busy).
- **Candidate search:** radius rings (**CONFIG** 1 → 3 → 7 km waves, 15s apart), filtered by category, availability, not-busy, rating floor **CONFIG**; ranked by `score = w1·proximity + w2·rating + w3·idleTime` (idle time prevents starvation). Wave size **CONFIG** 5.
- **Offer fan-out:** dispatch pushes the request to the wave over WebSocket; responses route back to the vertical (travel owns negotiation; delivery auto-assigns first-accept). Dispatch records assignment; the vertical owns all further state.
- **Courier trigger for orders:** search starts at `readyAt − pickupLead` where `readyAt = acceptedAt + prepMinutes` (merchant-set per item, max of the basket) and `pickupLead` **CONFIG** 7 min — the "approaching readiness" logic from the vision.
- **Performance counters** (vision's driver metrics): acceptance / completion / cancellation rates + rolling 30-day windows, incremented by dispatch events; exposed to the driver dashboard and to matching (rating floor).
- **Routing/ETA authority:** server calls **Mapbox Directions API** (already the map vendor; server-side token, **CONFIG** swap-able to OSRM later for cost) for authoritative ETAs + route polylines; client Mapbox remains UX-only. ETAs recomputed on each position tick, throttled **CONFIG** 15s.

---

## 4. Driver/courier onboarding logic (`partner` + wallet + dispatch) — **BUILT 2026-08-01** (except community verification, Phase 3 M5)

Refinements the build made to this spec (§11.4: update SPECS when a build refines it):

- **The stake is a `transfer` into the owner's own STAKING bucket, not a `hold`.** `WalletApi.hold` means ESCROW — money in flight for a transaction — and a stake is neither. It stays the applicant's money in a locked pocket, which is what makes returning it a *release* and lets M5's verification reward be a transfer out of it.
- **The KYC fee is charged out of STAKING and capped at what remains.** Billing a separate balance would let somebody stake and then have nothing to check them with; capping means a config mistake can make the fee useless but never puts a stake into debt. A **zero fee writes no ledger entry** — a line whose only content is that a policy is off is noise in a statement.
- **Idempotency keys come from facts already on the row**, never a clock: `partner:{id}:stake`, and for the fee the *total charged so far*, so a retried submission collapses onto one movement while a genuine resubmission gets its own.
- **Rejection and withdrawal release the stake; a suspension does not.** Keeping it on a rejection would make refusing people profitable; returning it on a suspension defeats what it funds. Release on *account closure* (the spec's "30 days, no open disputes") is **not built** — winding a driver down has trips and money in it.
- **Vehicles live in `partner`, not `dispatch`.** A vehicle is a claim a human reviews; dispatch needs one fact out of it, delivered at approval. **Editing the plate or the category un-approves it** — an edited plate describes a different car, which is the exact fraud this check exists to catch — while a colour change does not. **One active vehicle per driver, held by a partial unique index** rather than by the service, since activation is two writes.
- **A driver needs a vehicle and a courier does not.** A courier on a bicycle has no registration or insurance to show; one who registers a scooter still gets it reviewed. It is a config flag, so a market that disagrees changes a row.
- **Expiry is a sweep with a grace period, and flagging the active vehicle suspends its driver.** The day a certificate ran out is not an event anything reacts to, so without the sweep a lapsed registration receives work forever; and a flag that leaves work arriving is a flag that did nothing.
- **Vehicle photos** have a table, a cap and reference tracking, but no client picker yet — the papers were the blocking half.
- **Ride-hailing tokens are M4**, not built here.

### Original spec

Extends live `partner` machinery; the application object is unchanged, `kind=DRIVER|COURIER`.

- **Order of operations:** application → **stake** → KYC → vehicle(s) → approval → provisioning. The $30 stake (**CONFIG** `driverStakeAmount`) is a `WalletApi` hold into `STAKING` and is a *precondition for submission*, not approval — vision: staking funds verification. Insufficient wallet → Stripe top-up inline.
- **KYC: BUILT (2026-07-30) — impl #2 landed first.** `IdentityVerificationApi` lives in its own platform module **`kyc`**, not inside `partner` or `auth`: driver staking, seller provisioning and payouts all need a verified person, so none of them should own it (ARCHITECTURE §2b decision 3). The vendor is **Sumsub**, over its iOS MobileSDK — the app mints a short-lived access token from `POST /v1/kyc/access-token`, documents go from the camera straight to the vendor, and the verdict returns by HMAC-verified webhook (`/v1/kyc/webhook`) *or* by pull (`POST /v1/kyc/refresh`), which is what keeps the flow working before a webhook URL exists. Statuses are `NOT_STARTED | PENDING | IN_REVIEW | VERIFIED | RESUBMISSION_REQUESTED | REJECTED` — the retryable/final split matters, since the app offers a retry for one and not the other. The gate is at **submission**, not approval (a reviewer's queue should never hold an application that cannot be approved), and it applies to the admin-side create too: nobody passes a liveness check on someone else's behalf. With the vendor configured, the identity document kinds drop out of `requiredDocuments` — collecting an ID card we've chosen not to store would be theatre — leaving `RESTAURANT` needing only its licence and `DRIVER`/`COURIER` needing no uploads at all. **Unconfigured = the old path**, unchanged. KYC fee (**CONFIG**) debited from `STAKING` on submission; resubmission after FAILED charges only **CONFIG** retry fee (default 0).
- **Vehicles:** `partner.vehicle` — category, make, model, year, color, plate (unique per region), registration + insurance docs via `MediaDocumentApi` (private), 5 photos via `media` (public). States: `SUBMITTED → APPROVED → COMMUNITY_VERIFIED | FLAGGED`. Multiple vehicles allowed; exactly one **active** per driver; each verifies independently. Insurance/registration expiry dates stored → expiry pushes + auto-suspend on lapse (**CONFIG** grace 7 days).
- **Community vehicle verification:** on the **first** `TripCompleted` for an APPROVED-but-not-verified vehicle, `partner` invites that passenger (push + in-app card, expires **CONFIG** 48h; falls through to the next passenger, max **CONFIG** 3 invites). Passenger confirms: driver matches, photos match, plate matches, roadworthy, no fraud — plus optional photos (private prefix) and comment. All-yes → vehicle `COMMUNITY_VERIFIED`, badge everywhere, reward (**CONFIG**, e.g. $3) transferred from the driver's `STAKING` to the passenger's `REWARDS`. Any-no → `FLAGGED` + application `SUSPENDED` + admin review; the driver receives no new requests meanwhile.
- **Ride-hailing tokens:** `payments.token_policy` — tokens required per ride, keyed by category + distance band, effective-dated (central updates, no client change — vision). Debit at CONFIRMED; refund on driver-fault cancellation; no refund on completion or rider-fault cancel. Packs: `payments.token_pack` (size, price). Low-balance push at **CONFIG** threshold; a driver below min balance is filtered out by dispatch, not blocked from the app.
- **Withdrawals:** `AVAILABLE → Stripe Connect payout`; min amount + cooldown **CONFIG**; history from the ledger.

---

## 5. Delivery at full vision — missing pieces

- **Multi-merchant orders:** `delivery.order` becomes the parent (payment, address, recipient, totals); new `delivery.sub_order` per merchant (items, prep state machine — today's order states minus courier states). Courier states live on the parent (single-courier default) or per **leg** when dispatch splits merchants across couriers (**CONFIG** `maxMerchantsPerCourier=3`, split when route cost exceeds threshold). One payment hold; settlement splits per sub-order at capture (§1). Cancellation is per-sub-order until its merchant accepts; full-parent cancel refunds everything.
- **Handoff integrity:** pickup = 6-char order code on the sub-order (courier shows / merchant confirms; QR of the same code); delivery = **CONFIG** per-order choice of recipient PIN (default), photo (contactless), or plain confirm. Wrong PIN 3× → courier sees support flow, order stays `ARRIVED`.
- **Ordering for someone else:** recipient name/phone/instructions on the order (fields exist in spirit from addresses); recipient tracking via share link (§10) + SMS later. Booker pays; recipient gets the PIN.
- **Scheduled orders:** `scheduledAt`; poller promotes to merchant queue at `scheduledAt − prep − pickupLead`; modify/cancel free until promotion ("before preparation begins" — vision).
- **New categories** (grocery, pharmacy, retail, flowers, electronics, pet, package, errands): merchant `category` + order `kind`. Package delivery = order with pickup+dropoff and no merchant catalog (courier-only). **Errands/shopping assistance:** DEFERRED — free-form baskets break server-side pricing (the one invariant this vertical is built on); revisit as a quoted-then-approved flow.
- **Pickup / collect-in-store** (gap found 2026-07-31 — the vision, the plan and §9 all assume it and none of them define it; §9's `info` block is specified as rendering "hours/delivery/**pickup**"). A `fulfilment_kind` on the order (`DELIVERY` | `PICKUP`), offered per merchant (`pickup_enabled`, `pickup_prep_minutes`, and a pickup address that defaults to the merchant's own). What changes, and it is deliberately little: **no courier and no dispatch** (the state machine ends `CONFIRMED → PREPARING → READY_FOR_PICKUP → COLLECTED`, skipping every courier state, which is why this must not be modelled as a delivery with a zero courier), **no delivery fee and no tip** at pricing time — so the money split is food − commission to the merchant, commission + service fee to the platform, and nothing under `COURIER_FEE`/`TIP`, which is exactly the arithmetic §1 already does with those lines at zero. Collection is the same handoff code the courier uses (§5 above), shown to the customer instead: the merchant confirms the code, and one mechanism covers both. Two rules worth fixing now because they are cheap now and expensive later: a **promotion of kind `FREE_DELIVERY` is inapplicable to a pickup basket** (it must not silently become a discount on food — the whole point of §6's shape is that a discount is an honest order line), and a merchant with `pickup_enabled` and `active=false` is closed for both, since "open" is one switch about whether the kitchen is cooking. Lands with Phase 4 M4's breadth work, ahead of scheduled orders — a scheduled *pickup* is the same poller with no `pickupLead`.
- **Disputes** (missing items / wrong / damaged — vision): `delivery.dispute` on a delivered order: reason, items, photos, state `OPEN → RESOLVED_REFUND(full|partial) | RESOLVED_REJECTED`, **CONFIG** window 24h. Resolution is a human act on the admin surface (GoJoAdmin later; token surface now); refund executes via `WalletApi`. Same shape reused by economy/services later.
- **Order push:** `OrderStatusChanged` finally gets its consumer — `notifications` maps each transition to a push (see §12 matrix). Lands with checkout (2e M3), not Phase 4.

---

## 6. Commerce gaps (`economy`)

- **Product model (merchant catalogs, Phase 5 M1):** `economy.product` (seller merchant, name, description, category, brand, media gallery, specs JSON) + `product_variant` (SKU, option values e.g. size/color, price, stock) + per-variant inventory. **Inventory:** decrement inside the order transaction with a conditional `stock >= qty` update (oversell-proof); restore on cancel/refund. C2C `listing` stays as-is — a listing is not a product.
- **Cart:** stays client-side (the delivery decision, kept): checkout posts item ids + quantities; server prices everything. One cart per seller context; multi-seller product checkout = the multi-merchant parent/sub-order pattern (§5) reused.
- **Promotions (missing everywhere in the current plan):** per-vertical `promotion` table, one shared shape: scope (merchant | item/variant), type (`PERCENT` bps | `FIXED`), window, optional code, per-user limit, min basket. Applied server-side at pricing time; the discount is an order line, so receipts and refunds stay honest. Delivery first (2e M3 checkout), economy at Phase 5 M1. Free-delivery promos are a fee-line discount, same mechanism.
- **Reviews:** per-vertical engagement-style tables (the watch pattern): `review(target, author, rating 1–5, text, photos, created)`, one per buyer per fulfilled order/booking (verified-purchase only), aggregate cached on the target. Merchant reply: one per review. Applies to products, merchants, providers, services; delivery keeps its existing order rating and gains the written+photo form.
- **Digital products:** `product_kind=DIGITAL` + `digital_asset` (S3 private prefix via `MediaDocumentApi` pattern), `entitlement(user, product, kind = DOWNLOAD | LICENSE | SUBSCRIPTION)` granted at capture; downloads = short-lived signed GET, re-issuable while entitled; license keys = pre-loaded pool or generated; subscriptions = Stripe subscription mirrored to an entitlement with `expiresAt`.
- **Ownership transfer:** `listing_kind=OWNERSHIP_TRANSFER` + VIN/serial, condition, documents (private). Flow: `INQUIRY → OFFER_ACCEPTED → PAYMENT_HELD (escrow) → DOCS_CONFIRMED (admin checkpoint — a human verifies the paperwork; same posture as KYC review) → TRANSFERRED → RELEASED`. Either side can cancel before DOCS_CONFIRMED → full refund. High-value: **CONFIG** cap on wallet-held amount; above it, flag for manual settlement.
- **Taxes/shipping:** flat per-merchant config (tax bps, shipping flat/threshold-free). No tax engine — revisit per market.

---

## 7. Services booking (`services`, Phase 5 M3)

- **Provider profile:** provisioned via `partner` (`kind=SERVICE_PROVIDER` → `services.ProviderProvisioningApi`); qualifications/certifications docs private, portfolio public, service areas (regions), languages, response-time stat (computed from messaging first-reply times).
- **Catalog:** `service` (name, description, category, duration, price | `PRICE_ON_QUOTE`, location kind `AT_PROVIDER | AT_CUSTOMER | REMOTE`, requirements/preparation text, cancellation policy ref).
- **Availability:** weekly template (slots per weekday) + exception dates; bookable slots = template − exceptions − existing bookings − **CONFIG** buffer; horizon **CONFIG** 60 days.
- **Booking state machine:** `REQUESTED → CONFIRMED → COMPLETED | DECLINED | CANCELLED_CUSTOMER | CANCELLED_PROVIDER | NO_SHOW`. Payment held at request; provider must confirm within **CONFIG** 24h or auto-decline (auto-release). `PRICE_ON_QUOTE`: provider quotes in the thread → customer accepts → hold. Cancellation policy tiers (**CONFIG** per policy: free until X h before, then Y% fee, no-show 100%); provider cancel always free to customer + counts against provider metrics. Completion: provider marks done, customer has **CONFIG** 48h to dispute (§5 dispute shape), else auto-capture.
- **Thread:** every booking opens `ConversationContext(kind=BOOKING)`.

---

## 8. Business profiles, act-as, roles (2e M1) — **BUILT 2026-07-30**

Refinements the build made to this spec (§11.4: update SPECS when a build refines it):
- `category` and `bio` are **not** duplicated onto `business_profile` — a business reuses the profile columns it already has; the extension table holds only contact / address / hours / `verified` / owner.
- Act-as also covers likes and follows (query param `?actAs=`), not just creates. **iOS deliberately uses it for creation only**: reads are decorated for the caller, so a business like would read back unliked.
- `maxBusinessesPerOwner` is a Java constant (5) until the config registry (§14) exists in 2e M3.
- Handle changes on a business skip the two-month cooldown — that rule protects a person's identity, not a shop's signage.


- **Model:** `profile.kind = PERSON | BUSINESS`; business fields (category from the vision's taxonomy, description, address + geo, hours JSON, contact, links) on a `business_profile` extension table (`profile` schema); `owner_profile_id` → the owning person. **CONFIG** max businesses per owner (default 5). Team members/multi-owner: DEFERRED (single owner until GoJoAdmin needs roles).
- **Act-as:** mutation endpoints that create content (`posts`, `stories`, `videos`, media presign) accept optional `actAsProfileId`; server verifies `owner_profile_id == caller` else 403. Reads are unchanged (a business profile is just a profile). Likes/comments *as* a business: allowed, same mechanism. No second token, no session switch server-side; the iOS switcher is pure client state.
- **Commerce enablement:** `partner` application carries `business_profile_id`; approval stamps the vertical's provisioned id back. A business with no approval is content-only — exactly the vision's "brand before commerce".
- **Verified badge:** businesses get `verified=true` only via partner approval (KYC'd); no paid verification.
- **Role switching (vision "activate roles, switch between roles"):** roles are *derived*, not stored — `hasBusiness` (owned business profiles), `isDriver`/`isCourier` (dispatch registries), `merchantOf` (provisioned verticals). One `GET /v1/me/roles` aggregate powers the iOS profile switcher and mode toggles; no role table to drift.

---

## 9. Storefront JSON contract (2e M4) — **BUILT 2026-07-31**

Built as specified, with five refinements worth recording (§11.4):

- **The document lives in its own platform module** (`storefront` schema, one table keyed by `(surface, owner_id)`), not on the vertical's own table. `economy` and `services` get storefronts on this same contract, and three verticals each holding their own JSON is three renderers that disagree by the second release. The vertical still owns authorisation and references.
- **The block set is closed per surface, not globally.** `MERCHANT_STOREFRONT` takes all seven; `BUSINESS_HOME` takes `hero` / `media_row` / `text` / `info` only — a catalog block on a page with no catalog is a block whose ids nobody can resolve.
- **Validation is split, and the split is in the signature.** The module validates shape (type, surface, required properties, lengths, caps, ref kinds, and no property a type has no meaning for); the vertical validates that the ids are its own, passed in as a `StorefrontReferenceCheck` so no save can skip it. A bad id refuses the document whole and names the id.
- **POST/VIDEO refs are deliberately unvalidated.** `delivery` has no dependency on `social` or `watch`, and imported content renders through reads that enforce their own visibility, so the worst a borrowed id achieves is showing something already public.
- **Reads never fail.** A document that won't parse comes back empty and logs — the decorative half of a commerce page must not be able to take the functional half down. Public reads are embedded (merchant detail; the profile view `social` builds), and are always present so a client has one code path. iOS renders everything except `media_row`, which it skips like an unknown type.

### Original spec

One document per merchant (later per business), versioned: `{version, blocks: [...]}` where each block is `{type, id, ...props}` from a **closed set**: `hero` (media, headline, cta → item/section), `featured_items` (item ids), `collection` (title, item ids), `promo_banner` (promotion id), `media_row` (post/video ids — Studio's "import existing content"), `text` (about/policies), `info` (hours/delivery/pickup — rendered from live merchant data, not duplicated). Server validates types + referenced ids on write (400 on unknown type — forward-compat by version bump, the app's optional-decode discipline). Owner-scoped write `/mine/storefront`; public read embedded in the merchant/business payload. iOS renders read-only; unknown block types are skipped silently.

---

## 10. Trust & safety baseline — **BUILT 2026-07-31** (blocking, reporting, account deletion)

Built as specified for the three App Store blockers; the two ride-dependent items (SOS, live share links) are **not** built and moved to Phase 3 M5, where the trip they describe exists. Deviations worth recording:

- **Blocking lives in `social`, and `messaging` does not read it.** The table sits next to `follow` because a block has to tear down the follow graph in the *same transaction* — a safety feature that is briefly wrong is a safety feature that failed. But `messaging` is a platform module, and a platform module asking a vertical for permission inverts the layering (ARCHITECTURE §2). So the rule is handed *down*: `messaging` defines a public `ConversationGuard` SPI, `social` implements it, and a messaging module with no guards on the classpath behaves exactly as before. `SocialGraphApi.blockedIds` covers the read side for `watch` and `economy`, which are verticals and may depend on one.
- **Only one half of a block is disclosed.** "I blocked them" is a field on the profile view (it is the only place to undo it); "they blocked me" is a **404 on the profile**, with no field anywhere that could be read to infer it. Telling someone they were blocked hands them a reason to open a second account.
- **Reportable kinds are the ones with a handler.** `POST | COMMENT | STORY | VIDEO | PROFILE | LISTING`. `MESSAGE`, `ORDER` and `RIDE` are deliberately absent: a report a moderator cannot see the content of is a queue item nobody can close, and a private DM in DynamoDB is not something this queue can render. Adding one later is an enum constant plus a handler bean — the column is a varchar for that reason.
- **The vertical owns its content, so the vertical implements the takedown.** `moderation` stores a pointer and calls `ModeratableContent`, implemented in `social`/`watch`/`economy` — the same plugin shape as `ConversationGuard`, and the same direction (`vertical → platform`). An action a vertical can't perform (hiding a profile is a shadowban; deleting one is its owner's right) throws and becomes a 409 naming the combination, rather than a success that did nothing.
- **`SUSPEND` on a business profile is refused by name.** A business has no sign-in of its own, so suspending one would silently lock out the person who owns it; the refusal names the owner so a moderator makes that call deliberately.
- **One decision closes every open report on the same target; a dismissal closes only its own.** Forty rows for one viral post is a queue nobody can work — but somebody else's complaint about the same post may be a *different* complaint, and closing it unread would be a guess.
- **Account deletion cannot be cancelled in-app.** Sign-in is disabled the instant it is requested (that is what makes the account gone from the user's side), which leaves no session to cancel from. An operator restores it from the moderation admin surface — which is what a support request would do anyway. The screen says so.
- **A business owned by a deleted person survives and becomes unmanageable** (`actsFor` never matches a tombstoned owner again). Winding down a merchant has orders and money in it and is not a side effect of a personal deletion.
- **Two modules were moved to break a cycle.** `auth` grew `PlatformAdminApi` (the single definition of "is this an operator", previously a private copy in `partner`) and `AccountAdminApi` (Cognito disable/enable). `profile` and `moderation` now depend on `auth`, so `auth`'s old dependency on `profile` had to go: **`POST /v1/auth/session` moved into `profile`, same URL**. No client change.

### Original spec

Required before social scale (and App Store UGC guideline 1.2: report + block + takedown).

- **Blocking:** `social.block(blocker, blocked)` — removes follows both ways, hides each other's content/comments everywhere (feed, stories, watch, search), and `messaging` refuses new 1:1s (existing threads freeze). Exposed via an extended `SocialGraphApi.blockedIds` so other modules filter without owning the table.
- **Reporting:** platform `moderation` module (new, small): `report(reporterId, targetKind, targetId, reason, note)` — target kinds: post, story, video, comment, message, profile, listing, product, merchant, ride, order. Queue states `OPEN → ACTIONED(hide|remove|suspend) | DISMISSED`; review is human on the admin surface (GoJoAdmin later). `hide` is soft (author still sees it); `suspend` cascades to Cognito disable. Same module records ride/delivery incident reports (vision "reporting tools").
- **SOS (rides/deliveries):** button IN_TRIP → one-tap call to the local emergency number (**CONFIG** per region), simultaneous notify of the user's **emergency contacts** (`profile.emergency_contact`, max **CONFIG** 5) with a live share link, trip flagged `SOS` (admin surface + event). No PSAP integration claimed.
- **Live share links (rides, deliveries, later stories):** `share_token(kind, refId, token, expiresAt)` → public unauthenticated `GET /v1/share/{token}` returning a minimal tracking payload (position, ETA, driver first-name/plate) — the vision's "share with trusted contacts" for non-users. Expires at trip end + **CONFIG** 1h. Same token mechanism later backs universal links `https://gojogo.app/s/{token}` for content sharing (deep-link routing is an iOS slice).

---

## 11. Identity gaps (`auth`)

- **Phone signup** (vision lists it; currently email/Google/Apple only): Cognito `phone_number` alias + SMS OTP — **blocked on the existing SNS SMS production item** (PROGRESS "Needs YOU" #3); build only after that clears. Note: app-account phone is distinct from the My World phone identity by design — linking them is a product decision, default *not linked*.
- **MFA** ("secure their account"): Cognito optional TOTP MFA, settings toggle. Low-effort, post-2e polish.
- ~~**Account deletion**~~ — **BUILT 2026-07-31** with 2e M5, exactly as written: `DELETE /v1/me` → Cognito disable (plus a global sign-out, or the refresh token on the device keeps minting access tokens) + a 30-day grace on a nightly sweep → anonymize. The tombstone *is* the content plan: every author summary in this codebase already renders a missing profile as "Deleted user", so scrubbing the row's identifying fields turns every old post into that for free, with no per-vertical cascade and no holes in other people's threads. Ledger rows untouched. See §10 for the two gaps (no in-app cancel, orphaned business profiles).

---

## 12. Messaging + notifications coverage

- **`ConversationContext` kinds:** `LISTING` (live) + `RIDE`, `ORDER`, `BOOKING` (each vertical stamps its card; the pattern is proven). **Support chat:** `kind=SUPPORT` conversations with a reserved platform peer; inbox = GoJoAdmin later; until then the card deep-links to mail. Do not build a support agent console in iOS.
- **Push matrix (each event → push, in-app row, or both):** live today: social events + `MessageSent` + `PartnerReviewed`. To add, in order: `OrderStatusChanged` (2e M3 — placed/accepted/ready/picked-up/arriving/delivered), payment received / payout sent (2e M3), ride offer / confirmed / arriving / completed (Phase 3), token low balance (Phase 3), verification invite + reward (Phase 3), booking requested / confirmed / reminder **CONFIG** 24h+1h (Phase 5), dispute updates (Phase 4). Every new event gets: an `@ApplicationModuleListener` in `notifications`, an activity row, and an APNs template — one pattern, no exceptions.

---

## 13. Search & discovery contract (Phase 5 M4)

- **Index sources (consumers for events already publishing into the void):** `PostCreated`, `ListingCreated` + to-add `ProductUpserted`, `MerchantUpserted`, `VideoPublished`, `ServiceUpserted`, `BusinessProfileUpserted`. Each module owns its document shape; the `search` module owns only the pipeline + query API (index-per-domain, one alias).
- **Query surface:** `GET /v1/search?q=&kind=&near=&filters=` — kinds: people, businesses, products, menu items, services, videos, posts. Location filter from business geo. Ranking: text relevance × popularity (engagement counts) × distance decay for local kinds; personalization (follow graph boost) later.
- **Trending / recommendation rails** ("discover trending topics", "featured/trending restaurants"): periodic aggregation jobs over engagement events → cached rails per region; not real-time, **CONFIG** refresh 15 min. Until Phase 5 M4, "trending" surfaces stay recency+engagement sorts from Postgres (the live feed ranking pattern).

---

## 14. Platform config registry — **BUILT 2026-07-31**

Built as specified (`platform.config`, `ConfigApi`, 60s cache, effective-dated), with two notes: reads always take a **compiled-in default**, so an empty table behaves identically to a populated one and a typo in a value falls back rather than becoming a zero fee; and there is **no write endpoint yet** — values are seeded by migration until GoJoAdmin exists to edit them, the same posture the music catalog and partner review took.

### Original spec

All **CONFIG** knobs above live in one place: environment for infra-ish values, a `platform.config` table (key, value, effective_from) for product policy (fees, token policy, stake, TTLs, radii, windows) — readable by all modules via a tiny `ConfigApi`, cached **CONFIG** 60s, edited from the admin surface later. Effective-dating is what lets GoJoAdmin change token prices "without changing the driver experience" (vision).

---

## 15. Explicitly deferred (decided, not forgotten)

| Item | Why deferred |
|---|---|
| Cash payments | Receivable/reconciliation complexity; no market requirement yet (§1) |
| Refunding a *settled* order | Cancelling before delivery releases the hold, which covers the live case; a post-delivery refund needs the dispute flow (§5), Phase 4. `WalletApi.refund` exists and is uncalled. |
| Errands / shopping assistance | Breaks server-side pricing invariant; needs quote-approve flow (§5) |
| Team members / staff roles on a business | Single owner until GoJoAdmin needs roles (§8) |
| GoJoAds | No seam beyond existing engagement events (ARCHITECTURE §10b) |
| Articles (long-form) | A post kind + editor UX; no dependencies, schedule when social invests |
| Healthcare-specific compliance | Providers onboard as service providers; no medical records, no claims |
| Real estate (ownership transfer) | Vision marks it future |
| PDF receipts/invoices | Order record is the receipt (§1) |
| Multi-currency | Single `PLATFORM_CURRENCY` until a second market exists |
| KYC vendor integration | **Done (2026-07-30)** — Sumsub behind `IdentityVerificationApi` in the `kyc` module; sandbox credentials, production is a Secrets Manager swap. Manual document review remains the fallback when unconfigured. |
