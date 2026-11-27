#!/usr/bin/env bash
# Generates a little mixed traffic (fast, slow and failing requests) so the
# Grafana dashboards and alert rules have something to show.
#
#   scripts/load-test.sh [base-url] [duration-seconds]
#   scripts/load-test.sh http://localhost:8080 60
#
# Needs ENABLE_SIMULATE=true on the app (the default) for the slow/error requests.
set -uo pipefail

BASE_URL="${1:-http://localhost:8080}"
DURATION="${2:-60}"
BASE_URL="${BASE_URL%/}"

echo "Sending traffic to ${BASE_URL} for ${DURATION}s (Ctrl+C to stop)..."

hit() { curl -s -o /dev/null --max-time 10 "$1" || true; }

end=$((SECONDS + DURATION))
i=0
while ((SECONDS < end)); do
  i=$((i + 1))
  hit "${BASE_URL}/" &
  hit "${BASE_URL}/api/info" &
  hit "${BASE_URL}/api/simulate?delay_ms=$((RANDOM % 400))" &
  hit "${BASE_URL}/no-such-page" &
  # roughly 1 request in 10 iterations fails with a 500 so the error panels move
  if ((i % 10 == 0)); then
    hit "${BASE_URL}/api/simulate?status=500" &
  fi
  wait
  sleep 0.3
done

echo "Done: ${i} rounds sent."
