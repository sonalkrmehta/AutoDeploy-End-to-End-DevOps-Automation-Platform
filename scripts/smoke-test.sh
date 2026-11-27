#!/usr/bin/env bash
# Post-deployment smoke test. Used by the pipeline and handy to run by hand.
#
#   scripts/smoke-test.sh <base-url> [expected-version]
#
#   scripts/smoke-test.sh http://203.0.113.10 sha-1a2b3c4
#   scripts/smoke-test.sh http://localhost:8080
#
# Each check is retried (the stack may still be warming up). Tunables:
#   SMOKE_RETRIES (default 24)   SMOKE_DELAY seconds between tries (default 5)
set -euo pipefail

BASE_URL="${1:-}"
EXPECTED_VERSION="${2:-}"
RETRIES="${SMOKE_RETRIES:-24}"
DELAY="${SMOKE_DELAY:-5}"

if [[ -z "$BASE_URL" ]]; then
  echo "usage: $0 <base-url> [expected-version]" >&2
  exit 2
fi
BASE_URL="${BASE_URL%/}"

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

# Print the HTTP status of a URL (000 when the connection fails).
http_status() {
  curl -sS --max-time 10 -o "$BODY_FILE" -w '%{http_code}' "$1" 2>/dev/null || echo "000"
}

# check <description> <path> <expected-status> [body-regex]
check() {
  local description="$1" path="$2" want="$3" regex="${4:-}" status="000" attempt
  for ((attempt = 1; attempt <= RETRIES; attempt++)); do
    status="$(http_status "${BASE_URL}${path}")"
    if [[ "$status" == "$want" ]] && { [[ -z "$regex" ]] || grep -Eq "$regex" "$BODY_FILE"; }; then
      echo "  PASS  ${description}"
      return 0
    fi
    sleep "$DELAY"
  done
  echo "  FAIL  ${description} (last status: ${status}, path: ${path})"
  return 1
}

echo "Smoke testing ${BASE_URL}"
failures=0

check "Nginx is up" "/nginx-health" 200 || failures=$((failures + 1))
check "App /health reports status ok" "/health" 200 '"status": ?"ok"' || failures=$((failures + 1))
if [[ -n "$EXPECTED_VERSION" ]]; then
  check "App runs expected version ${EXPECTED_VERSION}" "/health" 200 "\"version\": ?\"${EXPECTED_VERSION}\"" \
    || failures=$((failures + 1))
fi
check "Status page renders" "/" 200 "AutoDeploy" || failures=$((failures + 1))
check "Grafana is healthy behind /grafana/" "/grafana/api/health" 200 '"database": ?"ok"' \
  || failures=$((failures + 1))
check "Raw /metrics is NOT public" "/metrics" 404 || failures=$((failures + 1))

echo
if ((failures > 0)); then
  echo "Smoke test FAILED (${failures} check(s))" >&2
  exit 1
fi
echo "Smoke test passed"
