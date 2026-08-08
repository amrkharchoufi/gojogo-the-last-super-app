# MADELEINE — Inference Routes

Companion to [MADELEINE.md](MADELEINE.md) (§2 is the decision this doc expands) and [COSTS.md](COSTS.md) (the bill this decision lands on). MADELEINE.md locks *what* Madeleine is; this file is the decision record for **where the model actually runs**, the two routes for getting there, and the written trigger for moving between them.

Conventions carried over: **CONFIG** marks a server-side policy knob; estimates are marked as estimates. Where this doc refines MADELEINE.md §2, MADELEINE.md gets updated too (SPECS §11.4 convention).

> **Status (updated 2026-08-08): the route is decided — Route A1, Bedrock on-demand.** Self-hosted GPU (Route B) stays specced and unbuilt behind §6's trigger, which takes **M1 off the critical path**. What is *not* decided is **which model** — see §9, now a four-way eval since Llama 4 turned out to be available. §10 is the prerequisite checklist, verified against the live console on 2026-08-08 and **shorter than it was**: Bedrock's model-access step no longer exists, quota defaults are ample, and the only remaining gate — the task-role IAM grant — is written.

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
- This is what MADELEINE.md §2 already calls the "dev-time bridge and production fallback route." **This document's argument is that it is also the correct production route for a long while** (see §4) — and as of the status note above, that is the decision.
- Trade-offs: per-token price is higher than the third-party market; you are subject to account-level throughput quotas; custom fine-tunes require Bedrock Custom Model Import, which has its own (non-trivial) cost model.

**On-demand, never Provisioned Throughput.** Bedrock offers both, and the words matter here: **on-demand** is serverless per-token with no instance and **$0 when idle** — that is the entire reason Route A wins §4. **Provisioned Throughput** is reserved model-unit capacity billed by the hour, which reproduces Route B's economics with none of Route B's control. Anyone reading "hosted" as "we host a model somewhere" and reaching for Provisioned has silently re-bought the $9k/mo problem. On-demand is the route; Provisioned is a Route-B-shaped decision and belongs behind §6's trigger if it is ever taken at all.

**Account gates — these need admin/root, not the deploy user.** Verified 2026-08-07: `aws bedrock list-foundation-models` from `gojogo-builder` returns `AccessDeniedException` (no identity-based policy allows `bedrock:ListFoundationModels`), which is [COSTS.md](COSTS.md)'s least-privilege deploy user behaving exactly as designed. Consequently the following cannot be done by the deploy and are tracked in §10:

- **Bedrock model access must be explicitly enabled per model** in the account. It is off by default.
- The **Fargate task role** needs `bedrock:InvokeModel` / `InvokeModelWithResponseStream` — the *task* role, not `gojogo-builder`.
- **Account TPM/RPM quotas** need checking against §4's loop before launch; an increase is a support ticket with lead time.

This is the same class of blocked-on-IAM item as COSTS.md's NAT phase 2 — plan for it rather than discovering it during M2.

### A2 — Third-party inference API (Together, Fireworks, Groq, Deepinfra, …)

- Typically **cheaper per token than Bedrock and materially faster** (Groq especially on latency), and several host **custom LoRAs cheaply** — directly relevant to the Darija / code-switching gap, which is the one Llama weakness prompting cannot fix.
- Trade-off, and it is the decisive one: **request bodies leave AWS.** That means a vendor DPA, a second availability dependency, and a fresh look at what's in context. Note MADELEINE.md §5 already seals GojoMessages content away from the model entirely, which shrinks — but does not eliminate — the exposure.
- Reasonable posture: **A1 for anything carrying user content; A2 is fair game for evaluation and benchmarking.** European launch languages mean European users and therefore GDPR, which makes "request bodies leave AWS to a third party" a compliance conversation rather than a procurement one — A1 was already the recommendation and this hardens it for production traffic.

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

> **Superseded 2026-08-08 by measurement and real prices.** Both inputs below were estimates and both were wrong in the same direction.
>
> **Measured**, over 60 turns of the chosen stack: **7,165 input + 102 output tokens per turn**. The lopsidedness is the point — an agent loop re-sends a growing context every iteration and emits almost nothing, so input price dominates and output price barely registers.
>
> **Real us-east-1 prices** (fetched 2026-08-08, verify before quoting): qwen3-235b **$0.53/M in, $2.66/M out**; ministral-8b **$0.15/M both ways**.
>
> ⇒ **$0.0041 per turn**, brain and sidekick together (the sidekick is $0.00005 of it — a rounding error, which is its own argument for keeping it).
>
> | Turns/day | Madeleine | + $109 infra |
> |---:|---:|---:|
> | 100 | $12/mo | **$121/mo** |
> | 1,000 | $123/mo | **$232/mo** |
> | 10,000 | $1,234/mo | **$1,343/mo** |
> | 57,000 | $7,035/mo | $7,144/mo |
>
> **Self-host break-even is ~73,000 turns/day** — about 24,000 DAU at 3 turns each, versus the ~4,400 estimated below. The original estimate under-stated Route A's advantage by roughly **17×**. Everything below is left in place because the method is what matters; treat its numbers as superseded arithmetic, not as guidance.

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
2. **Speak OpenAI-compatible chat completions, including tool calls and streaming deltas.** vLLM serves it natively — and so, now, does Bedrock: the **Chat Completions API on the `bedrock-mantle` endpoint** is OpenAI-compatible with streaming, tool calling and multimodal support, and AWS's own framing is that an existing OpenAI SDK codebase moves over by changing the base URL and API key. So the adapter this rule was written to contain may turn out to be **nearly nothing**. Confirm that on your actual model during §10's spike before assuming it; whatever translation does remain lives *inside* `ModelClient` and nowhere else.
3. **No route-specific prompt tuning.** The reason §2 insists on identical weights is so behavior transfers. A prompt that only works on one route has silently made the fallback fictional.
4. **The security model is route-independent.** The `<user_content>` delimiter, the `WRITE_GATED` registry check, and the confirm-token protocol (§5) are all server-side and unchanged by where tokens are generated. **Changing route never changes what Madeleine is allowed to do.** Worth stating because it's the question people ask first about a hosted model, and the answer is that the wall was never in the model.

**CONFIG surface, both routes:** `MODEL_BASE_URL`, `MODEL_NAME`, `SIDEKICK_BASE_URL`, plus credentials by route (IAM role for A1, API key in Secrets Manager for A2, nothing for B beyond SG reachability).

---

## 6. The switch trigger — write it down now, so it isn't a vibe later

Route A is the default. Move to Route B when **all three** hold:

1. **Sustained hosted token spend > ~$3,500/mo for two consecutive months.** Not a spike; the node is a 24/7 commitment and should answer to a 24/7 number. At that spend, a savings-plan `g6e.12xlarge` (≈$4.7k/mo per §10) is within striking distance and closing. On the measured $0.0041/turn that threshold is roughly **28,000 turns/day** — a long way from here, and the first task of that work is comparing GPU providers rather than assuming AWS.
2. **Real measured tokens-per-turn**, replacing the 30k estimate above. M2's ledger already persists every tool call — the instrumentation is free.
3. **At least one second workload ready to share the node** (moderation triage, vision menu ingestion, embeddings, sidekick), so the card isn't serving the brain alone.

Trigger the move *early* — before all three — only for a reason the money can't express: a fine-tune no vendor will serve, or a data-residency requirement Bedrock genuinely cannot meet.

**Do not** move because the hosted route had an outage. That's what min-1/max-2 versus a fallback URL is for, and Route B has outages too — with a pager attached.

---

## 7. Moving between routes

**A → B (planned):** stand the inference stack up alongside the live hosted route; point a **CONFIG** canary percentage or a staging environment at it first; compare turn-completion rate, p50/p95 turn latency, and tool-call parse failures against the hosted baseline before flipping `MODEL_BASE_URL`. Keep the hosted credentials configured — they become the fallback the moment they stop being the default.

**B → A (unplanned, i.e. the outage path):** cheap to keep alive precisely because both ends speak the same wire format (§5 rule 2) — but a failover that has never been exercised is not a failover. Exercise it on a schedule, not during an incident.

**Either direction, the same discipline:** because MADELEINE.md §3 persists conversations as `AssistantMessage` rows rather than raw model context, a mid-flight route change loses at most one turn. It never loses a conversation.

---

## 8. Recommendation

**Amend MADELEINE.md decision #2 — not to change the decision, but to change the default.**

Current wording makes self-hosting the production answer and Bedrock the "dev-time bridge and production fallback." At GojoGo's actual scale that is backwards by roughly two orders of magnitude. Proposed wording:

> The model is **an eval-selected model behind a `ModelClient` interface** (§9). Production runs on **hosted inference — Bedrock on-demand** — until the §6 switch trigger fires; **self-hosted vLLM on AWS GPU is the documented scale-out**, built when volume pays for it. The interface makes both the route and the model a config change.

Concretely, that means:

- **M1 comes off the critical path.** MADELEINE.md §9 already says the bridge unblocks M2 immediately; this makes that permanent rather than temporary, and removes one CDK stack — and one class of forgotten-context-flag failure — from the launch path.
- **M2 ships with token instrumentation from day one**, because §6's trigger is worthless without it.
- **The inference stack stays specced and unbuilt.** MADELEINE.md §2 remains the design; this file is the schedule.

The cost of being wrong in this direction is a hosted bill that grows for a month or two longer than optimal. The cost of being wrong in the other direction is $9,000/mo against a $109/mo account, committed before a single user has typed anything to Madeleine.

---

## 9. The open question: which model

Settling the route unsettles the model, and this is the one thing in MADELEINE.md worth genuinely reopening.

**Read decision #2's original order of reasoning:** *"self-hosted Llama on AWS."* Llama was chosen **because** self-hosting was chosen — open weights are what make self-hosting possible at all. The model followed from the deployment. §8 inverts the deployment; the model therefore has to be re-derived rather than inherited.

**What open weights still buy you, on a hosted route (the real case for Llama):**

- **Price.** Llama 3.3 70B is among the cheaper models on Bedrock. §4's loop re-prefills a growing context every iteration, so per-token price multiplies harder here than in a chat product. A cheap model that passes the eval is worth real money — and it pushes the §6 break-even further out, which is the *good* direction.
- **It is the only choice that keeps Route B alive.** §6's entire switch trigger is dead text under a closed model — you would be on per-token pricing permanently, growing linearly with your own success. Open weights are the option value on scale.
- **The launch languages are inside its supported set.** Scope settled 2026-08-08: **English, French, Spanish** core, plus European neighbours. Llama 3.3's officially supported eight are English, German, French, Italian, Portuguese, Hindi, Spanish, Thai — so the core is first-class and the likely extensions are too. Meta's own caveat is that performance outside that set may not meet their safety and helpfulness thresholds, which makes this a **boundary to hold, not a range to stretch**: adding Arabic, Chinese, Japanese, Russian or Turkish later puts the brain outside its supported envelope and reopens this section. Pin the list; don't leave it as "etc."
- **Fine-tuning remains available but is no longer load-bearing.** An earlier draft of this section rated a Darija / code-switched LoRA as potentially decisive. That was contingent on a single-market launch and is **dropped, not deferred** — the settled language scope is served by stock weights. Open weights still leave the door open; nothing now depends on walking through it.
- **No lock-in at all.** The same weights run on Bedrock, A2 providers, or your own node — the portability §5 protects is *maximal* with an open model.

**What argues against it:** multi-step agentic tool calling is precisely Llama 3.3 70B's weakest axis relative to frontier models, and §4 leans on exactly that — a 16-step loop whose failures touch money. The gating protocol (§5) contains the *blast radius* of a bad decision, but it cannot make a model that loses the thread useful.

**Llama 4 changes the shortlist.** Console check, 2026-08-08, `us-east-1`: **Llama 4 Maverick 17B Instruct** and **Llama 4 Scout 17B Instruct** are both available serverless with cross-region inference, and both list function calling. MADELEINE.md's choice of 3.3 70B was made before they were an option. They are open weights, so every argument above — price, Route B option value, zero lock-in — applies to them unchanged, on a newer generation. **Both enter the eval**; 3.3 70B is now the baseline to beat rather than the presumptive answer.

**Therefore: no default. The eval decides — and with the language scope settled, it decides on essentially one axis.** Llama enters as a strong candidate: its price and its Route B option value are unmatched, and the launch languages sit inside its supported set. What it still has to prove is the thing §4 leans hardest on and the thing open models are weakest at relative to frontier ones — holding a goal and emitting well-formed tool calls across sixteen steps. §10 builds the eval. Measure what actually breaks, not answer quality in the abstract:

| Metric | Why |
|---|---|
| **Tool-call parse failure rate** | the known drop-off axis for open models; §4 has no recovery path for a malformed call |
| **Multi-step completion rate** | does it still hold the goal at step 12 of 16 |
| **Wrong-tool / hallucinated-arg rate** | §5 gates the money, but a wrong `WRITE_SAFE` call still corrupts a cart or a draft |
| **p50 / p95 turn latency** | §9's own risk, below |
| **Blended cost per completed turn** | the number that feeds §4 and §6 |
| **The same turns in French and Spanish** | a smaller axis than it looked before the scope settled, but tool-call fidelity degrades in a second language before prose does — and prose is not what §4 depends on |

### Eval results, 2026-08-08 — first real data

Full 20-scenario run, `bedrock-mantle`, `us-east-1` ([tools/madeleine-eval](tools/madeleine-eval)):

| Model | Pass | Parse fail | Tokens/turn | p50 | p95 | Failed |
|---|---:|---:|---:|---:|---:|---|
| **qwen3-235b-a22b-2507** | **20/20** | 0% | 6,914 | 3.2s | 7.2s | — |
| **glm-5** | **20/20** | 0% | 7,140 | 3.5s | 8.8s | — |
| kimi-k2.5 | 19/20 | 0% | **4,182** | 3.8s | 11.6s | s20 |
| nemotron-super-3-120b | 18/20 | 0% | 9,971 | 4.2s | **6.8s** | s06, s07 |
| minimax-m2.5 | 18/20 | 0% | 7,407 | 6.5s | 24.6s | s02, s20 |
| gpt-oss-120b | 17/20 | 0% | 4,747 | 3.3s | 19.0s | s02, s11, s20 |
| *Llama (all)* | *blocked* | — | — | — | — | *not invocable — see §10* |

Single pass, temperature 0. **Read the stability table below before drawing conclusions from this one** — two of these rankings did not survive repetition.

**Four findings, in order of how much they change the decision:**

1. **Tool-call fidelity is not the differentiator §9 assumed.** Zero parse failures across **247 tool calls and six open-weight models**. The premise that open models drop off on tool-call fidelity — the main argument for paying frontier prices — did not reproduce here at all. Models differ on *judgement*, not on emitting valid JSON.
2. **§4's 30k tokens/turn was 3–7× too high.** Real range is 4.2k–10k. This moves §6's break-even from ~4,400 DAU to roughly **19,000** (see §4). Bedrock is the right answer for far longer than this document originally claimed.
3. **Latency is milder than feared but p95 is the risk.** p50 clusters at 3–4s, which is fine. p95 ranges from 6.8s to **24.6s** — so the §9 latency target belongs on p95, not p50, and minimax-m2.5 is disqualified on that alone.
4. **The one genuinely safety-shaped result:** on s02 ("Get me a couscous and a mint tea from Chez Rachid" — a cart request, not an order), **gpt-oss-120b and minimax-m2.5 both called `place_order`**. The phrasing is admittedly ambiguous, so this is a difference in disposition rather than a clear error: some models escalate toward action, qwen and glm do not. **§5 contained it exactly as designed** — the worst outcome was an unwanted confirmation card, never an unwanted charge. That is the confirmation protocol earning its place, and it is also why disposition, not capability, should pick the brain.

### Stability, 3 runs each — the single sample was misleading

| | qwen3-235b | glm-5 |
|---|---|---|
| Pass across 3 runs | **20, 20, 19** | 19, 18, 20 |
| p50 | **2.9 – 3.1s** | 3.3 – 4.1s |
| **p95** | **7.2 – 7.6s** | **12.6 – 23.6s** |
| Tokens/turn spread | 427 | 371 |
| Distinct flaky scenarios | **1** (s02) | **3** (s04, s13, s20) |

**Recommendation: qwen3-235b for the brain slot.** Not because it scored higher once — because it scores the same every time. Tight variance on every axis, and a p95 that moves by 0.4s across runs.

**glm-5 is ruled out on variance, not on capability.** Its 20/20 and 8.8s p95 in the single run were a lucky sample: the real p95 reaches **23.6s**, three times worse, and it drops a *different* step each run — s13 lost `draft_message`, s04 never reached the gated call. That is precisely the "loses the thread" failure §4's sixteen-step loop cannot tolerate, and a single pass would have hidden it. **This is why §10 item 7 says re-run before deciding.**

**s02 is flaky for qwen too (1 of 3 runs), and that is a prompt finding, not a model finding.** "Get me a couscous and a mint tea from Chez Rachid" reads as an order to some models some of the time, across every model tested. **Action for M2:** the system prompt must state explicitly that fetching items means building a cart, and that only an unambiguous instruction to order reaches `place_order`. Worth fixing in the prompt precisely because §5 already guarantees the blast radius is a confirmation card rather than a charge — this is polish, not a hole.

kimi-k2.5 remains the value option at 40% fewer tokens; worth a stability run of its own if cost becomes the binding constraint.

### The prompt was worth more than the model choice

Both fixes are now in [tools/madeleine-eval/prompts.py](tools/madeleine-eval/prompts.py), which **both runners import** — so the text M2 ships is the exact text that was measured. A prompt kept in a Java constant and copied into an eval drifts from it within a week.

Scores before and after, same scenarios, same models:

| Model | Before | After (2 runs) |
|---|---:|---:|
| qwen3-235b | 20/20/19 | **20/20, 20/20** |
| glm-5 | 19/18/20 | 19/20, **20/20** |
| **gpt-oss-120b** | **17/20** | **20/20, 19/20** |

**gpt-oss-120b went from worst in the field to level with the winner on a prompt change alone.** That reframes the earlier results: part of what looked like model quality was prompt deficiency, and the ranking of the middle of the field should be treated as provisional. It does not change the top pick — qwen3-235b was best before the fix and is still the most *consistent* after it — but it is a caution against reading too much into a two-point gap.

**And the first attempt at the fix made things worse, which is the more useful lesson.** Wording the cart rule as "when both readings are plausible, take the reversible one and ask" dropped qwen to 18/20 and glm-5 to 17/20: models began stopping at the cart even for *"Order me a couscous and have it sent to my home address"*, which is not ambiguous at all. Guarding one direction opened a hole in the other. The fix that worked names **both** verb classes with a contrasting example of each, because abstract rules about ambiguity get over-applied. **Every prompt change needs the full regression, not just the case it targets** — the harness exists to catch exactly this, and it did.

### Sidekick eval, 2026-08-08 — replacing the blocked Llama 3.1 8B

Scored on the three jobs §2 actually gives it (triage, tool-result summarization, titles) via [run_sidekick.py](tools/madeleine-eval/run_sidekick.py), **not** the agent loop it is forbidden to run. Faithfulness is the metric that matters: §4 pipes the sidekick's summary straight into the brain's context, so an invented price is a fact the brain cannot detect.

3 runs each, 12 cases:

| Model | Pass | Tokens/call | p50 | max | Hallucinations |
|---|---:|---:|---:|---:|---:|
| **ministral-3-8b** | **12/12 ×3** | **153** | **0.62s** | **0.92s** | **0** |
| qwen3-32b | 12/12 ×3 | 156 | 0.72s | 1.07s | 0 |
| nemotron-nano-12b | 12/12 ×3 | 161 | 0.66s | 1.25s | 0 |

Also perfect on a single pass: gpt-oss-20b (but **2× the tokens** at 318/call), gemma-3-27b (but a **6.7s** tail), ministral-3-14b.

**Decision: `mistral.ministral-3-8b-instruct`.** Best on every measured axis, and a like-for-like size swap for the 8B it replaces. **Zero hallucinated facts across every model and every run** — the failure mode most feared here simply did not occur, which is the real result: this job is not model-limited.

**It was prompt-limited, and that is the finding to carry into M2.** With bare labels, *"im starving, whats open near me"* failed on **all six models** and the French *"je voudrais commander une pizza"* on five — both routed to MARKETPLACE. Adding one-line definitions per label took every model from 10/12 to 12/12. **M2's triage prompt must define its labels, not merely list them**; the working version is in `run_sidekick.py`'s `PROMPTS["TRIAGE"]` and should be lifted from there rather than rewritten. A cheap fix that would have been read as "small models can't triage" if the eval had stopped at the first run.

**A split is legitimate and probably correct.** These are separate decisions and only one is hard:

- **Sidekick and bounded jobs** — summarization, conversation titles, triage: **`mistral.ministral-3-8b-instruct`**, measured (below). It replaces Llama 3.1 8B, which is as un-invocable as the rest of Meta.
- **The brain** — genuinely open. Llama 3.3 70B enters as a serious contender, not as the incumbent.

*Author's disclosure, since this file will outlive the conversation that produced it: this section was drafted with Claude, an Anthropic model, and Anthropic models are among the candidates on Bedrock. Discount any implicit preference accordingly — the defensible claim here is only that **the eval decides**, which is true whichever model wins.*

### The unbudgeted risk: latency

MADELEINE.md §4 sets **CONFIG** `turnDeadlineSeconds=120` — a *ceiling* before the turn gives up. Nothing anywhere sets a target for what a **typical** turn feels like, and each of up to 16 steps is a network round trip plus re-prefill of a growing context.

This will decide whether Madeleine feels magical or broken more than either the route or the model will. A 40-second wait for "find me a restaurant" loses to the user just tapping the delivery tab. **Add a p50 turn-latency target** as a first-class **CONFIG** alongside the deadline, and let it constrain how many steps the design actually plans for — a loop that *can* run 16 steps should rarely need 4.

---

## 10. Before you start — prerequisites for M2

Nothing here is large. All of it is cheaper before M2 than during it.

### Console findings, 2026-08-08 — this list got shorter

Verified directly in account `578109959809` / `us-east-1`:

1. ~~Enable Bedrock model access.~~ **Gone. The Model access page has been retired** — serverless foundation models auto-enable on first invocation, across all commercial regions. There is no EULA step and nothing to pre-authorize. Access is now governed **purely by IAM and SCPs**, which makes item 2 the only real gate.
2. **Grant the Fargate task role** `bedrock:InvokeModel` + `InvokeModelWithResponseStream`. **Written** — see [fargate-stack.ts](infra/lib/fargate-stack.ts), the statement after the `sns:Publish` grant. Note the two ARN forms: cross-region models are invoked via an **inference profile** (`us.meta.…`, account-scoped) that routes to a **foundation model** in whatever US region has capacity, so a policy naming only one of the two breaks the moment traffic moves. Ships with `./scripts/deploy-backend.sh --infra`.
   - **Bedrock needs no secret** — the task role *is* the credential. So there is no new `-c …SecretArn` flag, and therefore no new instance of the 2026-07-30 forgotten-flag failure. Worth noting because it is the one integration in this codebase that cannot ship half-configured.
3. **Quotas: defaults are ample.** Llama 3.3 70B cross-region shows an AWS default of **800 requests/min** and **600,000 tokens/min** — roughly 50 turns/min and 20 turns/min respectively against §4's loop, far beyond early traffic. **No support ticket needed.** One asterisk: the *applied* account value reads `0` rather than the default, which is either a display convention for "no override" or a genuine zero pending first invocation. It resolves the same way either way — **invoke once, re-read the quota** — which is item 8's spike, so the two collapse into one.

### Remaining one-time gates

- **Meta models are AWS Marketplace-served:** a principal with Marketplace permissions must invoke once to enable the model account-wide.
- **Anthropic models require a use-case form** before first invocation, once per account — only relevant if a Claude model is one of §9's comparison candidates.
- **Other providers' comparison models need their own ARN prefixes** added to the task-role policy before they can be evaluated; it is deliberately scoped to `meta.llama*` today.

### Decisions to make (yours, and they gate the spec)

4. **Amend MADELEINE.md decision #2** to §8's proposed wording, so the spec and this file agree. Its own convention says a refined decision gets written back.
5. **Set the p50 turn-latency target** (§9). A number, in the spec, next to the deadline.
6. ~~Confirm the launch-market language question.~~ **Settled 2026-08-08: English, French, Spanish core, plus European neighbours** — inside Llama 3.3's supported eight, so no fine-tune is needed and §9 comes down to tool-calling reliability alone. **Residual action: write the exact list** into MADELEINE.md rather than leaving "etc."; anything added outside the supported set (Arabic, Chinese, Japanese, Russian, Turkish) reopens §9.

### Build first, before the module (small, high-leverage)

7. **Write the ~20-turn eval.** Draw them from MADELEINE.md §9's demo lines: a federated search, a multi-vertical question, a cart build, a gated order, a declined action, an interrupted turn. This is the single highest-value artifact on the list — it selects the model (§9), it feeds §6's switch trigger, and it becomes the regression suite for every later prompt change. It does not need the `assistant` module to exist. **Shortlist as of 2026-08-08:** Llama 3.3 70B (baseline), Llama 4 Maverick 17B, Llama 4 Scout 17B, plus any non-Meta comparison models chosen — those need their ARN prefixes added to the task-role policy first.
8. **Spike `ModelClient` against the `bedrock-mantle` Chat Completions endpoint** — one class, streaming and one tool call, no module around it. Confirms §5 rule 2's "the adapter may be nearly nothing" on your real model, and de-risks the M2/M3 streaming envelope.
9. **Decide the token-instrumentation shape now.** Input, output, and step count per turn, persisted alongside the `AssistantMessage` rows §3 already writes. §6's trigger and §4's cost model are both worthless without it, and retrofitting counters into a working loop is how they end up approximate.

### Explicitly *not* now

- **M1 / `inference-stack.ts`** — off the critical path per §8. Stays specced.
- **A savings plan or Provisioned Throughput** — both are the $9k/mo commitment wearing different words (§2, §4).
- **Any fine-tune / LoRA** — dropped with the language scope (§9), not deferred. Stock weights cover English/French/Spanish. A fine-tune is an answer to a measured gap; there isn't one.
