#!/usr/bin/env bash
# Full job lifecycle on the paid org: draft -> submit -> poll -> cost -> certificate
# Run: ./scripts/lifecycle.sh > /tmp/lifecycle_out.txt 2>&1
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

AUTH="Authorization: Bearer ${COS_KEY_STRIPE_NOTERMS}"
BASE="${COS_API_BASE_URL}"
ORG="7780303033"
PDF="/tmp/cos_life_doc.pdf"

cat > "$PDF" <<'EOF'
%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Resources<<>>/Contents 4 0 R>>endobj
4 0 obj<</Length 44>>stream
BT /F1 24 Tf 100 700 Td (Lifecycle Test) Tj ET
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

pretty() { python3 -c "import json;print(json.dumps(json.load(open('$1')),indent=2))" 2>/dev/null || cat "$1"; }

JOB_JSON='{
  "organization_id": "'"$ORG"'",
  "type": "bankruptcy_notice",
  "documents": [ { "docket_description": "Lifecycle Test Notice", "docket_reference_number": "1" } ],
  "recipients": { "source": "pacer" },
  "bankruptcy_options": {
    "case_numbers": ["20-bk-01701"],
    "court_location": { "state": "Mississippi", "district": "Southern" }
  },
  "order_preferences": { "service": "normal" }
}'

echo "=== LIFECYCLE on paid org $ORG — $(date -u +%FT%TZ) ==="
echo
echo "########## Ensure default return-address + signature exist"
curl -sS -m 25 -o /tmp/ra.json -w "   POST return-address -> HTTP %{http_code}\n" -X POST -H "$AUTH" -H "Content-Type: application/json" \
  --data '{"name":"Life RA","firm_name":"Hoffman & Associates, PC","line1":"350 S Grand Ave","city":"Los Angeles","state":"CA","zip_code":"90071","country":"US","is_default":true}' \
  "$BASE/organizations/$ORG/return-addresses"
RA_ID=$(python3 -c "import json;print(json.load(open('/tmp/ra.json')).get('return_address_id',''))" 2>/dev/null)
curl -sS -m 25 -o /tmp/sg.json -w "   POST signature -> HTTP %{http_code}\n" -X POST -H "$AUTH" -H "Content-Type: application/json" \
  --data '{"name":"Life Sig","full_name":"Nancy Hoffman","client_role":"Chapter 13 Trustee","phone":"213-555-0100","is_default":true}' \
  "$BASE/organizations/$ORG/signatures"
SG_ID=$(python3 -c "import json;print(json.load(open('/tmp/sg.json')).get('signature_id',''))" 2>/dev/null)
echo "   RA_ID=$RA_ID SG_ID=$SG_ID"
rm -f /tmp/ra.json /tmp/sg.json
echo
echo "########## POST /jobs/mailings (draft)"
code=$(curl -sS -m 60 -o /tmp/d.json -w "%{http_code}" -X POST -H "$AUTH" -H "Accept: application/json" \
  -F "job=$JOB_JSON" -F "files=@$PDF;type=application/pdf;filename=life.pdf" "$BASE/jobs/mailings")
echo "-> HTTP $code"; pretty /tmp/d.json
JOB_ID=$(python3 -c "import json;print(json.load(open('/tmp/d.json')).get('job_id',''))" 2>/dev/null)
echo "JOB_ID=$JOB_ID"; echo
[ -n "$JOB_ID" ] || { echo "no job id; abort"; exit 1; }

echo "########## POST /jobs/mailings/$JOB_ID/submit"
curl -sS -m 60 -o /tmp/s.json -w "-> HTTP %{http_code}\n" -X POST -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID/submit"
pretty /tmp/s.json; echo

echo "########## POLL GET /jobs/mailings/$JOB_ID (up to ~90s)"
for i in $(seq 1 9); do
  sleep 10
  curl -sS -m 25 -o /tmp/p.json -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID"
  st=$(python3 -c "import json;print(json.load(open('/tmp/p.json')).get('status',''))" 2>/dev/null)
  cr=$(python3 -c "import json;print(json.load(open('/tmp/p.json')).get('certificate_ready',''))" 2>/dev/null)
  echo "   poll $i: status=$st certificate_ready=$cr"
  [ "$st" = "completed" ] && break
done
echo "## final GET job:"; pretty /tmp/p.json; echo

echo "########## GET /jobs/mailings/$JOB_ID/cost"
curl -sS -m 25 -o /tmp/c.json -w "-> HTTP %{http_code}\n" -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID/cost"
pretty /tmp/c.json; echo

echo "########## GET /jobs/mailings/$JOB_ID/certificate"
curl -sS -m 25 -o /tmp/cert.json -w "-> HTTP %{http_code}\n" -H "$AUTH" "$BASE/jobs/mailings/$JOB_ID/certificate"
pretty /tmp/cert.json; echo

echo "SAVED_JOB_ID=$JOB_ID"
rm -f /tmp/d.json /tmp/s.json /tmp/p.json /tmp/c.json /tmp/cert.json "$PDF"
