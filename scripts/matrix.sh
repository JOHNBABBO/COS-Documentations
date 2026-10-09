#!/usr/bin/env bash
# For each new partner key: create an org, then probe billing + terms behavior.
# Run: ./scripts/matrix.sh > /tmp/matrix_out.txt 2>&1
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
BASE="${COS_API_BASE_URL}"

pretty() { python3 -c "import json;print(json.dumps(json.load(open('$1')),indent=2))" 2>/dev/null || cat "$1"; }

run_for_key() {
  local label="$1" key="$2" suffix="$3"
  local AUTH="Authorization: Bearer $key"
  echo "==================================================================="
  echo "### $label   (key ...${key: -6})"
  echo "==================================================================="

  # Create an org under this partner
  local orgbody="/tmp/org.$$"
  local code
  code=$(curl -sS -m 30 -o "$orgbody" -w "%{http_code}" -X POST -H "$AUTH" \
    -H "Content-Type: application/json" \
    --data '{
      "name": "Audit Org '"$suffix"'",
      "external_id": "audit-'"$suffix"'",
      "contact": { "name": "Audit Admin", "email": "audit-'"$suffix"'@example.com", "phone": "213-555-'"$suffix"'", "role": "admin" },
      "address": { "line1": "1 Test Plaza", "line2": null, "city": "Los Angeles", "state": "CA", "zip_code": "90071", "country": "US" }
    }' \
    "$BASE/organizations")
  echo "## POST /organizations -> HTTP $code"
  pretty "$orgbody"
  local ORG
  ORG=$(python3 -c "import json;print(json.load(open('$orgbody')).get('organization_id',''))" 2>/dev/null)
  rm -f "$orgbody"
  echo "   ORG=$ORG"
  echo
  [ -n "$ORG" ] || { echo "   (no org id; skipping probes)"; return; }

  for ep in "billing/status:GET" "terms/status:GET"; do
    local path="${ep%%:*}" m="${ep##*:}"
    code=$(curl -sS -m 25 -o /tmp/e.$$ -w "%{http_code}" -X "$m" -H "$AUTH" "$BASE/organizations/$ORG/$path")
    echo "## $m $path -> HTTP $code"; pretty /tmp/e.$$; echo; rm -f /tmp/e.$$
  done

  # billing/setup (POST)
  code=$(curl -sS -m 25 -o /tmp/e.$$ -w "%{http_code}" -X POST -H "$AUTH" -H "Content-Type: application/json" \
    --data '{"success_url":"https://example.com/ok","cancel_url":"https://example.com/cancel"}' \
    "$BASE/organizations/$ORG/billing/setup")
  echo "## POST billing/setup -> HTTP $code"; pretty /tmp/e.$$; echo; rm -f /tmp/e.$$

  # terms/setup (POST)
  code=$(curl -sS -m 25 -o /tmp/e.$$ -w "%{http_code}" -X POST -H "$AUTH" -H "Content-Type: application/json" \
    --data '{"success_url":"https://example.com/ok","cancel_url":"https://example.com/cancel"}' \
    "$BASE/organizations/$ORG/terms/setup")
  echo "## POST terms/setup -> HTTP $code"; pretty /tmp/e.$$; echo; rm -f /tmp/e.$$
}

run_for_key "stripe + terms REQUIRED (id13)"      "$COS_KEY_STRIPE_TERMS"    "131"
run_for_key "monthly_invoice + terms REQ (id14)"   "$COS_KEY_INVOICE_TERMS"   "141"
run_for_key "monthly_invoice + NO terms (id15)"    "$COS_KEY_INVOICE_NOTERMS" "151"
