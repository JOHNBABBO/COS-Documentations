#!/usr/bin/env bash
# Full Partner API audit walk against the live staging API, using the real org.
# Writes clearly-labeled results. Run: ./scripts/audit.sh > /tmp/audit_out.txt 2>&1
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

AUTH="Authorization: Bearer ${COS_API_KEY}"
BASE="${COS_API_BASE_URL}"
ORG="${COS_TEST_ORG_ID}"

req() {
  # req LABEL METHOD URL [curl-args...]
  local label="$1" method="$2" url="$3"; shift 3
  local body="/tmp/cos_body.$$"
  local code
  code=$(curl -sS -m 40 -o "$body" -w "%{http_code}" -X "$method" \
    -H "$AUTH" -H "Accept: application/json" "$@" "$url" 2>/tmp/cos_err || echo "ERR")
  echo "########## $label"
  echo "# $method ${url#"$BASE"}  -> HTTP $code"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import sys,json;print(json.dumps(json.load(open('$body')),indent=2))" 2>/dev/null \
      || { echo "(non-JSON) $(head -c 500 "$body" | tr '\n' ' ')"; }
  else
    head -c 800 "$body"
  fi
  echo
  rm -f "$body"
}

echo "=== FULL AUDIT WALK — org=$ORG — $(date -u +%FT%TZ) ==="

echo
echo "########################## SETTINGS"
req "GET settings (before)" GET "$BASE/organizations/$ORG/settings"
req "PATCH settings" PATCH "$BASE/organizations/$ORG/settings" \
  -H "Content-Type: application/json" \
  --data '{"default_court":{"state":"CA","district":"CACB","division":"2"},"order_preferences":{"sides":"double_sided","format":"1up","service":"normal","mail_class":"first_class"}}'
req "GET settings (after)" GET "$BASE/organizations/$ORG/settings"

echo
echo "########################## CONTACTS"
req "GET contacts (list)" GET "$BASE/organizations/$ORG/contacts"
req "POST contact" POST "$BASE/organizations/$ORG/contacts" \
  -H "Content-Type: application/json" \
  --data '{"name":"Audit Contact","email":"audit-contact@example.com","phone":"213-555-0199","role":"operations"}'

echo
echo "########################## RETURN ADDRESSES"
req "GET return-addresses" GET "$BASE/organizations/$ORG/return-addresses"
req "POST return-address" POST "$BASE/organizations/$ORG/return-addresses" \
  -H "Content-Type: application/json" \
  --data '{"name":"Audit Return Addr","firm_name":"Hoffman & Associates, PC","line1":"350 S Grand Ave","city":"Los Angeles","state":"CA","zip_code":"90071","country":"US","is_default":true}'

echo
echo "########################## SIGNATURES"
req "GET signatures" GET "$BASE/organizations/$ORG/signatures"
req "POST signature" POST "$BASE/organizations/$ORG/signatures" \
  -H "Content-Type: application/json" \
  --data '{"name":"Audit Sig","full_name":"Nancy Hoffman","client_role":"Chapter 13 Trustee","phone":"213-555-0100","is_default":true}'

echo
echo "########################## TERMS"
req "GET terms/status" GET "$BASE/organizations/$ORG/terms/status"
req "POST terms/setup" POST "$BASE/organizations/$ORG/terms/setup" \
  -H "Content-Type: application/json" \
  --data '{"success_url":"https://example.com/ok","cancel_url":"https://example.com/cancel"}'

echo
echo "########################## BILLING"
req "GET billing/status" GET "$BASE/organizations/$ORG/billing/status"
req "POST billing/setup" POST "$BASE/organizations/$ORG/billing/setup" \
  -H "Content-Type: application/json" \
  --data '{"success_url":"https://example.com/ok","cancel_url":"https://example.com/cancel"}'

echo "=== END WALK (jobs handled separately) ==="
