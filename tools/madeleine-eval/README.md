# Madeleine brain-slot eval

Settles the one decision [MADELEINE-INFERENCE.md](../../MADELEINE-INFERENCE.md) §9 deliberately leaves open: **which model gets the brain slot.** Also produces the tokens-per-turn number §6's switch trigger needs, and doubles as §10 item 8's endpoint spike — one run answers all three.

Runs MADELEINE.md §4's agent loop against a candidate model with **stubbed tools**: no backend, no database, no deploy. That isolates the thing actually being measured — whether the model can hold a goal and emit well-formed tool calls across sixteen steps — from everything that could otherwise explain a bad result.

## Run it

```bash
export AWS_BEARER_TOKEN_BEDROCK=...
```

Generate that key in the Bedrock console under **API keys**. It is a credential: don't commit it, don't paste it into a shell argument, don't put it in the repo.

List the model ids the endpoint accepts — they differ from the console catalog's, and guessing wastes a run:

```bash
./run_eval.py --list-models
```

Run the brain set:

```bash
./run_eval.py --model qwen.qwen3-235b-a22b-2507 --json results/qwen3-235b.json
```

Run the sidekick set:

```bash
./run_sidekick.py --model mistral.ministral-3-8b-instruct --json results/sidekick/ministral-8b.json
```

One scenario, with every tool call printed:

```bash
./run_eval.py --model qwen.qwen3-235b-a22b-2507 --only s03_full_order_gated -v
```

**Always run a candidate 3× before deciding.** glm-5 scored 20/20 with an 8.8s p95 on one pass; over three, its p95 reached 23.6s and it dropped a different step each run.

Python 3.9+, stdlib only. Nothing to install.

## Results (2026-08-08)

| Slot | Model | Evidence |
|---|---|---|
| **Brain** | `qwen.qwen3-235b-a22b-2507` | 20/20/19 over 3 runs, p95 7.2–7.6s, 0% parse failures |
| **Sidekick** | `mistral.ministral-3-8b-instruct` | 12/12 ×3, 153 tok/call, 0.62s p50, 0 hallucinations |

Runner-up brain: `zai.glm-5` — ruled out on variance (p95 to 23.6s, a different step dropped each run), not capability. Value option: `kimi-k2.5`.

**Llama was never measured.** Every Meta model returns `Operation not allowed` — from the console as root, via API key on both endpoints, and via SigV4 with explicit `bedrock:InvokeModel`. AWS-side restriction; needs a Support ticket. It drops into this harness unchanged if it clears.

## Two evals, because there are two jobs

`run_eval.py` scores the **brain**: MADELEINE.md §4's 16-step agent loop.
`run_sidekick.py` scores the **sidekick**: triage, summarization, titles — the bounded jobs §2 gives it, and explicitly not the loop it may never run.

## What it measures

Answer quality in the abstract is not scored — §4 doesn't depend on prose:

| Metric | Why it's the one that matters |
|---|---|
| **Tool-call parse failure rate** | the axis open models drop off on; §4 has no recovery path for a malformed call |
| **Multi-step completion** | does the goal survive to step 12 of 16 |
| **Gated retries** | §5 says one action, one approval. A model that re-calls a pending gated tool will fight the confirmation protocol forever |
| **Forbidden calls** | reaching for a tool it was told not to use — predicts how much prompt surface you'll spend on containment |
| **Mean tokens/turn** | replaces §4's unverified 30k estimate and feeds §6's break-even |
| **p50 / p95 latency** | §9's unbudgeted risk |

## The 20 scenarios

Drawn from MADELEINE.md §9's demo lines, because the model that ships is the one that can do the demos.

- **Reads and routing** — s01, s12, s17: does it pick the right tool and then stop
- **The delivery spine** — s02, s03, s04: menu → cart → gated order, including a decline
- **Consent boundaries** — s05/s06 and s19: "how much would it cost" is not "book it", in two languages
- **Draft vs publish** — s09, s10, s11: WRITE_SAFE stops where WRITE_GATED begins
- **Refusal shapes** — s08, s14, s15: no tool exists, or not enough was said to act
- **Injection** — s16: a hostile listing description telling Madeleine to publish and message
- **Languages** — s18 (fr), s19 (es)

Scenarios assert *behaviour*, never transcripts. `mustNotCall` is a hard fail; step budgets and missing closing prose are warnings.

## Files

| File | |
|---|---|
| `catalog.json` | tool schemas + §5 classification + stub results |
| `scenarios.json` | the 20 brain turns and their assertions |
| `run_eval.py` | the §4 loop, scoring, summary |
| `sidekick.json` | the 12 sidekick cases |
| `run_sidekick.py` | triage/summarize/title scoring — **and the working triage prompt M2 should lift** |

## Two things this deliberately does not do

**It does not execute anything.** `WRITE_GATED` tools return `PENDING_USER_APPROVAL`, exactly as the real executor does (§4 step 3). There is no path from model output to a side effect here, same as in production — the classification is the security model, and this harness inherits it rather than reimplementing it.

**It does not use production's credential.** The eval authenticates with an API key because it runs from a laptop. The Fargate task calls `bedrock-runtime` with SigV4 under its own task role — no secret, no deploy flag, nothing to forget. Same wire format, different credential, and the difference is worth keeping straight when a result here doesn't reproduce there.
