# Backend → ECS/Fargate migration (private RDS, external DNS)

Replaces the App Runner backend with **ECS/Fargate inside the VPC**, reaching the
**private** RDS directly, behind an **ALB** that terminates HTTPS. This is the
proper private-RDS path (App Runner's VPC egress proved unstable — see
PRIVATE_RDS_MIGRATION.md). DNS is external to AWS, so the cert + records are
added at your DNS provider.

Stack: [lib/fargate-stack.ts](lib/fargate-stack.ts) (built as `GojoGoFargateStack`).

## What's already built
- `GojoGoFargateStack`: ECS cluster, Fargate task (same image/env/secrets as App
  Runner, task + execution roles), service in the private subnets using the SG the
  RDS already allows, internet-facing ALB, HTTPS listener (imported cert), target
  group health-checking `/actuator/health/liveness`, HTTP→HTTPS redirect.
- IAM: `iam-policy-milestone1.json` now grants ecs/elb/acm/route53/logs + PassRole
  to ECS tasks.

## Steps (each `$VAR` is filled in as you go)

**0. Apply the IAM policy (admin/root — once):**
```bash
aws iam create-policy-version \
  --policy-arn arn:aws:iam::578109959809:policy/GojoGoMilestone1Policy \
  --policy-document file://iam-policy-milestone1.json --set-as-default
```

**1. Request the ACM cert** (us-east-1) for your API host, e.g. `api.example.com`:
```bash
aws acm request-certificate --domain-name "$DOMAIN" \
  --validation-method DNS --region us-east-1 --query CertificateArn --output text
# → $CERT_ARN
aws acm describe-certificate --certificate-arn "$CERT_ARN" --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord'
# → gives {Name, Type: CNAME, Value}
```
Add that **CNAME** at your DNS provider. ACM validates automatically once it
propagates (minutes–hours); wait until:
```bash
aws acm describe-certificate --certificate-arn "$CERT_ARN" --region us-east-1 \
  --query 'Certificate.Status' --output text   # → ISSUED
```

**2. Deploy the Fargate stack** (needs the backend image already in ECR — it is):
```bash
export PATH="$HOME/.npm-global/bin:$PATH"
cd infra && cdk deploy GojoGoFargateStack \
  -c domainName="$DOMAIN" -c certificateArn="$CERT_ARN" --require-approval never
# outputs: AlbDnsCnameTarget = gojogo-alb-....us-east-1.elb.amazonaws.com
```

**3. Point your domain at the ALB** — add a **CNAME** `api.example.com` →
`$ALB_DNS` at your DNS provider (or an ALIAS if your provider supports it).

**4. Point the app at the new URL** — set `apiBaseURL` in
`GojoGo/CoreNetworking/BackendConfig.swift` to `https://$DOMAIN`, rebuild the app.
(The WebSocket `messagingSocketURL` is unchanged — separate API Gateway.)

**5. Verify:**
```bash
curl -s -o /dev/null -w "%{http_code}\n" https://$DOMAIN/actuator/health   # 200 (hits private RDS)
aws rds describe-db-instances --query 'DBInstances[?contains(DBInstanceIdentifier,`postgres`)].PubliclyAccessible'  # false
```
A sign-in from the app confirms Cognito/Apple resolve through the NAT.

**6. Retire App Runner** once Fargate is verified:
```bash
cd infra && cdk destroy GojoGoAppStack --force
```

## Notes
- Cost vs App Runner: ~similar compute + an ALB (~$16/mo) + the NAT (~$33/mo).
- The RDS stays private (`PostgresV4`, PRIVATE_WITH_EGRESS subnets). Data is empty
  (reset during the migration) — the app recreates its schema via Flyway.
