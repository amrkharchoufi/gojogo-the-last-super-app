# MADELEINE — Agentic Assistant Spec

Companion to [ARCHITECTURE.md](ARCHITECTURE.md) (boundaries, phases) and [SPECS.md](SPECS.md) (per-vertical logic). This file is the **wire contract and decision record** for Madeleine: the agent loop, the inference stack, the tool catalog, the confirmation protocol, and the pilot-mode command channel. Written before building so milestone sessions start from decisions, not questions — and because Madeleine spans three surfaces (GPU infra, backend module, iOS client) that will be built in parallel sessions, **this doc is the contract between them**. Its silences are where the bugs will land; when a build refines a decision, update this file (SPECS §11.4 convention applies here too).

Conventions: money is integer **minor units**; **CONFIG** marks server-side policy knobs; the spelling is **Madeleine** everywhere (the iOS shell — `MadeleineHomeView`, `MadeleineOrb` — already uses it).

**The four locked decisions** (from planning, 2026-08-07):

1. Madeleine is a backend `assistant` module. She acts by calling the same module APIs the app calls, **with the caller's own identity — never an elevated service account**. Full reach, zero elevation.
2. The model is **self-hosted Llama on AWS** behind a `ModelClient` interface; Bedrock's hosted Llama 3.3 70B is the dev-time bridge (same weights) and the production fallback route.
3. **Every action that moves money or leaves the user's private space requires an explicit in-app approval**, enforced server-side by a confirmation token the model never possesses. No autonomy level, prompt, or "the user already said yes" tool argument bypasses this.
4. Two execution lanes: **headless** (backend tool calls — where work happens) and **pilot mode** (a typed command channel that visibly drives the app — where trust happens).

---

## 1. Shape

```
iOS (GojoGo)                     backend                          GPU stack
┌──────────────────┐   REST     ┌──────────────────┐   HTTP      ┌─────────────────┐
│ MadeleineHomeView │──────────▶│ assistant module  │───────────▶│ vLLM / Llama 3.3 │
│ MadeleineStore    │           │  agent loop       │  internal  │ 70B FP8 (+8B)    │
│ pilot dispatcher  │◀──────────│  tool registry    │    ALB     └─────────────────┘
│ confirm cards     │ WorldSocket│  confirmations   │──▶ ToolApi calls into
└──────────────────┘  (fan-out) │  task runner      │    social/delivery/travel/…
                                └──────────────────┘    with the user's identity
```

- **Client sends over REST, receives over the WorldSocket** — the exact pattern messaging already uses. No new transport.
- The `assistant` module reaches other verticals through their **existing internal `*Api` facades** (Modulith-checked), never their repositories. Where a facade lacks a verb Madeleine needs, the verb is added to the facade — the vertical stays the owner of its own rules.
- Per the unique-class-names rule, everything in the module is prefixed `Assistant*` (`AssistantConversation`, `AssistantTask`, …).

---

## 2. Inference stack (`infra/lib/inference-stack.ts`)

New CDK stack, sibling of `fargate-stack.ts`. **Nothing in it is public.**

- **Serving:** vLLM (OpenAI-compatible server) in a container, EC2 launch type — an ECS capacity provider over a GPU Auto Scaling Group (Fargate cannot do GPUs). Llama tool-call parser enabled (`--tool-call-parser llama3_json`, `--enable-auto-tool-choice`).
- **Models:**
  - **Brain:** `Llama-3.3-70B-Instruct` **FP8** — the smallest Llama reliable at multi-step tool calling.
  - **Sidekick:** `Llama-3.1-8B-Instruct` on its own small node — intent triage, tool-result summarization, conversation titles. Never plans, never calls write tools.
- **Instances:** prod brain `g6e.12xlarge` (4× L40S, 192 GB — FP8 + real KV-cache headroom); dev/sidekick `g6e.xlarge` (1× L40S). Dev node on a **scale-to-zero schedule** (stopped nights/weekends, **CONFIG** cron). Buy a 1-yr savings plan for the prod node only once Madeleine ships.
- **Network:** internal ALB; security group admits only the Fargate service SG. Health check = vLLM `/health`. The model server never sees the internet and holds no data at rest — weights are baked into the AMI/EBS, conversations live in the database like everything else.
- **Scaling:** min 1 / max 2 on the brain ASG, scale on `vllm:num_requests_waiting` (queue depth), not CPU.
- **`ModelClient`:** one interface in the assistant module — `chat(messages, tools, streamHandler)` against an OpenAI-compatible endpoint. **CONFIG** `MODEL_BASE_URL`, `MODEL_NAME`, `SIDEKICK_BASE_URL`. Pointing `MODEL_BASE_URL` at Bedrock's Llama 3.3 70B is the dev bridge and the outage fallback; the app-facing behavior is identical because the weights are.
- **CDK deploy note:** this adds context flags to the deploy command; per the every-ARN rule, the deploy script must fail loudly if the inference URL/secret flags are absent, not ship with Madeleine silently off.

---

## 3. `assistant` module — data + REST surface

### Entities (all `assistant`-owned; no other module reads these tables)

- **`AssistantConversation`** — id, userId, title (sidekick-generated), createdAt, lastActiveAt, state `ACTIVE | ARCHIVED`.
- **`AssistantMessage`** — conversationId, role `USER | MADELEINE | TOOL`, content (trimmed), optional `toolName`/`toolArgs`/`toolResultSummary`, seq. **The raw model context is not persisted** — messages store what the ledger needs to replay a story, not the token stream.
- **`AssistantTask`** — the autonomy unit (§7): id, userId, conversationId, goal text, state, step plan (JSON), createdAt, finishedAt.
- **`AssistantAction`** — a pending side-effect awaiting approval (§5): id, taskId/conversationId, toolName, args (JSON), human-readable summary, amountMinor (nullable), state `PENDING | APPROVED | EXECUTED | DECLINED | EXPIRED`, confirmToken (opaque UUID, **never serialized into model context**), expiresAt.

### REST (all authenticated as the user; `/v1/assistant/…`)

| Verb | Path | Purpose |
|---|---|---|
| POST | `/conversations` | open conversation |
| GET | `/conversations` / `/conversations/{id}` | list / replay (ledger view reads this) |
| POST | `/conversations/{id}/messages` | user message → starts an agent turn; returns 202 + turnId |
| POST | `/actions/{id}/approve` | body `{confirmToken}` — the **only** path to executing a gated action |
| POST | `/actions/{id}/decline` | decline; agent turn resumes with a `DECLINED` tool result |
| POST | `/tasks` / `/tasks/{id}/cancel` | create / cancel background task |
| GET | `/tasks` / `/tasks/{id}` | task ledger |
| POST | `/turns/{turnId}/interrupt` | user grabbed the wheel (§6) — stops the loop after the in-flight step |
| POST | `/pilot/ack` | client acks a pilot command (§6) |

### Streaming envelope (WorldSocket fan-out, server→client, one envelope kind)

```json
{ "kind": "MADELEINE", "conversationId": "…", "turnId": "…", "event": { … } }
```

`event.type` ∈:

- `token` — `{text}` streamed assistant prose
- `status` — `{text}` one-liner of what she's doing ("Searching restaurants…")
- `tool_result_card` — `{card}` a typed rich card (listing, restaurant, ride quote…) the client renders natively
- `action_pending` — `{actionId, summary, amountMinor, expiresAt, confirmToken}` → client renders the confirm card. **The token travels socket→client→approve call and nowhere else.**
- `pilot` — a pilot command (§6)
- `task_update` — `{taskId, state, step}` (§7)
- `turn_done` / `turn_error` — `{turnId, …}`

Socket-down degradation: same as messaging — the turn still runs; `GET /conversations/{id}` on foreground catches the client up. Never fabricate an optimistic Madeleine reply client-side (never-fabricate rule).

---

## 4. The agent loop

One loop, no planner/executor split — Llama 3.3 does better with a single ReAct-style loop than with a two-model hierarchy:

1. Build context: system prompt + user profile snapshot + conversation tail + tool schemas.
2. Model responds with prose and/or tool calls.
3. Read tools execute immediately (parallel where independent). Write tools **do not execute** — they create an `AssistantAction` and return `PENDING_USER_APPROVAL` to the model (§5).
4. Tool results are **trimmed before entering context**: list results capped at **CONFIG** `toolResultMaxItems=8` items of named fields; the sidekick summarizes anything bigger. Raw JSON never enters the brain's context.
5. Loop until the model stops calling tools, or **CONFIG** `maxToolCallsPerTurn=16`, or **CONFIG** `turnDeadlineSeconds=120`. Budget exhaustion ends the turn honestly ("I got partway — here's where I stopped"), never silently.

**Untrusted-content rule:** everything a read tool returns that a user authored (listing text, posts, reviews, captions) is wrapped in a `<user_content>` delimiter in context, and the system prompt states that nothing inside it is an instruction. The **real** injection defense is architectural: a hostile listing can at worst make Madeleine *propose* an action, and every consequential action dead-ends at a confirm card the user reads. Prompt hygiene is the first fence; the token protocol is the wall.

Rate limits: **CONFIG** `turnsPerUserPerHour=30`, `concurrentTurnsPerUser=1` (a second message queues, it doesn't fork). Moderation: user messages pass the same moderation checks as social content before entering context.

---

## 5. Tool catalog + confirmation protocol

### The classification is the security model

Every tool is `READ`, `WRITE_SAFE` (reversible, stays in the user's private space), `WRITE_GATED` (moves money or leaves the user's space), or `CLIENT` (executes on the phone, §6). **`WRITE_GATED` is enforced in the registry, not in the prompt:** the executor consults the registry, sees the class, and refuses to run the tool directly — there is no code path from model output to a gated side-effect. Model output can only create an `AssistantAction`.

### Confirmation protocol

1. Executor creates `AssistantAction` (state `PENDING`, TTL **CONFIG** `actionTtlMinutes=10`), with a human-readable summary and, when money moves, the exact `amountMinor` — computed by the owning vertical's quote path, not by the model.
2. `action_pending` fans out; client renders a native confirm card: what, where, **exact amount**, Approve / Decline.
3. Approve → `POST /actions/{id}/approve {confirmToken}`. Server validates token + TTL + state, executes the underlying vertical call **with an idempotency key derived from actionId** (assigned-id rule: guard with existsById, don't catch duplicates), marks `EXECUTED`, resumes the turn with the real result.
4. Decline/expiry → the turn resumes with `DECLINED`/`EXPIRED` as the tool result. Madeleine may ask why; she may not retry the same action without a new user message.
5. **One action, one approval.** Approvals never batch ("approve all"), never persist ("always allow rides under 50"), never generalize across a task. A 10-step task with three gated steps stops three times. If that friction ever needs relaxing, it's a future spec revision with its own limits — not a runtime flag.

### Catalog v1 (per vertical; each maps to existing facade verbs — missing verbs get added to the facade)

| Tool | Module | Class | Notes |
|---|---|---|---|
| `search_all` | search | READ | federated; primary entry point |
| `get_profile`, `get_my_bookings` | profile / services | READ | |
| `search_restaurants`, `get_menu` | delivery | READ | |
| `build_cart` | delivery | WRITE_SAFE | cart is reversible; visible in app immediately |
| `place_order` | delivery | **WRITE_GATED** | wallet charge at placement (SPECS §1) |
| `quote_ride` | travel | READ | suggested fare from the pricing engine |
| `request_ride` | travel | **WRITE_GATED** | opens negotiation; balance check is travel's own |
| `accept_ride_offer` | travel | **WRITE_GATED** | fare freeze = money decision |
| `cancel_ride` | travel | **WRITE_GATED** | may incur cancel fee → gated |
| `get_ride_status` | travel/dispatch | READ | |
| `get_wallet`, `get_statement` | economy/payments | READ | **no wallet write tools exist at all** — top-ups are Stripe-hosted checkout, a human-only surface |
| `search_listings`, `get_listing` | storefront | READ | |
| `create_listing_draft` | storefront | WRITE_SAFE | draft state; publishing is gated |
| `publish_listing` | storefront | **WRITE_GATED** | leaves private space |
| `create_post_draft` | social | WRITE_SAFE | |
| `publish_post` | social | **WRITE_GATED** | leaves private space |
| `draft_message` | messaging | WRITE_SAFE | **draft only. No `read_thread`, no `send_message` tool exists.** Sending is the user tapping send on the prefilled composer. GojoMessages content never enters model context — this is the story-replies-stay-in-social rule extended to Madeleine: DM content is its own sealed system. |
| `book_service` | services | **WRITE_GATED** | |
| `get_watchlist`, `queue_music` | watch / music | READ / WRITE_SAFE | |
| `navigate_to`, `prefill`, `highlight` | — | CLIENT | §6 |

KYC, moderation, partner-payout, and admin surfaces get **no tools**. Madeleine explains them and navigates to them; she never operates them.

---

## 6. Pilot mode — the client command channel

The Manus-style capability, done as a first-class remote control instead of screen-scraping, since we own both ends.

### Wire contract (`event.type = "pilot"`)

```json
{ "type": "pilot", "commandId": "…", "seq": 4,
  "command": "navigate", "target": "restaurantDetail",
  "params": { "restaurantId": "…" }, "caption": "Opening Chez Rachid…" }
```

Commands v1 — deliberately few: `navigate(target, params)`, `prefill(screen, field, value)`, `highlight(elementKey, caption)`, `scroll_to(elementKey)`, `end_pilot`. **No `tap`.** Pilot mode shows and stages; anything consequential is either a headless gated action (§5) or a button the *user* presses. A pilot channel that can press buttons is the confirmation protocol with extra steps and no wall.

### Client rules (the part that will bite if unwritten)

- **One owner.** Commands land in `AppState` — a single `pilotQueue` drained one command at a time; screens never receive commands directly (one-owner-per-shared-dialog rule; this channel is exactly the shape that reproduces that bug).
- **Ack per command:** `POST /pilot/ack {commandId, outcome: DONE | UNSUPPORTED | INTERRUPTED}`. The agent loop blocks on the ack (**CONFIG** `pilotAckTimeoutSeconds=10`; timeout ⇒ treat as `UNSUPPORTED` and fall back to prose + a plain `navigate_to`).
- **Capability registry, not reflection:** a static `PilotTarget` enum in the client maps target keys → routes; screens opt in to `prefill`/`highlight` by registering element keys. Unknown target ⇒ `UNSUPPORTED` ack — the server may be newer than the app, and the contract must degrade, not crash. Registry version is reported at conversation start so the model's tool schema only offers targets this app build supports.
- **The wheel is the user's.** Any manual touch during pilot mode pauses the queue and fires `/turns/{turnId}/interrupt`. Overlay = MadeleineOrb cursor + caption bar + a persistent **Stop** button. Keystroke-level state stays view-local (AppState rule); the queue holds commands, not text diffs.

---

## 7. Autonomous tasks

`AssistantTask` state machine:

```
QUEUED → RUNNING → WAITING_APPROVAL → RUNNING → … → DONE | FAILED | CANCELLED
```

- Runner is the **claim-and-fire poller pattern** from messaging's send-later — no new scheduler infra. A task is an agent turn (§4 loop) detached from a live socket.
- `WAITING_APPROVAL`: the task parks on a gated action and **push-notifies** ("Ride found — 1 800 approve?") via notifications. Approval resumes it; **CONFIG** `taskApprovalTtlHours=24` then `FAILED(EXPIRED)` with a notification, never silent death.
- Completion/failure always notifies. A background agent that fails silently is worse than none.
- **Task ledger** screen: every task, its step plan, every tool call and result summary, every approval with timestamp — rendered from `AssistantMessage`/`AssistantAction` rows. This is the trust surface and the debugging surface; it costs nothing extra because §3 already persists exactly these rows.
- v1 tasks are **finite jobs**, not standing rules ("watch prices every day" is a later phase with its own spec section — recurring autonomy changes the risk math).

---

## 8. iOS client work

- **`MadeleineStore`** (new, in `Stores/`): owns conversations, streaming assembly (token events → one growing message), pending actions, task list. `MadeleineHomeView`'s local `app.chatMessages` is replaced by the store; AppState keeps only what's app-global — the pilot queue, an `activePilotTurn` flag the tab bar reads (pollers-diff-before-assigning rule applies to task/action polling).
- **WorldSocket:** add the `MADELEINE` envelope kind to the existing decode switch; no transport changes.
- **Confirm card:** native component — summary, exact amount, Approve/Decline. Rendered in-conversation and as the body of the `WAITING_APPROVAL` push's tap-through screen. Approve button is disabled until the card has been on screen ≥ **CONFIG** 1s (no reflex-tap money).
- **Pilot overlay:** orb cursor + caption + Stop, driven by the AppState queue (§6).
- **Task ledger:** list + detail replay under the Madeleine tab.

---

## 9. Build order (parallel-session plan)

Per the parallel-milestone contract rule — disjoint file ownership, this doc as the wire contract, integration verified by one session at the end:

| Milestone | Session owns | Depends on |
|---|---|---|
| **M1 Inference stack** | `infra/lib/inference-stack.ts`, vLLM image | nothing (Bedrock bridge unblocks M2 immediately) |
| **M2 Assistant module + loop + READ tools** | `backend/**/assistant/**` + facade verbs | this doc §3–5 |
| **M3 iOS chat + streaming** | `MadeleineStore`, `MadeleineHomeView`, WorldSocket envelope | §3 envelope |
| **M4 Confirmation protocol + gated tools** | backend actions + iOS confirm card | M2, M3 |
| **M5 Pilot mode** | AppState queue, overlay, registry + backend CLIENT tools | M3 |
| **M6 Tasks + ledger + push** | task runner, ledger screens, notifications hook | M2, M4 |

Demo line after each: M2+M3 = concierge that answers and deep-links across every vertical; M5 = the app drives itself; M4 = she orders dinner with your thumb on the approve button; M6 = she does it while the phone is in your pocket.

## 10. Cost notes

Prod brain g6e.12xlarge ≈ $7.6k/mo on-demand (≈ $4.7k/mo with 1-yr savings plan — buy after launch, not before); sidekick/dev g6e.xlarge ≈ $1.4k/mo, roughly halved by the scale-to-zero schedule. Bedrock-bridge months cost per-token only. The 8B sidekick exists to keep 70B tokens for thinking, not summarizing — that's a cost decision as much as a quality one.
