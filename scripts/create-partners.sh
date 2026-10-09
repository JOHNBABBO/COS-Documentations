#!/usr/bin/env bash
# Create the 3 missing partner config combos via the admin API.
# Run: ./scripts/create-partners.sh > /tmp/partners_out.txt 2>&1
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

ADMIN="Authorization: Bearer ${COS_ADMIN_TOKEN}"
ABASE="${COS_ADMIN_BASE_URL}"

echo "=== Verify admin token ==="
vcode=$(curl -sS -m 25 -o /tmp/v.txt -w "%{http_code}" -H "$ADMIN" "$ABASE/partners")
echo "GET /partners -> HTTP $vcode"
[ "$vcode" = "200" ] || { echo "Admin token not valid; aborting."; head -c 200 /tmp/v.txt; exit 1; }
rm -f /tmp/v.txt
echo

create() {
  local name="$1" mode="$2" terms="$3"
  local body="/tmp/cp.$$"
  local code
  code=$(curl -sS -m 30 -o "$body" -w "%{http_code}" -X POST -H "$ADMIN" \
    -H "Content-Type: application/json" \
    --data "{\"name\":\"$name\",\"billingMode\":\"$mode\",\"termsRequired\":$terms}" \
    "$ABASE/partners")
  echo "########## POST /partners  name=\"$name\" mode=$mode terms=$terms -> HTTP $code"
  python3 -c "import json;print(json.dumps(json.load(open('$body')),indent=2))" 2>/dev/null || cat "$body"
  echo
  rm -f "$body"
}

create "Audit stripe terms"      "stripe"          "true"
create "Audit invoice terms"     "monthly_invoice" "true"
create "Audit invoice noterms"   "monthly_invoice" "false"
