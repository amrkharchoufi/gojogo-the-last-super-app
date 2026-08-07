# MADELEINE — Inference Routes

Companion to [MADELEINE.md](MADELEINE.md) (§2 is the decision this doc expands) and [COSTS.md](COSTS.md) (the bill this decision lands on). MADELEINE.md locks *what* Madeleine is; this file is the decision record for **where the model actually runs**, the two routes for getting there, and the written trigger for moving between them.

Conventions carried over: **CONFIG** marks a server-side policy knob; estimates are marked as estimates. Where this doc refines MADELEINE.md §2, MADELEINE.md gets updated too (SPECS §11.4 convention).

---

## 0. The one sentence that makes this cheap

MADELEINE.md §2 already defines **`ModelClient`** — a single interface, `chat(messages, tools, streamHandler)`, against an OpenAI-compatible endpoint, configured by **CONFIG** `MODEL_BASE_URL` / `MODEL_NAME` / `SIDEKICK_BASE_URL`.

Both routes below are the **same weights** (Llama-3.3-70B-Instruct) behind the **same interface**, reached over the **same wire format**. Nothing in M2–M6 — the agent loop, the tool registry, the confirmation protocol, the pilot channel, the iOS client — knows or cares which route is live.

**So this is a deployment decision, not an architecture decision, and it is reversible with an environment variable.** That fact is the most valuable thing in this document: it means the route can be chosen on cost evidence later instead of on guesswork now, and it means neither route is a trap.

---

## 1. Why a GPU is involved at all (true of *both* routes)

Worth stating plainly, because "hosted" doesn't mean "no GPU" — it means *someone else's* GPU, billed by the token.

Generating one token from a 70B model requires reading **all ~70 GB of FP8 weights out of memory**. That is the whole cost model:

| | Memory bandwidth | 70B decode ceiling |
|---|---|---|
| CPU server (typical) | ~50–100 GB/s | **~1 token/sec** |
| 1× L40S | ~864 GB/s | ~12 tokens/sec (if it fit) |
| 4× L40S (`g6e.12xlarge`) | tensor-parallel | tens of tokens/sec, batched |

A 200-token reply on CPU takes roughly three minutes. And Madeleine is harder than a chatbot: §4's loop re-processes a growing context on every iteration, up to **CONFIG** `maxToolCallsPerTurn=16` round trips inside **CONFIG** `turnDeadlineSeconds=120`. CPU inference misses that deadline by two orders of magnitude. There is no configuration of CPU hardware that serves this.

Two further consequences worth internalizing, because they drive §4's economics:

- **70 GB doesn't fit on one 48 GB L40S.** Tensor-parallel across 4 cards is the *minimum viable shape* for the brain, which is why §2 lands on `g6e.12xlarge` and not something smaller. There is no cheaper self-host tier for a 70B.
- **GPUs are only economical when batched.** A GPU amortizes its weight reads across concurrent requests; serving one request at a time wastes almost all of the card. MADELEINE.md §4 sets **CONFIG** `concurrentTurnsPerUser=1`, so early traffic is precisely the worst-case pattern for an owned GPU: a trickle of lonely requests against a card billing 24/7.

---

## 2. Route A — Hosted inference (rent the GPU, pay per token)

**Shape:** `MODEL_BASE_URL` points at a managed Llama 3.3 70B endpoint. No new CDK stack, no ASG, no AMI, no capacity provider. The `assistant` module makes an HTTPS call and gets tokens back.

Two sub-variants, and the difference between them is a data-boundary question, not a performance one:

### A1 — Amazon Bedrock (in-account)

- Same AWS account (`578109959809`), same region, IAM-authenticated, reachable over PrivateLink — **the data never leaves your AWS boundary**, and Bedrock does not train on inputs.
- No infrastructure to own, patch, or scale. Zero idle cost.
- This is what MADELEINE.md §2 already calls the "dev-time bridge and production fallback route." **This document's argument is that it is also the correct production route for a long while** (see §4).
- Trade-offs: per-token price is higher than the third-party market; you are subject to account-level throughput quotas; custom fine-tunes require Bedrock Custom Model Import, which has its own (non-trivial) cost model.

### A2 — Third-party inference API (Together, Fireworks, Groq, Deepinfra, …)

- Typically **cheaper per token than Bedrock and materially faster** (Groq especially on latency), and several host **custom LoRAs cheaply** — directly relevant to the Darija / code-switching gap, which is the one Llama weakness prompting cannot fix.
- Trade-off, and it is the decisive one: **request bodies leave AWS.** That means a vendor DPA, a second availability dependency, and a fresh look at what's in context. Note MADELEINE.md §5 already seals GojoMessages content away from the model entirely, which shrinks — but does not eliminate — the exposure.
- Reasonable posture: **A1 for anything carrying user content; A2 is fair game for evaluation, benchmarking, and LoRA experiments.**

**Operationally, Route A costs one config change and zero new failure modes.** It also keeps M1 off the critical path entirely — MADELEINE.md §9 already notes the bridge unblocks M2 immediately.

---

## 3. Route B — Self-hosted vLLM on EC2 GPU (own the GPU, pay for time)

**Shape:** the `infra/lib/inference-stack.ts` described in MADELEINE.md §2 — a new CDK stack, sibling of [fargate-stack.ts](infra/lib/fargate-stack.ts), holding:

- vLLM (OpenAI-compatible server) in a container on **EC2 launch type** via an ECS capacity provider over a GPU Auto Scaling Group. Fargate cannot do GPUs — this is why it can't reuse the existing service.
- Llama tool-call parsing on (`--tool-call-parser llama3_json --enable-auto-tool-choice`).
- Internal ALB only; security group admits **only** the Fargate service SG. Health check = vLLM `/health`. Nothing public, no data at rest — weights baked into the AMI/EBS, conversations live in Postgres like everything else.
- Brain ASG min 1 / max 2, scaling on `vllm:num_requests_waiting` (queue depth), not CPU.

**What owning it actually buys:**

- **Zero marginal cost per token.** Above a volume threshold this is the only thing that matters (§4).
- **No rate limits or quota tickets**, and latency you control rather than observe.
- **Any weights you want, including your own LoRA**, swapped by redeploying an image.
- **Co-location economics.** This is the underrated one: once the same node is also serving Llama Guard for moderation triage, a vision model for menu ingestion, an embedder for search, *and* the 8B sidekick, one node's utilization looks entirely different from a node running the brain alone.

**What owning it actually costs, beyond the invoice:**

- **Scale-to-zero does not work for the brain.** Loading ~70 GB of weights is a multi-minute cold start, so the prod node is up 24/7 by definition. MADELEINE.md §2's scale-to-zero schedule only ever applies to the dev/sidekick node.
- **A savings plan is a one-year bet on a utilization number you don't have yet.** §2 is right to say "buy after launch, not before" — but that is also a quiet admission that the economics aren't provable in advance.
- **A new CDK stack is new context flags on the deploy.** [scripts/deploy-backend.sh](scripts/deploy-backend.sh) exists in its current shape because CDK context is not sticky and a forgotten flag renders as *module not configured* — that's how Sumsub KYC shipped silently disabled on 2026-07-30. Any inference URL/secret flag must land in `CDK_SECRET_ARGS` **and** be loud when empty, per that file's own comment block. MADELEINE.md §2 already flags this; it is a real cost, not a formality.
- **GPU capacity is not always available.** `g6e` classes can be constrained in a region; an ASG that cannot launch is an outage with no error in your code.

---

## 4. The economics — the actual deciding factor

From [COSTS.md](COSTS.md), the whole of GojoGo today:

| | Monthly |
|---|---:|
| Entire current infra (Fargate + ALB + NAT + RDS + everything) | **~$109** |
| Route B as specced (prod brain `g6e.12xlarge` + sidekick/dev `g6e.xlarge`) | **~$9,000** |

Route B is **~80× the entire current infrastructure bill**, in a document that deliberates $33/mo for a NAT gateway and defers $25/mo of OpenSearch.

### Break-even, parametrically

Assumptions, all marked as estimates and all worth re-deriving once M2 emits real numbers:

- Hosted Llama 3.3 70B blended ≈ **$0.75 per million tokens** — *verify current pricing; do not trust this figure.*
- One Madeleine turn ≈ **30k tokens**, counting context re-sent across loop iterations (§4 trims tool results to **CONFIG** `toolResultMaxItems=8`, which is what keeps this from being far worse).
- ⇒ **~$0.0225 per turn.**

| Turns / month | Route A cost | Route B cost | ≈ DAU at 3 turns/day |
|---:|---:|---:|---:|
| 10,000 | ~$225 | ~$9,000 | ~110 |
| 100,000 | ~$2,250 | ~$9,000 | ~1,100 |
| 200,000 | ~$4,500 | ~$9,000 | ~2,200 |
| **400,000** | **~$9,000** | **~$9,000** | **~4,400 ← break-even** |
| 1,000,000 | ~$22,500 | ~$9,000 | ~11,000 |

**Read the table honestly in both directions.** Below ~4,000 daily actives *actively using Madeleine*, Route B is paying for idle silicon. Above it, Route A is a tax that grows linearly forever while Route B's bill stays flat — at 1M turns/month Route B is 2.5× cheaper, and that gap only widens.

Neither route is "correct." **The volume decides, and the volume is currently unmeasured.** The S3 media bucket holds 16 objects.

---

## 5. What differs in code: almost nothing (and the rules that keep it that way)

The portability is only real if it is maintained deliberately. Four rules:

1. **Nothing outside `ModelClient` may know the route.** No `if (bedrock)` anywhere in the agent loop, the registry, or the executor. One implementation per route, one interface, chosen by config.
2. **Speak OpenAI-compatible chat completions, including tool calls and streaming deltas.** vLLM serves it natively; Bedrock is reached through a thin adapter *inside* the client. The adapter is the seam — keep it thin and keep it there.
3. **No route-specific prompt tuning.** The reason §2 insists on identical weights is so behavior transfers. A prompt that only works on one route has silently made the fallback fictional.
4. **The security model is route-independent.** The `<user_content>` delimiter, the `WRITE_GATED` registry check, and the confirm-token protocol (§5) are all server-side and unchanged by where tokens are generated. **Changing route never changes what Madeleine is allowed to do.** Worth stating because it's the question people ask first about a hosted model, and the answer is that the wall was never in the model.

**CONFIG surface, both routes:** `MODEL_BASE_URL`, `MODEL_NAME`, `SIDEKICK_BASE_URL`, plus credentials by route (IAM role for A1, API key in Secrets Manager for A2, nothing for B beyond SG reachability).

---

## 6. The switch trigger — write it down now, so it isn't a vibe later

Route A is the default. Move to Route B when **all three** hold:

1. **Sustained hosted token spend > ~$3,500/mo for two consecutive months.** Not a spike; the node is a 24/7 commitment and should answer to a 24/7 number. At that spend, a savings-plan `g6e.12xlarge` (≈$4.7k/mo per §10) is within striking distance and closing.
2. **Real measured tokens-per-turn**, replacing the 30k estimate above. M2's ledger already persists every tool call — the instrumentation is free.
3. **At least one second workload ready to share the node** (moderation triage, vision menu ingestion, embeddings, sidekick), so the card isn't serving the brain alone.

Trigger the move *early* — before all three — only for a reason the money can't express: a fine-tune no vendor will serve, or a data-residency requirement Bedrock genuinely cannot meet.

**Do not** move because the hosted route had an outage. That's what min-1/max-2 versus a fallback URL is for, and Route B has outages too — with a pager attached.

---

## 7. Moving between routes

**A → B (planned):** stand the inference stack up alongside the live hosted route; point a **CONFIG** canary percentage or a staging environment at it first; compare turn-completion rate, p50/p95 turn latency, and tool-call parse failures against the hosted baseline before flipping `MODEL_BASE_URL`. Keep the hosted credentials configured — they become the fallback the moment they stop being the default.

**B → A (unplanned, i.e. the outage path):** this is the reason the adapter stays maintained. A failover that has never been exercised is not a failover; exercise it on a schedule, not during an incident.

**Either direction, the same discipline:** because MADELEINE.md §3 persists conversations as `AssistantMessage` rows rather than raw model context, a mid-flight route change loses at most one turn. It never loses a conversation.

---

## 8. Recommendation

**Amend MADELEINE.md decision #2 — not to change the decision, but to change the default.**

Current wording makes self-hosting the production answer and Bedrock the "dev-time bridge and production fallback." At GojoGo's actual scale that is backwards by roughly two orders of magnitude. Proposed wording:

> The model is **Llama 3.3 70B behind a `ModelClient` interface**. Production runs on **hosted inference (Bedrock)** until the §6 switch trigger fires; **self-hosted vLLM on AWS GPU is the documented scale-out**, built when volume pays for it. The interface makes this a config change, and the weights are identical either way.

Concretely, that means:

- **M1 comes off the critical path.** MADELEINE.md §9 already says the bridge unblocks M2 immediately; this makes that permanent rather than temporary, and removes one CDK stack — and one class of forgotten-context-flag failure — from the launch path.
- **M2 ships with token instrumentation from day one**, because §6's trigger is worthless without it.
- **The inference stack stays specced and unbuilt.** MADELEINE.md §2 remains the design; this file is the schedule.

The cost of being wrong in this direction is a hosted bill that grows for a month or two longer than optimal. The cost of being wrong in the other direction is $9,000/mo against a $109/mo account, committed before a single user has typed anything to Madeleine.
