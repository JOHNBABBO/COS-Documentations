#!/usr/bin/env bash
# Read-only probe helper for the CoS Partner API audit.
# Usage: ./scripts/probe.sh > /tmp/probe_out.txt 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

AUTH="Authorization: Bearer ${COS_API_KEY}"
BASE="${COS_API_BASE_URL}"
ORG="${COS_TEST_ORG_ID}"

probe() {
  local method="$1" url="$2"; shift 2
  local body="/tmp/cos_probe_body.$$"
  local code
  code=$(curl -sS -m 25 -o "$body" -w "%{http_code}" -X "$method" \
    -H "$AUTH" -H "Accept: application/json" "$@" "$url" || echo "ERR")
  printf '%-6s %-55s -> HTTP %s\n' "$method" "${url#"$BASE"}" "$code"
  # pretty-print JSON if possible, else raw (truncated)
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import sys,json;print(json.dumps(json.load(open('$body')),indent=2))" 2>/dev/null \
      | sed 's/^/   /' || { echo "   $(head -c 400 "$body" | tr '\n' ' ')"; }
  else
    echo "   $(head -c 400 "$body" | tr '\n' ' ')"
  fi
  echo
  rm -f "$body"
}

echo "=== Read-only probes against $BASE (org=$ORG) ==="
echo
echo "## Organizations"
probe GET "$BASE/organizations/$ORG"
echo "## Settings"
probe GET "$BASE/organizations/$ORG/settings"
echo "## Nested collections (status doc: not yet available)"
probe GET "$BASE/organizations/$ORG/contacts"
probe GET "$BASE/organizations/$ORG/return-addresses"
probe GET "$BASE/organizations/$ORG/signatures"
echo "## Billing & Terms"
probe GET "$BASE/organizations/$ORG/billing/status"
probe GET "$BASE/organizations/$ORG/terms/status"
echo "## Jobs (read-only)"
probe GET "$BASE/jobs/mailings?organization_id=$ORG"
