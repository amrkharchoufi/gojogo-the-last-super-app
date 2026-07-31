#!/usr/bin/env bash
#
# Deploy the GojoGo backend to ECS/Fargate.
#
#   ./scripts/deploy-backend.sh              # deploy HEAD
#   ./scripts/deploy-backend.sh --list       # what's deployed, and what you can go back to
#   ./scripts/deploy-backend.sh --rollback   # back to the previous revision
#   ./scripts/deploy-backend.sh --infra      # deploy the CDK stack, not the code
#
# Preflight → tests → build + push → new task definition → roll out → health check.
#
# Every deploy pins an **immutable image tag** (the git SHA) into a new task
# definition revision. Nothing ever runs "whatever :latest points at", which is
# what makes rollback real: revision N-1 still references the exact image it was
# built from, so `--rollback` is one command and genuinely goes back.
#
# Other things this encodes so you don't have to remember them:
#
#   * Java 21. The build must run on Corretto 21 even when `java` on PATH is 23 —
#     the Spring Modulith tests fail spuriously on 23. The script finds 21 itself
#     and refuses to run on anything else.
#   * ECS, not App Runner (retired in the Fargate migration).
#   * A clean git tree, so the image tag names code that actually exists. Use
#     --allow-dirty to override; the tag then carries a `-dirty-<ts>` suffix so
#     it can never be confused with the commit.
#   * Flyway runs at startup inside the new task. A failed migration looks like a
#     stalled rollout, which is why this waits for stability *and* health rather
#     than exiting when the API call returns.
#
# CAUTION: a bare `cdk deploy GojoGoFargateStack` resets the service to the task
# definition CDK owns — dropping to image `latest`, and dropping every secret
# whose `-c ...SecretArn` flag you didn't retype. Use `--infra`, which keeps that
# list in one reviewable place and refuses to ship a revision that lost one.
#
set -euo pipefail

# ---------------------------------------------------------------- configuration
# Each is overridable from the environment: AWS_REGION=eu-west-1 ./deploy-backend.sh
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT="${AWS_ACCOUNT:-578109959809}"
ECR_REPO="${ECR_REPO:-${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/gojogo-backend}"
ECS_CLUSTER="${ECS_CLUSTER:-gojogo}"
ECS_SERVICE="${ECS_SERVICE:-gojogo-backend}"
HEALTH_URL="${HEALTH_URL:-https://api.gojogo.app/actuator/health}"

# --- CDK context for --infra --------------------------------------------------
# Every flag `cdk deploy GojoGoFargateStack` reads, in one place. None of these
# are secrets — they are ARNs and hostnames, identifiers for things whose values
# live in Secrets Manager.
#
# They are here because CDK context is not sticky. A flag you forget is not
# "leave it as it was", it is "absent", and the stack renders absent as *module
# not configured*: the task definition comes back without that module's secrets
# and the module falls back or switches off. Forgetting sumsubSecretArn once
# shipped a revision with Sumsub KYC silently disabled (2026-07-30). A list in a
# file can be reviewed; a list in your shell history cannot.
#
# Adding a module that needs a secret? Add its ARN here *and* to CDK_SECRET_ARGS
# below, and --infra will carry it forever after.
CDK_STACK="${CDK_STACK:-GojoGoFargateStack}"
CDK_DOMAIN_NAME="${CDK_DOMAIN_NAME:-api.gojogo.app}"
CDK_CERTIFICATE_ARN="${CDK_CERTIFICATE_ARN:-arn:aws:acm:us-east-1:578109959809:certificate/97477813-a50e-4c57-9634-781ae06cd5a9}"
# `-` not `:-` for the two secret ARNs, unlike everything else here: an
# explicitly empty value has to survive, because "deploy this module
# unconfigured" is a real thing to want in a fresh environment. `:-` would
# helpfully substitute the default back in and make that impossible to express.
SUMSUB_SECRET_ARN="${SUMSUB_SECRET_ARN-arn:aws:secretsmanager:us-east-1:578109959809:secret:gojogo/sumsub-gHmmld}"
STRIPE_SECRET_ARN="${STRIPE_SECRET_ARN-arn:aws:secretsmanager:us-east-1:578109959809:secret:gojogo/stripe-4I84ec}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"

RUN_TESTS=1
WAIT_FOR_ROLLOUT=1
DRY_RUN=0
ALLOW_DIRTY=0
MODE=deploy
ROLLBACK_TARGET=""

# ---------------------------------------------------------------------- output
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; RESET=''
fi

step() { printf '\n%s==>%s %s%s%s\n' "$BOLD" "$RESET" "$BOLD" "$*" "$RESET"; }
info() { printf '    %s\n' "$*"; }
note() { printf '    %s%s%s\n' "$DIM" "$*" "$RESET"; }
warn() { printf '%s  ! %s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
ok()   { printf '%s  ✓ %s%s\n' "$GREEN" "$*" "$RESET"; }
die()  { printf '\n%s  ✗ %s%s\n\n' "$RED" "$*" "$RESET" >&2; exit 1; }

aws_() { aws --region "$AWS_REGION" "$@"; }

usage() {
  sed -n '3,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Modes:
  (default)         Build the current commit and deploy it.
  --list            Show recent task definition revisions, their image tags, and
                    which one is live. This is your rollback menu.
  --rollback [REV]  Redeploy a previous revision — the one before the current if
                    REV is omitted. No rebuild: it redeploys an image that
                    already exists, so it's fast and cannot fail to compile.
  --current         Print the image tag currently deployed, and exit.
  --infra           Deploy the CDK stack, not the code. Carries every context
                    flag the stack reads (see the config block at the top of
                    this file), re-pins the running image instead of letting it
                    default to `latest`, and fails loudly if the new task
                    definition lost a secret the old one had.

Options:
  --skip-tests   Push without running `mvn test`. For redeploying code that
                 already passed; not for a first push of new code.
  --no-wait      Return once ECS accepts the deployment, without waiting for the
                 rollout or health check. You are then on your own for verifying.
  --allow-dirty  Deploy with uncommitted changes. The image tag gets a
                 `-dirty-<timestamp>` suffix so it never impersonates a commit.
  --dry-run      Print every mutating command instead of running it.
  -h, --help     This.

Environment overrides:
  AWS_REGION AWS_ACCOUNT ECR_REPO ECS_CLUSTER ECS_SERVICE HEALTH_URL
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tests)  RUN_TESTS=0 ;;
    --no-wait)     WAIT_FOR_ROLLOUT=0 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    --list)        MODE=list ;;
    --current)     MODE=current ;;
    --infra)       MODE=infra ;;
    --rollback)
      MODE=rollback
      if [[ "${2:-}" =~ ^[0-9]+$ ]]; then ROLLBACK_TARGET="$2"; shift; fi
      ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Unknown option: $1  (--help for usage)" ;;
  esac
  shift
done

# ------------------------------------------------------------------- ecs helpers

# The image ref a given task definition runs, e.g. ...gojogo-backend:b33afe6
taskdef_image() {
  aws_ ecs describe-task-definition --task-definition "$1" \
    --query 'taskDefinition.containerDefinitions[0].image' --output text
}

# Sorted, one per line — so two revisions can be diffed with comm(1). Used by
# --infra to prove a stack deploy didn't drop a module's credentials.
taskdef_secret_names() {
  aws_ ecs describe-task-definition --task-definition "$1" \
    --query 'taskDefinition.containerDefinitions[0].secrets[].name' --output text \
    | tr '\t' '\n' | sort
}

# True if this exact tag exists in ECR. `batch-get-image` prints "None" for a
# miss rather than failing, hence the grep.
ecr_has_tag() {
  aws_ ecr batch-get-image --repository-name "${ECR_REPO##*/}" \
        --image-ids "imageTag=$1" --query 'images[0]' --output text 2>/dev/null \
    | grep -qv '^None$'
}

live_taskdef_arn() {
  aws_ ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
    --query 'services[0].taskDefinition' --output text
}

# Copy the live task definition, swap in a new image, register it as a new
# revision. Everything else — env, secrets, roles, cpu/memory, log config — is
# carried over verbatim, so this can't silently drift from what CDK declared.
register_revision_with_image() {
  local base_arn="$1" new_image="$2"
  # Explicit XXXXXX template: `mktemp -t name` means different things on BSD
  # (macOS) and GNU (the CI runner), and GNU rejects a template without X's.
  local spec; spec="$(mktemp "${TMPDIR:-/tmp}/gojogo-taskdef.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -f '$spec'" RETURN

  aws_ ecs describe-task-definition --task-definition "$base_arn" \
       --query 'taskDefinition' --output json \
    | python3 -c '
import json, sys
td = json.load(sys.stdin)
# Fields the API returns but refuses on the way back in.
for key in ("taskDefinitionArn", "revision", "status", "requiresAttributes",
            "compatibilities", "registeredAt", "registeredBy", "deregisteredAt"):
    td.pop(key, None)
td["containerDefinitions"][0]["image"] = sys.argv[1]
json.dump(td, sys.stdout)
' "$new_image" > "$spec"

  aws_ ecs register-task-definition --cli-input-json "file://$spec" \
       --query 'taskDefinition.taskDefinitionArn' --output text
}

# "GojoGoFargateStackTask33048A08" out of a task-definition ARN or family:rev.
taskdef_family() {
  local s="${1##*/}"
  printf '%s' "${s%%:*}"
}

roll_out() {
  local taskdef_arn="$1"
  step "Deploy"
  info "$(basename "$taskdef_arn")  →  $(taskdef_image "$taskdef_arn")"
  if (( DRY_RUN )); then
    note "[dry-run] aws ecs update-service --task-definition $taskdef_arn"
    printf '\n%s  dry run — nothing was changed.%s\n\n' "$DIM" "$RESET"
    exit 0
  fi
  aws_ ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" \
       --task-definition "$taskdef_arn" --output text --query 'service.serviceName' \
       >/dev/null \
    || die "update-service failed."
  ok "ECS accepted the deployment"
}

wait_and_verify() {
  if (( ! WAIT_FOR_ROLLOUT )); then
    cat <<EOF

  Not waiting (--no-wait). To check on it:
    aws ecs describe-services --cluster $ECS_CLUSTER --services $ECS_SERVICE \\
      --region $AWS_REGION --query 'services[0].deployments'
    curl -s -o /dev/null -w '%{http_code}\\n' $HEALTH_URL

EOF
    exit 0
  fi

  # desiredCount 1 / minHealthyPercent 100: the new task must go healthy before
  # the old one drains, so a broken build stalls rather than causing an outage.
  # There's no deployment circuit breaker, hence the timeout handling below.
  step "Waiting for the rollout"
  note "New task starts before the old one drains. Typically 2–4 min; times out at 10."

  if aws_ ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"; then
    ok "Service stable"
  else
    warn "Service did not stabilise within the wait window."
    cat >&2 <<EOF

  It may still be starting, or the new task may be crash-looping — a failed
  Flyway migration looks exactly like this. The previous task keeps serving
  traffic until the new one is healthy, so you are probably still up.

    # why the task died
    aws ecs describe-tasks --cluster $ECS_CLUSTER --region $AWS_REGION \\
      --tasks \$(aws ecs list-tasks --cluster $ECS_CLUSTER --service-name $ECS_SERVICE \\
        --desired-status STOPPED --region $AWS_REGION --query 'taskArns[0]' --output text) \\
      --query 'tasks[0].[stoppedReason,containers[0].reason]'

    # application logs (Flyway errors land here)
    aws logs tail /ecs/gojogo-backend --since 15m --region $AWS_REGION

    # give up and go back
    ./scripts/deploy-backend.sh --rollback

EOF
    die "Deploy unconfirmed."
  fi

  # `services-stable` is necessary but not sufficient, and on 2026-07-31 it
  # returned success while the new revision was crash-looping on a bean-name
  # collision: the OLD task was still serving, so the health check below passed
  # too and the deploy reported success having changed nothing. Both of those
  # checks are answered by whatever is currently behind the load balancer, which
  # is exactly what a failed rollout leaves in place.
  #
  # So: ask what is *actually running*, and insist it is the revision this
  # deploy created.
  step "Rollout"
  local rollout
  rollout="$(aws_ ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
    --query "services[0].deployments[?status=='PRIMARY']|[0].{state:rolloutState,failed:failedTasks,td:taskDefinition}" \
    --output json)"
  local want_td state failed
  want_td="$(printf '%s' "$rollout" | python3 -c 'import json,sys; print(json.load(sys.stdin)["td"])')"
  state="$(printf '%s' "$rollout" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')"
  failed="$(printf '%s' "$rollout" | python3 -c 'import json,sys; print(json.load(sys.stdin)["failed"])')"

  local running_tds
  running_tds="$(aws_ ecs describe-tasks --cluster "$ECS_CLUSTER" \
    --tasks $(aws_ ecs list-tasks --cluster "$ECS_CLUSTER" --service-name "$ECS_SERVICE" \
      --query 'taskArns' --output text) \
    --query 'tasks[?lastStatus==`RUNNING`].taskDefinitionArn' --output text 2>/dev/null || echo "")"

  if [[ "$state" != "COMPLETED" || "$running_tds" != *"${want_td##*/}"* ]]; then
    printf '      wanted   %s\n      running  %s\n      state    %s (%s failed task(s))\n' \
      "${want_td##*/}" "${running_tds:-none}" "$state" "$failed" >&2
    die "The new revision is NOT what's serving traffic.
    The previous task is still up — which is why /actuator/health would have
    answered 200 and told you nothing. A crash-looping task usually means a
    failed Flyway migration or a context that won't start:

      aws logs tail /ecs/gojogo-backend --since 15m --region $AWS_REGION
      $0 --rollback"
  fi
  ok "Running ${want_td##*/}${failed:+ (after $failed failed attempt(s))}"

  step "Health"
  local code
  for attempt in 1 2 3 4 5; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$HEALTH_URL" || echo 000)"
    if [[ "$code" == "200" ]]; then
      ok "$HEALTH_URL → 200 (full check — this round-trips the database)"
      return 0
    fi
    note "attempt $attempt/5 → HTTP $code"
    sleep 6
  done

  die "Service reports stable but $HEALTH_URL never returned 200.
    aws logs tail /ecs/gojogo-backend --since 15m --region $AWS_REGION
    ./scripts/deploy-backend.sh --rollback"
}

# ------------------------------------------------------------- shared preflight
for tool in aws curl python3; do
  command -v "$tool" >/dev/null 2>&1 || die "\`$tool\` not found on PATH."
done
aws sts get-caller-identity >/dev/null 2>&1 \
  || die "No usable AWS credentials. Configure them, then retry."

# ------------------------------------------------------------------ read-only modes
if [[ "$MODE" == "current" ]]; then
  taskdef_image "$(live_taskdef_arn)" | sed "s|^.*:||"
  exit 0
fi

if [[ "$MODE" == "list" ]]; then
  live_arn="$(live_taskdef_arn)"
  family="$(aws_ ecs describe-task-definition --task-definition "$live_arn" \
              --query 'taskDefinition.family' --output text)"
  step "Task definition revisions — $family"
  note "The live one is marked. Roll back with: --rollback <revision>"
  printf '\n'
  for arn in $(aws_ ecs list-task-definitions --family-prefix "$family" \
                  --sort DESC --max-items 10 --query 'taskDefinitionArns[]' --output text); do
    marker="  "; [[ "$arn" == "$live_arn" ]] && marker="${GREEN}◀ live${RESET}"
    printf '    %-6s %-58s %s\n' \
      "$(basename "$arn" | sed 's/.*://')" "$(taskdef_image "$arn")" "$marker"
  done
  printf '\n'
  exit 0
fi

# ------------------------------------------------------------------------- infra
# Deploy the CDK stack — infrastructure, not code. No build, no tests, no push:
# this changes the shape of the task definition (secrets, env, roles, sizing),
# and then re-pins the image that was already running.
if [[ "$MODE" == "infra" ]]; then
  step "Infra — cdk deploy $CDK_STACK"

  command -v npx >/dev/null 2>&1 || die "\`npx\` not found on PATH (needed for cdk)."
  [[ -f "$REPO_ROOT/infra/cdk.json" ]] || die "No infra/cdk.json under $REPO_ROOT."

  # CloudFormation rejects a second update with a message that reads like a
  # permissions error. Name the real cause before cdk gets that far.
  stack_status="$(aws_ cloudformation describe-stacks --stack-name "$CDK_STACK" \
                    --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo ABSENT)"
  case "$stack_status" in
    ABSENT) die "Stack $CDK_STACK doesn't exist in $AWS_REGION." ;;
    *_IN_PROGRESS)
      die "$CDK_STACK is $stack_status — an update is already running.

    A stack deploy that can't pull its image retries for up to 3 hours before
    CloudFormation gives up (there's no deployment circuit breaker). You almost
    certainly want to cancel rather than wait:

      aws cloudformation describe-stacks --stack-name $CDK_STACK \\
        --region $AWS_REGION --query 'Stacks[0].StackStatus' --output text
      aws cloudformation cancel-update-stack --stack-name $CDK_STACK --region $AWS_REGION" ;;
  esac
  ok "Stack — $stack_status"

  # CDK owns the entire task definition, so a deploy that doesn't say which image
  # to run falls back to the stack's default, `latest` — a tag this script
  # deliberately never pushes and which may not exist at all. Carry the running
  # image across instead: an infra change should not also be a code change.
  live_arn="$(live_taskdef_arn)"
  live_image="$(taskdef_image "$live_arn")"
  infra_tag="${INFRA_IMAGE_TAG:-${live_image##*:}}"
  before_secrets="$(taskdef_secret_names "$live_arn")"

  [[ "$infra_tag" != "latest" ]] || die "The live task definition runs \`:latest\`.
    That means an earlier stack deploy already reset it, and there is no commit
    tag to carry across. Pin one explicitly — see --list for what exists:
      INFRA_IMAGE_TAG=<sha> $0 --infra"

  ecr_has_tag "$infra_tag" || die "Image tag \`$infra_tag\` is not in ECR.
    Deploying it would leave the service unable to pull, retrying for hours
    while the old task keeps serving. See --list, then:
      INFRA_IMAGE_TAG=<sha> $0 --infra"
  ok "Image — pinning $infra_tag (currently live)"

  cdk_args=(
    deploy "$CDK_STACK"
    -c "domainName=$CDK_DOMAIN_NAME"
    -c "certificateArn=$CDK_CERTIFICATE_ARN"
    -c "imageTag=$infra_tag"
  )

  # Empty is legal — an environment genuinely without Sumsub credentials should
  # still deploy — but it is never what you meant on a laptop, so it's loud.
  for pair in "sumsubSecretArn=$SUMSUB_SECRET_ARN" "stripeSecretArn=$STRIPE_SECRET_ARN"; do
    if [[ -n "${pair#*=}" ]]; then
      cdk_args+=( -c "$pair" )
      info "context  ${pair%%=*}"
    else
      warn "${pair%%=*} is empty — that module will deploy UNCONFIGURED."
    fi
  done

  if (( DRY_RUN )); then
    note "[dry-run] (cd infra && npx cdk ${cdk_args[*]})"
    printf '\n%s  dry run — nothing was changed.%s\n\n' "$DIM" "$RESET"
    exit 0
  fi

  step "cdk deploy"
  ( cd "$REPO_ROOT/infra" && npx cdk "${cdk_args[@]}" ) \
    || die "cdk deploy failed. The previous task definition is still serving."

  # The whole point of the mode: prove the new revision didn't lose anything.
  # A dropped secret doesn't fail the deploy — the module just comes up
  # unconfigured, which is invisible until someone tries to use it.
  step "Secrets carried over"
  after_arn="$(live_taskdef_arn)"
  after_secrets="$(taskdef_secret_names "$after_arn")"
  lost="$(comm -23 <(printf '%s\n' "$before_secrets") <(printf '%s\n' "$after_secrets"))"
  if [[ -n "$lost" ]]; then
    printf '%s\n' "$lost" | sed 's/^/      /' >&2
    die "The new revision DROPPED the secrets above.
    Whichever module owns them is now unconfigured in prod. Add the missing ARN
    to the config block at the top of this script and re-run --infra, or go back:
      $0 --rollback"
  fi
  ok "all $(printf '%s\n' "$after_secrets" | grep -c .) secrets present"

  wait_and_verify
  printf '\n%s  Infra deployed. Image %s, task definition %s.%s\n\n' \
    "$GREEN" "$infra_tag" "$(basename "$after_arn")" "$RESET"
  exit 0
fi

# ---------------------------------------------------------------------- rollback
if [[ "$MODE" == "rollback" ]]; then
  step "Rollback"
  live_arn="$(live_taskdef_arn)"
  family="$(taskdef_family "$live_arn")"

  if [[ -n "$ROLLBACK_TARGET" ]]; then
    target_arn="arn:aws:ecs:${AWS_REGION}:${AWS_ACCOUNT}:task-definition/${family}:${ROLLBACK_TARGET}"
    aws_ ecs describe-task-definition --task-definition "$target_arn" >/dev/null 2>&1 \
      || die "No such revision: $family:$ROLLBACK_TARGET  (try --list)"
  else
    # The newest ACTIVE revision that isn't the live one. `|| true` because grep
    # exits 1 when it filters everything out — which is the "only one revision
    # exists" case, and needs the explanation below rather than a bare exit 1.
    target_arn="$(aws_ ecs list-task-definitions --family-prefix "$family" \
                    --sort DESC --max-items 10 --query 'taskDefinitionArns[]' --output text \
                  | tr '\t' '\n' | grep -v "^${live_arn}$" | head -1 || true)"
    [[ -n "$target_arn" ]] || die "Nothing to roll back to — $(basename "$live_arn") is the only revision.
    Rollback works from the second deploy onward: each one leaves behind a
    revision pinned to the exact image it shipped. See --list."
  fi

  info "from  $(basename "$live_arn")  →  $(taskdef_image "$live_arn")"
  info "to    $(basename "$target_arn")  →  $(taskdef_image "$target_arn")"
  note "No rebuild — this image already exists and already ran."

  if (( ! DRY_RUN )); then
    read -r -p "    Roll back? [y/N] " reply
    [[ "$reply" == [yY] ]] || die "Cancelled."
  fi

  roll_out "$target_arn"
  wait_and_verify
  printf '\n%s  Rolled back to %s.%s\n\n' "$GREEN" "$(basename "$target_arn")" "$RESET"
  exit 0
fi

# ==============================================================================
# Deploy
# ==============================================================================
step "Preflight"

for tool in mvn git; do
  command -v "$tool" >/dev/null 2>&1 || die "\`$tool\` not found on PATH."
done

# Java 21, specifically. `java` on PATH may be 23, where Modulith's ArchUnit
# tests fail spuriously — so locate 21 rather than trusting PATH. A JAVA_HOME
# already in the environment (CI sets one) is honoured, then verified.
if [[ -z "${JAVA_HOME:-}" ]] && [[ -x /usr/libexec/java_home ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"
fi
[[ -n "${JAVA_HOME:-}" ]] || die "No Java 21 found. Install Corretto 21, or set JAVA_HOME to it."

java_version="$("$JAVA_HOME/bin/java" -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')"
[[ "$java_version" == "21" ]] \
  || die "JAVA_HOME is Java $java_version, need 21. ($JAVA_HOME)
    The Modulith tests fail spuriously on newer JDKs — this is not a formality."
export JAVA_HOME
ok "Java 21 — $JAVA_HOME"

ok "AWS — $(aws sts get-caller-identity --query Arn --output text)"

account="$(aws sts get-caller-identity --query Account --output text)"
[[ "$account" == "$AWS_ACCOUNT" ]] \
  || warn "Signed in to account $account but deploying to $AWS_ACCOUNT. Check ECR_REPO."

aws_ ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
      --query 'services[0].status' --output text 2>/dev/null | grep -q ACTIVE \
  || die "ECS service $ECS_CLUSTER/$ECS_SERVICE is not ACTIVE (or isn't visible to this identity)."
ok "ECS — $ECS_CLUSTER/$ECS_SERVICE active"

# The image tag has to name something real, or rollback later is guesswork.
git_sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
  (( ALLOW_DIRTY )) || die "Uncommitted changes.
    The image is tagged with the commit SHA, and a dirty tree means that tag
    would name code that isn't in the commit — which breaks rollback later.
    Commit first, or pass --allow-dirty to tag it $git_sha-dirty-<timestamp>."
  IMAGE_TAG="${git_sha}-dirty-$(date -u +%Y%m%d%H%M%S)"
  warn "Dirty tree — deploying as $IMAGE_TAG."
else
  IMAGE_TAG="$git_sha"
  ok "Git — clean at $git_sha"
fi
IMAGE_REF="${ECR_REPO}:${IMAGE_TAG}"

# A tag is never overwritten: a task definition revision may point at it, and
# moving it would silently change what that revision means. But the tag already
# existing is not an error — the tag *is* the commit, so the image already there
# is byte-for-byte this code. Reuse it. That's what makes a deploy that failed
# after the push (IAM, a stalled rollout) retryable on the same commit.
IMAGE_ALREADY_PUSHED=0
if aws_ ecr batch-get-image --repository-name "${ECR_REPO##*/}" \
        --image-ids "imageTag=$IMAGE_TAG" --query 'images[0]' --output text 2>/dev/null \
      | grep -qv '^None$'; then
  IMAGE_ALREADY_PUSHED=1
fi

# Flyway runs inside the task at startup, against the private RDS this script
# can't reach. Listing the migrations is the honest substitute: if one is new,
# this deploy is the thing that applies it.
step "Migrations on disk"
ls -1 "$BACKEND_DIR/src/main/resources/db/migration/" | sort -V | sed 's/^/    /'
note "Flyway applies any unapplied ones at task startup. A failure there fails the deploy."

# ------------------------------------------------------------------------ tests
step "Tests"
if (( RUN_TESTS )); then
  if (( DRY_RUN )); then
    note "[dry-run] mvn -B -f $BACKEND_DIR/pom.xml test"
  else
    mvn -B -f "$BACKEND_DIR/pom.xml" test || die "Tests failed — nothing deployed."
    ok "Tests green"
  fi
else
  warn "Skipped (--skip-tests)."
fi

# ------------------------------------------------------------- build + push image
step "Build + push image"
info "$IMAGE_REF"

# Not routed through a helper: the ECR token is a live credential and must never
# be echoed, so dry-run prints a redacted form and skips fetching one at all.
if (( IMAGE_ALREADY_PUSHED )); then
  ok "Already in ECR — reusing it (same commit, same image); not rebuilding."
elif (( DRY_RUN )); then
  printf '    %s[dry-run]%s mvn -B -f %s -DskipTests compile jib:build \\\n' \
    "$DIM" "$RESET" "$BACKEND_DIR/pom.xml"
  printf '        -Djib.image=%s \\\n' "$IMAGE_REF"
  printf '        -Djib.to.auth.username=AWS -Djib.to.auth.password=<redacted>\n'
else
  # Jib talks to the registry directly — no Docker daemon, no Dockerfile.
  ecr_password="$(aws_ ecr get-login-password)" \
    || die "Couldn't get an ECR token. Does this identity have ecr:GetAuthorizationToken?"

  # Deliberately the ONLY tag pushed. Co-tagging `latest` would move it under
  # whatever task definition still references it — including, during the
  # migration off `latest`, the live one. That is the exact mutability this
  # script exists to remove, so `latest` is left frozen wherever it is.
  mvn -B -f "$BACKEND_DIR/pom.xml" -DskipTests compile jib:build \
      -Djib.image="$IMAGE_REF" \
      -Djib.to.auth.username=AWS \
      -Djib.to.auth.password="$ecr_password" \
    || die "Image build/push failed — nothing deployed."
  ok "Pushed $IMAGE_TAG"
fi

# --------------------------------------------------------- new task def revision
step "Task definition"
current_arn="$(live_taskdef_arn)"
info "current  $(basename "$current_arn")  →  $(taskdef_image "$current_arn")"

if (( DRY_RUN )); then
  note "[dry-run] register a new revision of $(taskdef_family "$current_arn") with image $IMAGE_REF"
  new_arn="$current_arn"
else
  register_err="$(mktemp "${TMPDIR:-/tmp}/gojogo-register-err.XXXXXX")"
  if ! new_arn="$(register_revision_with_image "$current_arn" "$IMAGE_REF" 2>"$register_err")"; then
    if grep -q 'iam:PassRole' "$register_err"; then
      rm -f "$register_err"
      die "Not allowed to register a task definition (iam:PassRole denied).

    Registering a revision means handing ECS the task + execution roles, which
    needs iam:PassRole with iam:PassedToService including ecs-tasks.amazonaws.com.
    The old deploy path (force-new-deployment on a mutable tag) never passed a
    role, so this permission was never needed before.

    iam-policy-milestone1.json has the fix. Apply it as an ADMIN (the deploy
    user cannot grant itself permissions):

      aws iam create-policy-version \\
        --policy-arn arn:aws:iam::${AWS_ACCOUNT}:policy/GojoGoMilestone1Policy \\
        --policy-document file://iam-policy-milestone1.json --set-as-default

    (If that reports the 5-version limit, delete the oldest non-default version
    with: aws iam delete-policy-version --policy-arn <arn> --version-id vN)

    The image is already pushed, so afterwards just re-run this script — it
    reuses the image already in ECR instead of rebuilding it."
    fi
    cat "$register_err" >&2
    rm -f "$register_err"
    die "register-task-definition failed."
  fi
  rm -f "$register_err"
  ok "registered $(basename "$new_arn")"
fi

roll_out "$new_arn"
wait_and_verify

printf '\n%s  Deployed %s as %s.%s\n' "$GREEN" "$IMAGE_TAG" "$(basename "$new_arn")" "$RESET"
printf '%s  Roll back with: ./scripts/deploy-backend.sh --rollback%s\n\n' "$DIM" "$RESET"
