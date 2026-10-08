# Partner API — Live Audit Findings (COS-26091)

Comparing the **live staging implementation** (`https://backend.staging.thenoticingcenter.com/v1/cos`)
against **`API_SPECS (1).md`** (revision 2026-07-14).

Partner used for read-only walk: **"Adan Test 1"** — `billingMode: stripe`, `termsRequired: false`.
Test org: `7780303033`.

Legend: 🔴 doc wrong / must fix · 🟡 needs confirmation · 🟢 doc matches live · 🆕 live has endpoint the status doc marked "not available"

---

## 1. Organizations

### `GET /organizations/{id}` — 🔴 response schema differs from spec
Live response:
```json
{
  "organization_id": "7780303033",
  "name": "Hoffman & Associates, PC",
  "type": "Consumer Bankruptcy",
  "address": { "line1": "...", "city": "...", "state": "CA", "zip_code": "90071", "country": "US" },
  "phone": "2135550119",
  "created_at": "...",
  "updated_at": "..."
}
```
Discrepancies vs spec:
- Live has `type` (e.g. "Consumer Bankruptcy") — **not documented**.
- Live has top-level `phone` — spec puts phone only on the contact, not the org.
- Live response has **no `external_id`** — spec documents it on create/response.
- Live response has **no embedded `contact` object** — spec shows one.
- Live includes `updated_at` — spec shows only `created_at`.
- Live `address` omits `line2` when null — spec shows `line2: null`.
- `organization_id` is a numeric string ("7780303033"), not the `org_a1b2c3` style the spec uses in examples.

## 2. Settings

### `GET /organizations/{id}/settings` — 🆕 LIVE (status doc said "not available") · 🟡 shape
Live:
```json
{ "organization_id": "...", "default_contact_id": 15, "default_return_address_id": null,
  "default_signature_id": null, "default_court": null, "order_preferences": null }
```
- Endpoint is live — status doc (Sept 1) listed GET /settings as not available. Status doc outdated.
- `default_contact_id` is an **integer** (15), spec shows string IDs ("con_123").
- `default_court` / `order_preferences` are `null` for a fresh org (spec implies populated objects / defaults). 🟡 confirm whether defaults are applied server-side.

## 3. Nested collections — 🆕 all LIVE (status doc said "not available")

### `GET .../contacts`
```json
{ "contacts": [ { "contact_id": 15, "name": "Nancy Hoffman", "email": "...",
  "phone": "213-555-0119", "role": "admin", "is_default": true, "created_at": "...", "updated_at": "..." } ] }
```
- 🔴 `contact_id` is an **integer**, spec shows string ("con_123").
- 🟢 field names otherwise match.

### `GET .../return-addresses`
```json
{ "organization_id": "...", "return_addresses": [] }
```
- 🔴 Live wraps with an extra top-level `organization_id`; spec shows `{ "return_addresses": [...] }` only.

### `GET .../signatures`
```json
{ "organization_id": "...", "signatures": [] }
```
- 🔴 Same extra `organization_id` wrapper vs spec's `{ "signatures": [...] }`.

## 4. Billing

### `GET .../billing/status` — 🟢 shape matches
```json
{ "organization_id": "...", "payment_configured": false, "payment_method": null,
  "payment_standing": "ok", "orders_blocked": true, "outstanding_balance": { "amount": 0, "currency": "USD" } }
```
- Matches spec. `orders_blocked:true` with no payment method is consistent with the stripe gate.
- 🟡 `outstanding_balance.amount` is `0` (integer) vs spec `0.0` — cosmetic JSON number formatting.

## 5. Terms

### `GET .../terms/status` — 🟢 behavior matches (terms not required) · 🟡 null fields
```json
{ "organization_id": "...", "terms_required": false, "terms_accepted": true,
  "current_version": null, "accepted_version": null, "accepted_at": null, "accepted_by": null, "terms_url": null }
```
- `terms_required:false → terms_accepted:true` matches spec auto-accept.
- 🟡 `current_version` and `terms_url` are `null` here; spec example shows them populated. Confirm against a `termsRequired:true` partner.

## 6. Jobs

### `GET /jobs/mailings` (list) — 🆕 LIVE (status doc said "not available") · 🟢 shape
```json
{ "mailings": [], "pagination": { "page": 1, "per_page": 25, "total": 0 } }
```
- Matches spec shape.

### `GET /organizations` (list, no id) — 🔴 NOT implemented
- Returns Express `404 Cannot GET /v1/cos/organizations`. Spec documents a list endpoint with `external_id`/pagination. Not live.

---

## Status-doc (260901) items that are now STALE
- `GET /settings`, contacts/return-addresses/signatures collections, `GET /jobs/mailings` are all LIVE now despite being listed "not yet available" (Sept 1).

## Still to test (writes — need confirmation)
- `POST /organizations`, `PATCH /organizations/{id}`
- `PATCH .../settings`, create/patch/delete on nested collections
- `POST .../billing/setup`, `POST .../terms/setup`
- `POST /jobs/mailings` (draft), `/submit`, `/cancel`, `GET /{id}`, `/cost`, `/certificate`
- Error codes: 401 (bad/missing key), 404 variants, 422 validation, 409 conflict
- Billing/terms matrix: needs the other 3 partner keys


---

# Live write-walk findings (org 7780303033, partner stripe/termsRequired=false)

## Settings
- 🔴 **`default_court` requires FULL NAMES, not codes.** `PATCH .../settings` with `{"state":"CA","district":"CACB"}` → `400 invalid_request`: *"State \"CA\" is not recognised. Must match exactly, e.g. \"California\"."* The spec's examples (`CA`, `CACB`, division `"2"`) are wrong. Live wants `"California"`, `"Central"`, etc. (Same for job `court_location`.)
- 🟡 PATCH not re-verified with correct names yet (blocked by the 400 above using codes). Need a follow-up PATCH with full names to confirm the success shape + that GET reflects it.

## Contacts / Return addresses / Signatures
- 🔴 **All IDs are integers**, not strings: `contact_id:16`, `return_address_id:9`, `signature_id:9`. Spec uses `con_123`/`ra_123`/`sig_123`.
- 🔴 **Inconsistent list wrapper**: `contacts` → `{ "contacts":[...] }`; return-addresses & signatures → `{ "organization_id":"...", "<coll>":[...] }`. Spec shows none with `organization_id`.
- 🔴 **Signature response shape is leaner than spec.** POST signature returned: `signature_id,name,full_name,client_role,phone,bar_number,address_line1,city,state,zip_code,is_default,created_at,updated_at`. Spec's signature resource also lists `address_line2`, `firm_name`, `email`, `fax` — **absent in live response**.
- 🟢 Return-address "at least one of address_name/firm_name" rule holds — sent only `firm_name`, got 201.
- POST contact/return-address/signature all return `201` with the created object (matches spec behavior).

## Terms
- 🟢 `POST .../terms/setup` → `403 forbidden` for a `termsRequired:false` partner, message: "Terms setup is not applicable — terms are not required for this partner". Matches spec's "returns 403 otherwise."
- 🟡 The 200 path (termsRequired:true) still needs a different partner key to test.

## Billing
- 🟢 `POST .../billing/setup` → `200` with `setup_url` (real Stripe `cs_test_...` checkout URL — staging is Stripe TEST mode) and `expires_at` ~24h out. Matches spec.

## Jobs
- 🟢 `POST /jobs/mailings` (multipart, PACER source) → `201 draft`. PACER lookup runs at draft creation.
- 🔴 **PACER populates `debtor_name`, `chapter`, `judge_name`** even when not supplied (resolved from the case). Spec's 2026-07-14 note says `chapter`/`judge_name` are partner-supplied and "not independently verified" — live resolves them from PACER. Reconcile the spec wording.
- 🔴 **Extra response fields not in spec:** `document_count` (POST response) and `per_notice_rate` (inside cost breakdown, both POST and GET and /cost).
- 🔴 **`GET /jobs/mailings/{id}` returns BOTH `cost_estimate` and `cost:null`.** Spec shows only `cost` on GET.
- 🔴 **`GET .../cost` omits `job_id`, `case_number`, `recipient_count`** that the spec's cost object shows at top level; and returns `per_notice_rate`/`currency` non-null even pre-completion (spec says all null until completed).
- 🔴 **`GET .../certificate` → `404 Cannot GET` (route NOT mounted).** Endpoint not implemented. Spec documents it fully.
- 🔴 **Submit error message is self-contradictory.** `402 payment_required`: *"Orders are blocked: payment_standing is \"ok\". Outstanding balance: $0.00..."* — gate is actually driven by `payment_configured:false`, but the message cites `payment_standing:ok`. Misleading message (backend bug); not described in spec.
- 🟢 Submit gate itself works: `orders_blocked:true` (no payment method) → `402`. Draft remains `draft` after rejected submit.
- 🟢 `GET /jobs/mailings` list shape matches spec.

## Blocked / still needed for full Option B lifecycle
- To reach `submitted → completed` (and test certificate + final `cost` actuals), the payment gate must be cleared: either complete the Stripe `setup_url` in a browser, or use an org/partner that already has `payment_configured:true`. Submit cannot succeed while `orders_blocked:true`.
- `termsRequired:true` partner needed to test the terms 200 path and `403 terms_not_accepted` on submit.
