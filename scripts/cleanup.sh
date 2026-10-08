#!/usr/bin/env bash
# Delete audit-created test records. Run: ./scripts/cleanup.sh > /tmp/cleanup_out.txt 2>&1
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
AUTH="Authorization: Bearer ${COS_API_KEY}"
BASE="${COS_API_BASE_URL}"
ORG="${COS_TEST_ORG_ID}"

del() {
  local label="$1" url="$2"
  local code
  code=$(curl -sS -m 30 -o /tmp/d.txt -w "%{http_code}" -X DELETE -H "$AUTH" "$url")
  echo "$label -> HTTP $code  $(head -c 200 /tmp/d.txt | tr '\n' ' ')"
  rm -f /tmp/d.txt
}

del "DELETE contact 16"        "$BASE/organizations/$ORG/contacts/16"
del "DELETE return-address 9"  "$BASE/organizations/$ORG/return-addresses/9"
del "DELETE signature 9"       "$BASE/organizations/$ORG/signatures/9"
