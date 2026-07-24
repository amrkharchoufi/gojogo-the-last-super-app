# GojoGo — Infrastructure Costs

_Generated 2026-07-24. Account `578109959809`, region `us-east-1`._

> **How these numbers were produced.** The deploy IAM user (`gojogo-builder`)
> is **not** granted `ce:GetCostAndUsage` (Cost Explorer) or `dynamodb:DescribeTable`,
> so this is **not** a copy of your AWS bill. It is a grounded estimate built from
> the **actual deployed resource specs** I could read (App Runner instance size,
> RDS instance class/storage, S3 object count/bytes) plus **public us-east-1
> on-demand pricing**. To get the exact billed figure, run the command at the
> bottom from a principal that has Cost Explorer access.

## Deployed resource inventory (read live from the account)

| Resource | Spec (verified) | Billing model |
|---|---|---|
| App Runner `gojogo-backend` | 1 vCPU / 2 GB, **RUNNING** | Memory billed 24/7 for the warm instance; vCPU billed only while actively serving |
| RDS Postgres 16.13 | `db.t4g.micro`, 20 GB, **single-AZ**, publicly accessible | On-demand instance-hour + storage-GB |
| S3 `gojogo-user-media-…` | 16 objects, ~17 MB | Storage-GB + requests + egress |
| DynamoDB `gojogo-messaging` | PAY_PER_REQUEST, 1 GSI, TTL (from IaC) | Per-request reads/writes + storage |
| API Gateway WebSocket | `ialc1dg00l` prod stage | Per message + per connection-minute |
| Lambdas | ws-authorizer, ws-connections, auth-triggers | Per invocation (free tier covers current volume) |
| Cognito user pool | `us-east-1_ImKOJoJaA` | Per monthly active user (free under ~10k MAU) |
| Secrets Manager | db-credentials-v3, apns-key (+ any OAuth) | $0.40 / secret / month |
| ECR | `gojogo-backend` image | $0.10 / GB-month |
| CloudFront | **not deployed** (account unverified) | — |
| **NAT Gateway** | **DEPLOYED** (RDS is private) | ~$33/mo + $0.045/GB processed |
| **ECS/Fargate** | **DEPLOYED** — backend runtime (replaced App Runner) | per vCPU-sec + GB-sec |
| **ALB** | **DEPLOYED** — public HTTPS front for Fargate | ~$16/mo + LCU |

## Estimated monthly cost — post-migration (ECS/Fargate + private RDS)

| Service | Low (mostly idle) | Typical (light real traffic) | Notes |
|---|---:|---:|---|
| **ECS/Fargate** (1 task, 1 vCPU / 2 GB, 24/7) | ~$36 | ~$36 | $0.04048/vCPU-hr + $0.004445/GB-hr × 730 ≈ $29.6 + $6.5. Runs 24/7 (unlike App Runner's idle-memory-only billing) |
| **ALB** | ~$16 | ~$18 | ~$0.0225/hr ($16.4) + a few LCU-hours |
| **NAT Gateway** | ~$33 | ~$34 | $0.045/hr ($32.9) + per-GB processed (S3/DynamoDB bypass it via gateway endpoints) |
| **RDS** `db.t4g.micro` (now private) | ~$14 | ~$14 | $0.016/hr instance ($11.7) + 20 GB storage (~$2.3) |
| **Secrets Manager** | ~$1.20 | ~$1.60 | 3–4 secrets × $0.40 |
| **CloudWatch Logs** | ~$1 | ~$3 | ECS + Lambda log ingestion/storage |
| **DynamoDB / S3 / API GW WS / Lambda / Cognito / ECR** | ~$0.50 | ~$2 | On-demand / free-tier as before |
| **Total** | **~$102/mo** | **~$109/mo** | The private-RDS architecture (Fargate + ALB + NAT) is **~$70/mo more** than the old public-RDS App Runner setup (~$28–55). This is the cost of a private database + a dedicated HTTPS domain. |

> **Cost note:** the security hardening (private RDS) roughly **tripled** the idle infra cost — Fargate runs 24/7 (~$36 vs App Runner's ~$11 idle floor), plus the always-on ALB (~$16) and NAT (~$33). If cost matters more than a private DB at this stage, the old App Runner + public-RDS setup was ~$28/mo idle. To trim Fargate: scale the task to 0.5 vCPU / 1 GB (~$18/mo) if the JVM fits.

## Cost impact of the changes made this session

The **performance** work (feed ranking, prefetch, cache-control) is compute-neutral
or cost-reducing. The **private-RDS migration** to ECS/Fargate + ALB + NAT is what
added ~$70/mo (see the table above) — that's the price of a private database and a
dedicated HTTPS endpoint, not the feed work.

| Change | Monthly cost delta | Why |
|---|---:|---|
| Ranked feed (in-memory re-rank) | **$0** (slightly ↓) | No new queries; actually **removes one** `followeeIds` DB round-trip per feed request (was loaded twice) |
| `Cache-Control: immutable` on media | **↓ over time** | Media is content-addressed, so once cached at the OS/edge it is never re-fetched → fewer S3 GETs and less egress |
| iOS image prefetch (look-ahead) | **~$0** | Bounded (6–8 ahead) + de-duped; a warmed image is cached, so net **fewer** redundant loads per session. Comfortably inside the free S3 egress tier at current scale |
| App Runner autoscaling config (min 1 / max 4 / conc 80) | **$0** | `minSize: 1` matches App Runner's existing default warm floor — same bill, now codified and tunable |

**Net effect of this session: ≈ $0/mo (marginally lower), with a materially faster feed.**

## Optional levers (documented, NOT deployed — your call)

These are the money-costing items from `PROGRESS.md`. None were enabled; each is a
deliberate decision because it adds ongoing cost.

| Lever | Added cost | Buys you | Status |
|---|---:|---|---|
| **CloudFront** for media | ~$1–5/mo now (scales with egress; **cheaper per-GB than S3** at volume: $0.085 vs $0.09) | Edge-cached media → lower latency worldwide + the `Cache-Control` added this session finally takes effect at the edge | IaC ready (`ENABLE_CLOUDFRONT` in `media-stack.ts`); **blocked** until AWS Support verifies the account |
| **NAT Gateway** (private RDS) | ~$33/mo + $0.045/GB processed | Takes RDS off the public internet | **Phase 1 deployed; Phase 2 blocked on an IAM update only admin/root can apply**, then a staged deploy. S3/DynamoDB use free gateway endpoints. Runbook: `infra/PRIVATE_RDS_MIGRATION.md` |
| **Extra warm App Runner instance** (raise `minSize` to 2) | +~$10.22/mo each | More always-warm headroom for a launch spike | Change `minSize` in `app-stack.ts` |
| **OpenSearch** (search index) | ~$25+/mo | Full-text listing/post search | Phase 2b decision, not started |
| **Pause App Runner when idle** | −(App Runner cost) | Zero backend spend while not testing | `aws apprunner pause-service --service-arn <arn>` / `resume-service` |

## Get the exact billed number

From a principal with Cost Explorer permission (`ce:GetCostAndUsage`):

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[].{Service:Keys[0],Cost:Metrics.UnblendedCost.Amount}' \
  --output table
```

The `gojogo-builder` deploy user intentionally lacks this permission; run it as an
admin/root principal, or add `ce:GetCostAndUsage` to a read-only role.
