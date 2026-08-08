#!/usr/bin/env python3
"""Sidekick eval — MADELEINE.md §2's small model.

Scores the three bounded jobs the sidekick actually does (triage, tool-result
summarization, conversation titles) rather than the agent loop it is explicitly
forbidden from running.

The scoring is mechanical on purpose — substring presence, label match, length.
No LLM judge: judging a small model with a large one imports the large model's
opinions into a decision about cost, and the properties that matter here
(did the name survive, did a price get invented, is it short) are all checkable
without one.

Usage:
    export AWS_BEARER_TOKEN_BEDROCK=$(cat ~/.bedrock_key)
    ./run_sidekick.py --model mistral.ministral-3-8b-instruct
    ./run_sidekick.py --model ... --json results/sidekick/ministral-8b.json
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

from run_eval import Client, DEFAULT_BASE_URL  # same transport, same auth story

HERE = Path(__file__).parent

from prompts import SIDEKICK_PROMPTS as PROMPTS, TRIAGE_LABELS  # noqa: F401


def score(case, out):
    """Mechanical checks. Returns (failures, warnings)."""
    failures, warnings = [], []
    text = (out or "").strip()

    if not text:
        return ["empty response"], warnings

    if case["job"] == "TRIAGE":
        # Tolerate a trailing period or stray casing; reject prose.
        got = text.strip().strip(".").upper()
        if got != case["want"]:
            if case["want"] in got and len(got) < 40:
                warnings.append(f"label buried in prose: {text[:50]!r}")
            else:
                failures.append(f"wanted {case['want']}, got {text[:40]!r}")
        elif len(text) > len(case["want"]) + 2:
            warnings.append("label not bare")

    for frag in case.get("mustContain", []):
        if frag.lower() not in text.lower():
            failures.append(f"dropped {frag!r}")

    for frag in case.get("mustNotContain", []):
        if frag.lower() in text.lower():
            # The load-bearing check: a fact that is not in the source.
            failures.append(f"HALLUCINATED/malformed {frag!r}")

    cap = case.get("maxChars")
    if cap and len(text) > cap:
        warnings.append(f"{len(text)} chars over {cap}")

    if case.get("langHint") == "fr" and not any(
        w in text.lower() for w in ("é", "è", "à", "ç", "vélo", "recherche", "occasion", "achat", "un ", "de ")
    ):
        warnings.append("may not be French")

    return failures, warnings


def main():
    ap = argparse.ArgumentParser(description="Madeleine sidekick eval")
    ap.add_argument("--model", required=True)
    ap.add_argument("--base-url", default=os.environ.get("MODEL_BASE_URL", DEFAULT_BASE_URL))
    ap.add_argument("--json")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    api_key = os.environ.get("AWS_BEARER_TOKEN_BEDROCK") or os.environ.get("BEDROCK_API_KEY")
    if not api_key:
        sys.exit("Set AWS_BEARER_TOKEN_BEDROCK.")

    cases = json.loads((HERE / "sidekick.json").read_text())["cases"]
    client = Client(args.base_url, api_key, args.model, timeout=60)

    print(f"\n  model  {args.model}\n  cases  {len(cases)}\n")
    rows, passed = [], 0

    for c in cases:
        user = c.get("input") or json.dumps(c.get("source"), ensure_ascii=False)
        messages = [
            {"role": "system", "content": PROMPTS[c["job"]]},
            {"role": "user", "content": user},
        ]
        started = time.time()
        try:
            resp = client.chat(messages, tools=[])
            msg = resp["choices"][0]["message"]
            out = (msg.get("content") or "").strip()
            usage = resp.get("usage") or {}
            tokens = usage.get("prompt_tokens", 0) + usage.get("completion_tokens", 0)
            err = None
        except Exception as exc:
            out, tokens, err = "", 0, f"{type(exc).__name__}: {str(exc)[:120]}"
        secs = time.time() - started

        failures, warnings = ([err], []) if err else score(c, out)
        ok = not failures
        passed += ok
        print(f"  {c['id']:<26}{'PASS' if ok else 'FAIL'}  {secs:>5.1f}s {tokens:>6} tok")
        if args.verbose and out:
            print(f"        {out[:150]!r}")
        for f in failures:
            print(f"        ✗ {f}")
        for w in warnings:
            print(f"        ~ {w}")

        rows.append({"id": c["id"], "job": c["job"], "pass": ok, "failures": failures,
                     "warnings": warnings, "seconds": round(secs, 2), "tokens": tokens,
                     "output": out})

    n = len(rows) or 1
    times = sorted(r["seconds"] for r in rows)
    halluc = sum(1 for r in rows for f in r["failures"] if "HALLUCINATED" in f)
    summary = {
        "model": args.model, "passed": passed, "total": len(rows),
        "hallucinations": halluc,
        "meanTokens": round(sum(r["tokens"] for r in rows) / n, 1),
        "p50Seconds": round(times[len(times) // 2], 2),
        "maxSeconds": round(max(times), 2),
    }
    print(f"\n  {passed}/{len(rows)} passed")
    print(f"  hallucinated facts   {halluc}   ← the one that poisons the brain's context")
    print(f"  mean tokens / call   {summary['meanTokens']}")
    print(f"  p50 / max latency    {summary['p50Seconds']}s / {summary['maxSeconds']}s\n")

    if args.json:
        out = Path(args.json)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps({"summary": summary, "cases": rows}, indent=2, ensure_ascii=False))
        print(f"  wrote {out}\n")

    sys.exit(0 if passed == len(rows) else 1)


if __name__ == "__main__":
    main()
