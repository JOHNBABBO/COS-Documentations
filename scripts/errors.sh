#!/usr/bin/env bash
# Error-code sweep against the live Partner API.
# Run: ./scripts/errors.sh > /tmp/errors_out.txt 2>&1
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

KEY="${COS_KEY_STRIPE_NOTERMS}"
AUTH="Authorization: Bearer ${KEY}"
BASE="${COS_API_BASE_URL}"
ORG="7780303033"
PDF="/tmp/err.pdf"
printf '%%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R>>endobj\n4 0 obj<</Length 10>>stream\nBT()Tj ET\nendstream endobj\ntrailer<</Root 1 0 R>>\n%%%%EOF\n' > "$PDF"
pretty() { python3 -c "import json;print(json.dumps(json.load(open('$1')),indent=2))" 2>/dev/null || { echo "(non-JSON) $(head -c 160 "$1" | tr '\n' ' ')"; }; }

j() {  # labeled request: j LABEL METHOD URL [curl args...]
  local label="$1" m="$2" url="$3"; shift 3
  local code; code=$(curl -sS -m 40 -o /tmp/er.json -w "%{http_code}" -X "$m" "$@" "$url")
  echo "## $label  [$m ${url#"$BASE"}] -> HTTP $code"
  pretty /tmp/er.json; echo; rm -f /tmp/er.json
}

echo "=== ERROR SWEEP — $(date -u +%FT%TZ) ==="
echo

echo "===== AUTH ====="
j "401 bad key"      GET "$BASE/organizations/$ORG" -H "Authorization: Bearer cos_live_boguskey000"
j "401 no header"    GET "$BASE/organizations/$ORG"
j "401 malformed hdr" GET "$BASE/organizations/$ORG" -H "Authorization: NotBearer xyz"
echo

echo "===== NOT FOUND ====="
j "404 org not_found"      GET "$BASE/organizations/0000000000" -H "$AUTH"
j "404 contact_not_found"  GET "$BASE/organizations/$ORG/contacts/99999999" -H "$AUTH"
j "404 ra_not_found"       GET "$BASE/organizations/$ORG/return-addresses/99999999" -H "$AUTH"
j "404 sig_not_found"      GET "$BASE/organizations/$ORG/signatures/99999999" -H "$AUTH"
echo

echo "===== JOB VALIDATION (422) ====="
# missing case_numbers for bankruptcy_notice
j "422 missing case_numbers" POST "$BASE/jobs/mailings" -H "$AUTH" \
  -F 'job={"organization_id":"'"$ORG"'","type":"bankruptcy_notice","documents":[{"docket_description":"x"}],"recipients":{"source":"pacer"},"bankruptcy_options":{"court_location":{"state":"Mississippi","district":"Southern"}}}' \
  -F "files=@$PDF;type=application/pdf;filename=err.pdf"
# bad notification email
j "422 invalid_notification_email" POST "$BASE/jobs/mailings" -H "$AUTH" \
  -F 'job={"organization_id":"'"$ORG"'","type":"bankruptcy_notice","documents":[{"docket_description":"x"}],"recipients":{"source":"pacer"},"bankruptcy_options":{"case_numbers":["20-bk-01701"],"court_location":{"state":"Mississippi","district":"Southern"}},"notifications":{"primary_email":"not-an-email"}}' \
  -F "files=@$PDF;type=application/pdf;filename=err.pdf"
# too many cc emails (11)
j "422 too_many_cc_emails" POST "$BASE/jobs/mailings" -H "$AUTH" \
  -F 'job={"organization_id":"'"$ORG"'","type":"bankruptcy_notice","documents":[{"docket_description":"x"}],"recipients":{"source":"pacer"},"bankruptcy_options":{"case_numbers":["20-bk-01701"],"court_location":{"state":"Mississippi","district":"Southern"}},"notifications":{"primary_email":"ok@example.com","cc_emails":["1@e.com","2@e.com","3@e.com","4@e.com","5@e.com","6@e.com","7@e.com","8@e.com","9@e.com","10@e.com","11@e.com"]}}' \
  -F "files=@$PDF;type=application/pdf;filename=err.pdf"
# bad return_address_id reference
j "404 return_address_not_found (job ref)" POST "$BASE/jobs/mailings" -H "$AUTH" \
  -F 'job={"organization_id":"'"$ORG"'","type":"bankruptcy_notice","documents":[{"docket_description":"x"}],"recipients":{"source":"pacer"},"bankruptcy_options":{"case_numbers":["20-bk-01701"],"court_location":{"state":"Mississippi","district":"Southern"}},"return_address_id":"99999999"}' \
  -F "files=@$PDF;type=application/pdf;filename=err.pdf"
# debtor_name mismatch
j "422 debtor_name_mismatch" POST "$BASE/jobs/mailings" -H "$AUTH" \
  -F 'job={"organization_id":"'"$ORG"'","type":"bankruptcy_notice","documents":[{"docket_description":"x"}],"recipients":{"source":"pacer"},"bankruptcy_options":{"case_numbers":["20-bk-01701"],"court_location":{"state":"Mississippi","district":"Southern"},"debtor_name":"Totally Wrong Name LLC"}}' \
  -F "files=@$PDF;type=application/pdf;filename=err.pdf"
# bogus case number
j "422 case_not_found" POST "$BASE/jobs/mailings" -H "$AUTH" \
  -F 'job={"organization_id":"'"$ORG"'","type":"bankruptcy_notice","documents":[{"docket_description":"x"}],"recipients":{"source":"pacer"},"bankruptcy_options":{"case_numbers":["99-bk-99999"],"court_location":{"state":"Mississippi","district":"Southern"}}}' \
  -F "files=@$PDF;type=application/pdf;filename=err.pdf"
echo

echo "===== CONFLICT (409) ====="
# duplicate contact email on existing org
j "409 duplicate contact email (1st create)" POST "$BASE/organizations/$ORG/contacts" -H "$AUTH" -H "Content-Type: application/json" \
  --data '{"name":"Dup A","email":"dup-test@example.com","phone":"213-555-0101"}'
j "409 duplicate contact email (2nd, should conflict)" POST "$BASE/organizations/$ORG/contacts" -H "$AUTH" -H "Content-Type: application/json" \
  --data '{"name":"Dup B","email":"dup-test@example.com","phone":"213-555-0102"}'
# duplicate external_id org
j "409 duplicate external_id (1st create)" POST "$BASE/organizations" -H "$AUTH" -H "Content-Type: application/json" \
  --data '{"name":"Dup Org A","external_id":"audit-dup-eid","contact":{"name":"c","email":"dupeid-a@example.com","phone":"213-555-0103","role":"admin"},"address":{"line1":"1 St","city":"LA","state":"CA","zip_code":"90071","country":"US"}}'
j "409 duplicate external_id (2nd, should conflict)" POST "$BASE/organizations" -H "$AUTH" -H "Content-Type: application/json" \
  --data '{"name":"Dup Org B","external_id":"audit-dup-eid","contact":{"name":"c","email":"dupeid-b@example.com","phone":"213-555-0104","role":"admin"},"address":{"line1":"1 St","city":"LA","state":"CA","zip_code":"90071","country":"US"}}'
rm -f "$PDF"
echo "=== END ERROR SWEEP ==="
