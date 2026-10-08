#!/usr/bin/env bash
# Jobs lifecycle audit: draft -> inspect -> submit -> get -> cost -> certificate
# Run: ./scripts/jobs.sh > /tmp/jobs_out.txt 2>&1
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

AUTH="Authorization: Bearer ${COS_API_KEY}"
BASE="${COS_API_BASE_URL}"
ORG="${COS_TEST_ORG_ID}"
PDF="/tmp/cos_test_doc.pdf"

# Minimal valid 1-page PDF
cat > "$PDF" <<'EOF'
%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Resources<<>>/Contents 4 0 R>>endobj
4 0 obj<</Length 44>>stream
BT /F1 24 Tf 100 700 Td (Audit Test) Tj ET
endstream endobj
xref
0 5
0000000000 65535 f 
0000000009 00000 n 
0000000052 00000 n 
0000000101 00000 n 
0000000191 00000 n 
trailer<</Size 5/Root 1 0 R>>
startxref
285
%%EOF
EOF

pretty() { python3 -c "import json,sys;print(json.dumps(json.load(open('$1')),indent=2))" 2>/dev/null || cat "$1"; }

JOB_JSON='{
  "organization_id": "'"$ORG"'",
  "type": "bankruptcy_notice",
  "documents": [ { "docket_description": "Audit Test Notice", "docket_reference_number": "1" } ],
  "recipients": { "source": "pacer" },
  "bankruptcy_options": {
    "case_numbers": ["20-bk-01701"],
    "court_location": { "state": "Mississippi", "district": "Southern" }
  },
  "order_preferences": { "service": "normal" }
}'

echo "=== JOBS LIFECYCLE — org=$ORG — $(date -u +%FT%TZ) ==="
echo
echo "########## POST /jobs/mailings (draft)"
code=$(curl -sS -m 60 -o /tmp/draft.json -w "%{http_code}" -X POST \
  -H "$AUTH" -H "Accept: application/json" \
  -F "job=$JOB_JSON" \
  -F "files=@$PDF;type=application/pdf;filename=audit.pdf" \
  "$BASE/jobs/mailings")
echo "-> HTTP $code"
pretty /tmp/draft.json
echo

JOB_ID=$(python3 -c "import json;print(json.load(open('/tmp/draft.json')).get('job_id',''))" 2>/dev/null)
echo "Extracted JOB_ID=$JOB_ID"
echo

if [ -n "$JOB_ID" ]; then
  echo "########## GET /jobs/mailings/{id} (draft state)"
  curl -sS -m 40 -o /tmp/jget.json -w "-> HTTP %{http_code}\n" -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID"
  pretty /tmp/jget.json
  echo

  echo "########## POST /jobs/mailings/{id}/submit"
  curl -sS -m 60 -o /tmp/jsub.json -w "-> HTTP %{http_code}\n" -X POST -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID/submit"
  pretty /tmp/jsub.json
  echo

  echo "########## GET /jobs/mailings/{id} (after submit)"
  curl -sS -m 40 -o /tmp/jget2.json -w "-> HTTP %{http_code}\n" -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID"
  pretty /tmp/jget2.json
  echo

  echo "########## GET /jobs/mailings/{id}/cost"
  curl -sS -m 40 -o /tmp/jcost.json -w "-> HTTP %{http_code}\n" -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID/cost"
  pretty /tmp/jcost.json
  echo

  echo "########## GET /jobs/mailings/{id}/certificate"
  curl -sS -m 40 -o /tmp/jcert.json -w "-> HTTP %{http_code}\n" -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID/certificate"
  pretty /tmp/jcert.json
  echo
fi

echo "########## GET /jobs/mailings (list)"
curl -sS -m 40 -o /tmp/jlist.json -w "-> HTTP %{http_code}\n" -H "$AUTH" "$BASE/jobs/mailings?organization_id=$ORG"
pretty /tmp/jlist.json
rm -f /tmp/draft.json /tmp/jget.json /tmp/jsub.json /tmp/jget2.json /tmp/jcost.json /tmp/jcert.json /tmp/jlist.json "$PDF"
