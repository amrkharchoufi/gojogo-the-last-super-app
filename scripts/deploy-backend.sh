#!/usr/bin/env bash
#
# Deploy the GojoGo backend to ECS/Fargate.
#
#   ./scripts/deploy-backend.sh              # deploy HEAD
#   ./scripts/deploy-backend.sh --list       # what's deployed, and what you can go back to
#   ./scripts/deploy-backend.sh --rollback   # back to the previous revision
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
# CAUTION: `cdk deploy GojoGoFargateStack` resets the service to the task
# definition CDK owns. After an infra deploy, pass the running tag through:
#   cdk deploy GojoGoFargateStack -c imageTag=$(./scripts/deploy-backend.sh --current)
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
  sed -n '3,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Modes:
  (default)         Build the current commit and deploy it.
  --list            Show recent task definition revisions, their image tags, and
                    which one is live. This is your rollback menu.
  --rollback [REV]  Redeploy a previous revision — the one before the current if
                    REV is omitted. No rebuild: it redeploys an image that
                    already exists, so it's fast and cannot fail to compile.
  --current         Print the image tag currently deployed, and exit.

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

# Never overwrite a tag: a deployed revision points at it, so moving it would
# silently change what that revision means.
if aws_ ecr batch-get-image --repository-name "${ECR_REPO##*/}" \
        --image-ids "imageTag=$IMAGE_TAG" --query 'images[0]' --output text 2>/dev/null \
      | grep -qv '^None$'; then
  die "$IMAGE_TAG is already in ECR — this commit has been deployed before.
    Overwriting the tag would silently change what an existing task definition
    revision means, so it's refused. Options:
      --list                  find the revision running this image
      --rollback <revision>   redeploy it without rebuilding
      --allow-dirty           build a fresh, uniquely-tagged image
    Or just commit your changes and deploy the new SHA."
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
if (( DRY_RUN )); then
  printf '    %s[dry-run]%s mvn -B -f %s -DskipTests compile jib:build \\\n' \
    "$DIM" "$RESET" "$BACKEND_DIR/pom.xml"
  printf '        -Djib.image=%s -Djib.to.tags=latest \\\n' "$IMAGE_REF"
  printf '        -Djib.to.auth.username=AWS -Djib.to.auth.password=<redacted>\n'
else
  # Jib talks to the registry directly — no Docker daemon, no Dockerfile.
  ecr_password="$(aws_ ecr get-login-password)" \
    || die "Couldn't get an ECR token. Does this identity have ecr:GetAuthorizationToken?"

  # `latest` rides along as a human convenience pointer. ECS does not use it.
  mvn -B -f "$BACKEND_DIR/pom.xml" -DskipTests compile jib:build \
      -Djib.image="$IMAGE_REF" \
      -Djib.to.tags=latest \
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
  new_arn="$(register_revision_with_image "$current_arn" "$IMAGE_REF")" \
    || die "register-task-definition failed."
  ok "registered $(basename "$new_arn")"
fi

roll_out "$new_arn"
wait_and_verify

printf '\n%s  Deployed %s as %s.%s\n' "$GREEN" "$IMAGE_TAG" "$(basename "$new_arn")" "$RESET"
printf '%s  Roll back with: ./scripts/deploy-backend.sh --rollback%s\n\n' "$DIM" "$RESET"
