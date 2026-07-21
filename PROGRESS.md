# GojoGo — Build Progress

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full architecture and milestone plan. This file tracks what's actually done.

## Environment — ready

- **AWS account:** `578109959809`, region `us-east-1`
- **IAM user:** `gojogo-builder`, policy `GojoGoMilestone1Policy` (now at **v4** — Milestone 1 added: SSM write on `/cdk-bootstrap/*`, `ec2:DescribeRouteTables`/`DescribeInternetGateways`/`DescribeVpnGateways` for CDK VPC lookup, `iam:CreateServiceLinkedRole` for App Runner. [iam-policy-milestone1.json](iam-policy-milestone1.json) matches the live v4.)
- **Local tools:** Java 23, Maven 3.9.16, AWS CLI 2.36.5, CDK 2.1132.0 (`~/.npm-global/bin/cdk` — may need `export PATH="$HOME/.npm-global/bin:$PATH"` in non-login shells)
- **CDK bootstrapped** in us-east-1 (CDKToolkit stack live)

## Milestone status

- [x] **Milestone 1 — Backend skeleton + auth** ✅ done, deployed, verified end-to-end
- [ ] **Milestone 2 — Profiles + social API** ← next
- [ ] Milestone 3 — Media upload
- [ ] Milestone 4 — iOS wiring
- [ ] Milestone 5 — Buffer / hardening

## What's deployed (Milestone 1)

| Thing | Value |
|---|---|
| API base URL | `https://pmv3e2g3yv.us-east-1.awsapprunner.com` |
| Health check | `GET /actuator/health` (public) |
| Session endpoint | `POST /v1/auth/session` with `Authorization: Bearer <Cognito ID token>` → creates/fetches profile row |
| Cognito user pool | `us-east-1_ImKOJoJaA` (`gojogo-users`), issuer `https://cognito-idp.us-east-1.amazonaws.com/us-east-1_ImKOJoJaA` |
| Cognito app client | `5gouehsu6bgaur82gcebiubvt0` (`gojogo-ios`, no secret, SRP + USER_PASSWORD_AUTH enabled) |
| RDS Postgres 16 | `gojogodatastack-postgres9dc8bb04-eudbfwduhm5c.ccpumiyo88o1.us-east-1.rds.amazonaws.com:5432/gojogo`, user `gojogo`, db.t4g.micro, default VPC, public (dev-only) |
| ECR repo | `578109959809.dkr.ecr.us-east-1.amazonaws.com/gojogo-backend` (`:latest` deployed) |
| App Runner service | `gojogo-backend`, arn `...service/gojogo-backend/ff8ba66ef00142e3839deca19ec8285c`, 1 vCPU / 2 GB |
| CloudFormation stacks | `GojoGoAuthStack`, `GojoGoDataStack`, `GojoGoEcrStack`, `GojoGoAppStack` (+ `CDKToolkit`) |

**DB password:** in gitignored `infra/.env.deploy` (also set as App Runner env var `DB_PASSWORD`). Needed as `--parameters <Stack>:DbPassword=...` when redeploying `GojoGoDataStack` or `GojoGoAppStack`.

## Code layout

- `backend/` — Spring Boot 3.5 + Spring Modulith 1.4, Java 21. Modules: `auth` (session endpoint), `profile` (owns `profile.user_profile`, public API `ProfileApi`), `social` + `media` (empty shells). `ModularityTests` enforces module boundaries in the build. Flyway migrations in `src/main/resources/db/migration` create the `profile`/`social`/`media` schemas.
- `infra/` — CDK TypeScript app, four stacks (see table above). `cdk deploy` falls back to current credentials (the builder user can't assume the CDK roles — expected, fine).
- `.github/workflows/deploy-backend.yml` — tests → Jib build/push to ECR → `apprunner start-deployment` on push to `main` touching `backend/`.

## Verified end-to-end (2026-07-22)

curl flow: `cognito-idp sign-up` → `admin-confirm-sign-up` → `initiate-auth` (USER_PASSWORD_AUTH) → `POST /v1/auth/session` with the ID token → `200` with profile row (repeat call returns same `profileId`; no token → `401`). Test user `gojogo-m1-test@example.com` exists in the pool.

## Known issues / dev shortcuts to revisit

- **RDS is publicly accessible** with 5432 open to the world (password-protected). Forced by the scoped IAM policy (no VPC/NAT/VPC-connector permissions). Fix when moving to ECS/private networking.
- **DB password is a plaintext App Runner env var + local file** — no Secrets Manager permissions in the policy. Migrate to Secrets Manager when the policy allows.
- **GitHub Actions workflow is written but untested** — needs repo secrets `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (gojogo-builder's keys) added on GitHub, then a push to `main` to prove it. Until then, manual deploy: `cd backend && mvn -B -DskipTests compile jib:build -Djib.image=578109959809.dkr.ecr.us-east-1.amazonaws.com/gojogo-backend:latest -Djib.to.auth.username=AWS -Djib.to.auth.password="$(aws ecr get-login-password --region us-east-1)"` then `aws apprunner start-deployment --service-arn <arn above>`.
- **Signup requires `admin-confirm-sign-up`** (or the emailed code) — fine for dev; decide verified-email UX before launch.
- App Runner min instance count is 1 → the service bills ~24/7 at this size (~$25/mo with RDS). `aws apprunner pause-service` when idle to save money.
- Milestone 1 work is **not yet committed to git**.

## To resume in a new session

Say: *"Read PROGRESS.md and ARCHITECTURE.md, start Milestone 2."* Everything needed is in those two files.
