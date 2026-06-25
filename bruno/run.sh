#!/bin/bash
# ============================================================
# run.sh — Bruno API collection runner for Scalekit
#
# Designed for agent and CI runs. Headless M2M only.
#
# USAGE
#   ./run.sh <env>              — run CI-safe folders against <env>
#   ./run.sh <env> --all        — include browser-flow folders too
#   ./run.sh <env> <folder>     — single folder (e.g. organizations)
#
# CREDENTIALS (in priority order)
#   1. BRUNO_* env vars         — CI pipeline secrets
#   2. .env file in this dir    — cp .env.example .env and fill in values
#   3. environments/<env>.bru   — base environment file (URLs only, no secrets)
#
# EXAMPLES
#   BRUNO_ENV_URL=https://... BRUNO_CLIENT_ID=... BRUNO_CLIENT_SECRET=... ./run.sh staging
#   ./run.sh local                      # uses .env for creds, local.bru for URL
#   ./run.sh staging organizations      # single folder
#   ./run.sh staging --reporter-json out.json
#
# EXIT CODES
#   0 — all requests passed (or were skipped)
#   1 — one or more requests failed, or a configuration error occurred
# ============================================================

set -euo pipefail

BRUNO_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Parse arguments ───────────────────────────────────────────────────────────
ENV="${1:-local}"
shift || true

FOLDER_OVERRIDE=""
RUN_ALL=false
PASSTHROUGH_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --all) RUN_ALL=true ;;
    --*)   PASSTHROUGH_ARGS+=("$arg") ;;
    *)
      if [ -z "$FOLDER_OVERRIDE" ]; then
        FOLDER_OVERRIDE="$arg"
      else
        PASSTHROUGH_ARGS+=("$arg")
      fi
      ;;
  esac
done

# Issue #7 fix: --all is silently ignored when a folder override is also present
if [ -n "$FOLDER_OVERRIDE" ] && [ "$RUN_ALL" = true ]; then
  echo "Error: cannot combine a folder name with --all. Use one or the other." >&2
  exit 1
fi

# ── Validate environment file ─────────────────────────────────────────────────
ENV_FILE="$BRUNO_DIR/environments/$ENV.bru"
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: environment file not found: $ENV_FILE" >&2
  echo "  Available: $(ls "$BRUNO_DIR/environments/"*.bru 2>/dev/null | xargs -n1 basename | tr '\n' ' ')" >&2
  exit 1
fi

# ── Load .env if present ──────────────────────────────────────────────────────
if [ -f "$BRUNO_DIR/.env" ]; then
  # shellcheck disable=SC1090
  set -a; source "$BRUNO_DIR/.env"; set +a
fi

# ── Resolve credentials ───────────────────────────────────────────────────────
ENV_URL="${BRUNO_ENV_URL:-${ENV_URL:-$(grep "^  env_url:" "$ENV_FILE" | awk '{print $2}')}}"
CLIENT_ID="${BRUNO_CLIENT_ID:-${CLIENT_ID:-$(grep "^  client_id:" "$ENV_FILE" | awk '{print $2}')}}"
CLIENT_SECRET="${BRUNO_CLIENT_SECRET:-${CLIENT_SECRET:-$(grep "^  client_secret:" "$ENV_FILE" | awk '{print $2}')}}"

if [ -z "$ENV_URL" ] || [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
  echo "Error: env_url, client_id, or client_secret is missing." >&2
  echo "  cp .env.example .env and fill in your values, or set BRUNO_ENV_URL / BRUNO_CLIENT_ID / BRUNO_CLIENT_SECRET" >&2
  exit 1
fi

# ── Fetch M2M bearer token ────────────────────────────────────────────────────
# Issue #2 fix: use -s (silent) without -f so curl does not exit non-zero on
# HTTP 4xx/5xx. This allows set -e to stay active AND lets us capture and print
# the response body when authentication fails.
echo "Fetching access token from $ENV_URL..." >&2
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT
HTTP_STATUS=$(curl -s -o "$TMPFILE" -w "%{http_code}" \
  -X POST "$ENV_URL/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" 2>/dev/null || true)
TOKEN_RESPONSE=$(cat "$TMPFILE" 2>/dev/null || true)

if [ "$HTTP_STATUS" != "200" ]; then
  echo "Error: token endpoint returned HTTP $HTTP_STATUS" >&2
  echo "$TOKEN_RESPONSE" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
else
  ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || true)
fi

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Error: failed to extract access_token from response" >&2
  echo "$TOKEN_RESPONSE" >&2
  exit 1
fi

# ── Resolve environment ID at runtime ────────────────────────────────────────
# Users always carry environment_id in their response — derive it from the first
# result rather than hardcoding it anywhere.
if command -v jq >/dev/null 2>&1; then
  ENVID=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$ENV_URL/api/v1/users?page_size=1" 2>/dev/null | \
    jq -r '.users[0].environment_id // empty' 2>/dev/null || true)
else
  ENVID=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$ENV_URL/api/v1/users?page_size=1" 2>/dev/null | \
    python3 -c "
import sys, json
users = json.load(sys.stdin).get('users', [])
print(users[0].get('environment_id', '') if users else '')
" 2>/dev/null || true)
fi

if [ -n "$ENVID" ]; then
  echo "Resolved envid: $ENVID" >&2
else
  echo "Warning: could not resolve envid — tests using {{envid}} will fail" >&2
fi

# ── CI-safe folder list ───────────────────────────────────────────────────────
# Excluded: fga, migrations (require migration_token), _dev/idp-simulator (local IDP),
#           sso/auth-flows (requires browser login_request_id)
CI_SAFE_FOLDERS=(
  "organizations"
  "roles"
  "users"
  "connections"
  "directory"
  "interceptors"
  "secrets"
  "tokens"
  "domains"
  "mcp"
  "connected-accounts"
  "clients"
  "emails"
  "auditlogs"
  "headless-passwordless"
  "sessions"
)

# Issue #8 fix: warn about collection folders that exist on disk but are not
# in CI_SAFE_FOLDERS, so new folders are never silently excluded.
if [ -z "$FOLDER_OVERRIDE" ] && [ "$RUN_ALL" = false ]; then
  for dir in "$BRUNO_DIR"/*/; do
    folder=$(basename "$dir")
    # skip non-collection dirs
    [[ "$folder" == "environments" || "$folder" == "_dev" ]] && continue
    in_list=false
    for f in "${CI_SAFE_FOLDERS[@]}"; do
      [ "$f" = "$folder" ] && in_list=true && break
    done
    if [ "$in_list" = false ]; then
      echo "Warning: folder '$folder' exists but is not in CI_SAFE_FOLDERS — it will not run. Add it to CI_SAFE_FOLDERS or use --all." >&2
    fi
  done
fi

# ── Determine target folders ──────────────────────────────────────────────────
if [ -n "$FOLDER_OVERRIDE" ]; then
  TARGET_FOLDERS=("$FOLDER_OVERRIDE")
  echo "Running folder: $FOLDER_OVERRIDE" >&2
elif [ "$RUN_ALL" = true ]; then
  TARGET_FOLDERS=()
  echo "Running all folders (--all)" >&2
else
  TARGET_FOLDERS=("${CI_SAFE_FOLDERS[@]}")
  echo "Running ${#CI_SAFE_FOLDERS[@]} CI-safe folders (use --all to include browser-flow folders)" >&2
fi

# ── Build env-var flags ───────────────────────────────────────────────────────
ENV_VAR_ARGS=(
  "--env-var" "access_token=$ACCESS_TOKEN"
  "--env-var" "env_url=$ENV_URL"
  "--env-var" "api_url=$ENV_URL"
)
[ -n "$ENVID" ] && ENV_VAR_ARGS+=("--env-var" "envid=$ENVID")

# ── Run ───────────────────────────────────────────────────────────────────────
cd "$BRUNO_DIR"

BRU_ARGS=(run --env "$ENV" "${ENV_VAR_ARGS[@]}")

if [ ${#TARGET_FOLDERS[@]} -eq 0 ]; then
  BRU_ARGS+=(-r)
else
  BRU_ARGS+=("${TARGET_FOLDERS[@]+"${TARGET_FOLDERS[@]}"}")
fi

[ ${#PASSTHROUGH_ARGS[@]} -gt 0 ] && BRU_ARGS+=("${PASSTHROUGH_ARGS[@]}")

# Issue #1 fix: mask the access_token value in the log to avoid leaking it in CI
LOGGED_ARGS=("${BRU_ARGS[@]}")
for i in "${!LOGGED_ARGS[@]}"; do
  if [ "${LOGGED_ARGS[$i]}" = "access_token=$ACCESS_TOKEN" ]; then
    LOGGED_ARGS[$i]="access_token=***"
  fi
done
echo "bru ${LOGGED_ARGS[*]}" >&2
echo "" >&2

bru "${BRU_ARGS[@]}"
