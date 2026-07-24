# Private-RDS + NAT migration — runbook

Moves RDS off the public internet into a private VPC (App Runner reaches it via a
VPC connector; a NAT Gateway keeps Cognito/Apple/APNs/SNS reachable). This could
**not** be done in one `cdk deploy` for two reasons, both now handled:

1. **CDK cross-stack export deadlock** — renaming the DB (`PostgresV3`→`V4`) tries
   to delete CloudFormation exports that `GojoGoAppStack` imports. Solved by a
   **Phase 1** deploy that decoupled AppStack from those exports (**already done +
   deployed**, 2026-07-24 — the live AppStack pins the DB to the V3 secret ARN +
   endpoint as literals instead of importing them).
2. **Missing IAM permissions** — the `gojogo-builder` deploy user could create a
   VPC/subnets/routes but **not** a NAT Gateway, EIP, Internet Gateway, or VPC
   endpoints. Added to [iam-policy-milestone1.json](../iam-policy-milestone1.json)
   (statement `Ec2VpcNetworkingForPrivateRds`) — **you must apply this v7 policy as
   an admin/root principal before Phase 2** (`gojogo-builder` cannot grant itself
   permissions).

## Current state (as of 2026-07-24)

- **Fast feed is LIVE** — the ranked-feed + Cache-Control backend image is rolled;
  iOS prefetch ships with the app build. None of that depended on this migration.
- **RDS is still public** (password-protected), unchanged. No data was lost.
- **Phase 1 is deployed** — live `GojoGoAppStack` is the decoupled version.
- The repo's `data-stack.ts` / `app-stack.ts` / `bin/gojogo.ts` now hold the
  **Phase 2 target** (V4 private DB + NAT + connector + autoscaling). So **repo ≠
  deployed for these two stacks** until you run Phase 2.

## Phase 2 — run this (destructive: replaces the DB, ~15 min downtime, +~$33/mo)

```bash
# 0. FIRST (admin/root, one time): apply the updated IAM policy so the deploy user
#    can create NAT/EIP/IGW/VPC-endpoints. e.g.:
aws iam create-policy-version \
  --policy-arn arn:aws:iam::578109959809:policy/GojoGoMilestone1Policy \
  --policy-document file://iam-policy-milestone1.json --set-as-default

# 1. Deploy both stacks together (CDK orders DataStack first). This REPLACES the
#    RDS instance into the private VPC (Postgres data reset — test rows only),
#    creates the NAT + gateway endpoints, and switches App Runner onto the VPC
#    connector. The V3 export deadlock is gone because Phase 1 already removed the
#    imports from the deployed AppStack.
export PATH="$HOME/.npm-global/bin:$PATH"
cd infra && cdk deploy GojoGoDataStack GojoGoAppStack --require-approval never

# 2. Roll the backend so it reads the new DB host/secret (App Runner reads env at
#    startup; the AppStack update triggers a deploy, but force it to be sure):
aws apprunner start-deployment \
  --service-arn arn:aws:apprunner:us-east-1:578109959809:service/gojogo-backend/a33d8b2ac276407babdfdb27a5c2a940
```

## Verify

```bash
# Backend healthy again (Flyway recreated the empty schema on the new DB):
curl -s -o /dev/null -w "%{http_code}\n" https://f6kp8hx2j2.us-east-1.awsapprunner.com/actuator/health   # 200
# RDS is now private:
aws rds describe-db-instances \
  --query 'DBInstances[?contains(DBInstanceIdentifier,`postgres`)].PubliclyAccessible'                    # false
```
A successful sign-in from the app proves Cognito/Apple still resolve **through the
NAT** — that is the exact thing the original (reverted, NAT-less) attempt failed.

## If Phase 2 fails and you want to abandon it

The live AppStack (Phase 1) is healthy and self-contained. To return the repo to a
clean single-DB baseline, restore the original DB reference in `app-stack.ts`
(`props.database` instead of the pinned V3 literals) and `git checkout` the
`data-stack.ts` / `bin/gojogo.ts` from before this migration, then
`cdk deploy GojoGoAppStack`.

## Notes

- One NAT Gateway (single-AZ) — bump `natGateways: 2` in `data-stack.ts` for
  AZ-redundant egress before a real launch.
- The old `gojogo/db-credentials-v3` secret is scheduled for deletion when V3 is
  removed; the new DB uses `gojogo/db-credentials-v4` (App Runner re-wires
  automatically — nothing to edit by hand).
