#!/usr/bin/env bash
# Submit a known draft and poll to completion, then cost + certificate.
# Usage: ./scripts/submit-poll.sh <JOB_ID> > /tmp/sp_out.txt 2>&1
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
AUTH="Authorization: Bearer ${COS_KEY_STRIPE_NOTERMS}"
BASE="${COS_API_BASE_URL}"
JOB_ID="${1:?need job id}"
pretty() { python3 -c "import json;print(json.dumps(json.load(open('$1')),indent=2))" 2>/dev/null || cat "$1"; }

echo "########## POST /jobs/mailings/$JOB_ID/submit"
curl -sS -m 60 -o /tmp/s.json -w "-> HTTP %{http_code}\n" -X POST -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID/submit"
pretty /tmp/s.json; echo

echo "########## POLL (up to ~120s)"
for i in $(seq 1 12); do
  sleep 10
  curl -sS -m 25 -o /tmp/p.json -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID"
  st=$(python3 -c "import json;print(json.load(open('/tmp/p.json')).get('status',''))" 2>/dev/null)
  cr=$(python3 -c "import json;print(json.load(open('/tmp/p.json')).get('certificate_ready',''))" 2>/dev/null)
  echo "   poll $i: status=$st certificate_ready=$cr"
  [ "$st" = "completed" ] && break
  [ "$st" = "cancelled" ] && break
done
echo "## final GET:"; pretty /tmp/p.json; echo

echo "########## GET cost"
curl -sS -m 25 -o /tmp/c.json -w "-> HTTP %{http_code}\n" -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID/cost"
pretty /tmp/c.json; echo

echo "########## GET certificate"
curl -sS -m 25 -o /tmp/cert.json -w "-> HTTP %{http_code}\n" -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID/certificate"
pretty /tmp/cert.json; echo
rm -f /tmp/s.json /tmp/p.json /tmp/c.json /tmp/cert.json
