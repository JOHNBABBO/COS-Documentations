#!/usr/bin/env bash
# Clean up error-sweep test data. Run: ./scripts/cleanup2.sh > /tmp/cleanup2_out.txt 2>&1
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
AUTH="Authorization: Bearer ${COS_KEY_STRIPE_NOTERMS}"
BASE="${COS_API_BASE_URL}"
ORG="7780303033"
pretty() { python3 -c "import json;print(json.dumps(json.load(open('$1')),indent=2))" 2>/dev/null || { echo "(non-JSON) $(head -c 160 "$1" | tr '\n' ' ')"; }; }

echo "## DELETE contact 20"
curl -sS -m 25 -o /tmp/x -w "-> HTTP %{http_code}\n" -X DELETE -H "$AUTH" "$BASE/organizations/$ORG/contacts/20"; echo

# Also delete the lifecycle default RA/SG we created (ids 10) if desired — leave them (they are valid defaults).

echo "## Try DELETE duplicate orgs (may not be supported)"
for oid in 1870059062 8104092438; do
  curl -sS -m 25 -o /tmp/x -w "DELETE /organizations/$oid -> HTTP %{http_code}  " -X DELETE -H "$AUTH" "$BASE/organizations/$oid"
  head -c 160 /tmp/x | tr '\n' ' '; echo
done
rm -f /tmp/x
