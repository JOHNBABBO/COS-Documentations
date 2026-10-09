#!/usr/bin/env bash
# Isolate the 500 on draft creation by trying variants.
# Run: ./scripts/draft-probe.sh > /tmp/draftprobe_out.txt 2>&1
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
AUTH="Authorization: Bearer ${COS_KEY_STRIPE_NOTERMS}"
BASE="${COS_API_BASE_URL}"
ORG="7780303033"
PDF="/tmp/dp.pdf"
printf '%%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R>>endobj\n4 0 obj<</Length 20>>stream\nBT (hi) Tj ET\nendstream endobj\ntrailer<</Root 1 0 R>>\n%%%%EOF\n' > "$PDF"
pretty() { python3 -c "import json;print(json.dumps(json.load(open('$1')),indent=2))" 2>/dev/null || cat "$1"; }

try() {
  local label="$1" job="$2"
  local code
  code=$(curl -sS -m 60 -o /tmp/t.json -w "%{http_code}" -X POST -H "$AUTH" -H "Accept: application/json" \
    -F "job=$job" -F "files=@$PDF;type=application/pdf;filename=dp.pdf" "$BASE/jobs/mailings")
  echo "## $label -> HTTP $code"; pretty /tmp/t.json; echo; rm -f /tmp/t.json
}

# Variant A: minimal, exactly like the Postman stg2 draft (no documents array, service rush)
try "A: Postman-style minimal (rush, no documents[])" '{
  "organization_id":"'"$ORG"'",
  "type":"bankruptcy_notice",
  "bankruptcy_options":{"case_numbers":["20-bk-01701"],"court_location":{"state":"Mississippi","district":"Southern"}},
  "order_preferences":{"service":"rush"},
  "recipients":{"source":"pacer"}
}'

# Variant B: user_supplied recipients (no PACER)
try "B: user_supplied recipients" '{
  "organization_id":"'"$ORG"'",
  "type":"bankruptcy_notice",
  "documents":[{"docket_description":"Test","docket_reference_number":"1"}],
  "recipients":{"source":"user_supplied","addresses":[{"name":"Bank of America NA","address":["PO Box 15019","Wilmington, DE 19850"]}]},
  "bankruptcy_options":{"case_numbers":["20-bk-01701"],"court_location":{"state":"Mississippi","district":"Southern"}},
  "order_preferences":{"service":"normal"}
}'

# Variant C: with documents[] + pacer (the shape that just 500'd)
try "C: documents[] + pacer + normal" '{
  "organization_id":"'"$ORG"'",
  "type":"bankruptcy_notice",
  "documents":[{"docket_description":"Lifecycle Test Notice","docket_reference_number":"1"}],
  "recipients":{"source":"pacer"},
  "bankruptcy_options":{"case_numbers":["20-bk-01701"],"court_location":{"state":"Mississippi","district":"Southern"}},
  "order_preferences":{"service":"normal"}
}'
rm -f "$PDF"
