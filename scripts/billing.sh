#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
code=$(curl -sS -m 40 -o /tmp/bill.json -w "%{http_code}" -X POST \
  -H "Authorization: Bearer ${COS_API_KEY}" -H "Content-Type: application/json" -H "Accept: application/json" \
  --data '{"success_url":"https://example.com/ok","cancel_url":"https://example.com/cancel"}' \
  "${COS_API_BASE_URL}/organizations/${COS_TEST_ORG_ID}/billing/setup")
echo "POST billing/setup -> HTTP $code"
python3 -c "import json;print(json.dumps(json.load(open('/tmp/bill.json')),indent=2))" 2>/dev/null || cat /tmp/bill.json
rm -f /tmp/bill.json
