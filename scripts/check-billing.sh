#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
BASE="${COS_API_BASE_URL}"
pretty() { python3 -c "import json;print(json.dumps(json.load(open('$1')),indent=2))" 2>/dev/null || cat "$1"; }

echo "## org 7780303033 (stripe/false) billing/status:"
curl -sS -m 25 -o /tmp/b1 -w "-> HTTP %{http_code}\n" -H "Authorization: Bearer ${COS_KEY_STRIPE_NOTERMS}" "$BASE/organizations/7780303033/billing/status"
pretty /tmp/b1; echo

echo "## org 8509846406 (stripe/terms id13) billing/status:"
curl -sS -m 25 -o /tmp/b2 -w "-> HTTP %{http_code}\n" -H "Authorization: Bearer ${COS_KEY_STRIPE_TERMS}" "$BASE/organizations/8509846406/billing/status"
pretty /tmp/b2; echo
rm -f /tmp/b1 /tmp/b2
