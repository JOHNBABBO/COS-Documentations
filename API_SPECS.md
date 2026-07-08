# Certificate of Service — Partner API Spec

> **Status:** Working draft. Endpoints are subject to change prior to general availability.
>
> **Revision note (2026-06-25):** This copy incorporates the partner asks raised since the June 5 draft (partner discovery conversations in June). All additions/edits are tagged inline with **`[CHANGED 2026-06-25]`** so they can be reviewed before merging. Main additions: onboarding gate + terms-of-service acceptance; declined-payment semantics on billing status; a `draft` → estimate → submit job flow (pre-submission invoice estimate); organization tenancy + lookup by `external_id`; a partner-configuration note; and `4up` flagged as not yet supported by the backend.

---

## Overview

The CoS Partner API allows integration partners to submit physical mailing jobs, retrieve certificates of service, and manage organization and billing settings programmatically.

Billing is optional and configured per your business agreement with CoS. Organizations are set up for either direct Stripe payment (card or ACH) or monthly invoicing — this is determined during onboarding and is transparent to the API. When billing is enabled via Stripe, a valid payment method must be on file before jobs can be submitted.

**`[CHANGED 2026-06-25]` Onboarding gate.** For partners whose customers pay CoS directly, an organization must clear a two-condition **onboarding gate** before it can submit jobs: **(1) a valid payment method is on file** *and* **(2) the customer has accepted the current CoS Terms of Service.** Either condition can be checked independently (see `GET /organizations/{id}/billing/status` and `GET /organizations/{id}/terms/status`). For partners not configured to require direct payment or terms (the default), both conditions are treated as satisfied automatically and customers are never prompted.

**Base URL:** `https://api.certificateofservice.com/v1/cos`

---

## Authentication

API key authentication via the `Authorization` header. Keys are issued at the **platform level** per integration partner (not per firm/customer account).

```
Authorization: Bearer <api-key>
```

- Keys support optional **IP allowlists** and **per-credential scopes**
- Key rotation: request a new key from CoS; old key remains active during a transition window you agree on with CoS

---

## Partner configuration (set by CoS)

> **`[CHANGED 2026-06-25]`** A small number of settings are configured by CoS per your business agreement during onboarding. **You cannot change these via the API** — they're documented here only so you understand how your integration will behave. They apply to every organization you provision.

| Setting | Values | What it changes for you |
| --- | --- | --- |
| **Billing mode** | `stripe` \| `monthly_invoice` | `stripe`: your customers pay CoS directly; `billing/setup` and `billing/status` are active and a valid payment method is required before jobs can be submitted. `monthly_invoice`: CoS invoices in arrears; the `billing/*` endpoints return `403` and no payment method is required. |
| **Terms required** | `true` \| `false` | When `true`, each customer must accept the CoS Terms of Service before jobs can be submitted (observable via `GET /organizations/{id}/terms/status`). When `false`, terms are treated as accepted automatically and customers are never prompted. |

A “payment method required” gate is **not** a separate setting — it is implied by billing mode (`stripe` always requires one; `monthly_invoice` never does). The onboarding gate for an organization is therefore: *(payment method on file, if billing mode is `stripe`)* **and** *(terms accepted, if terms required)*.

---

## Data Model

```
Organization (a firm or trustee account in your platform)
  └── Settings (return_address, signature, default_court, order_preferences)
  └── Billing (optional — Stripe or monthly invoice, per partner agreement)
        └── Payment method (Stripe only; required before submitting jobs if Stripe billing is enabled)
  └── Jobs
        └── Mailings
              ├── Documents (uploaded PDFs)
              ├── Recipients (PACER pull or provided)
              ├── Cost breakdown
              └── Certificate (PDF, available on completion)
```

---

## Endpoints

### Organizations

An **organization** represents a firm or customer account within your platform. Partners can provision organizations programmatically.

**`[CHANGED 2026-06-25]` Tenancy.** Every organization endpoint is scoped to the authenticating partner's API key. A partner can only read, update, or list organizations it created; requesting an `organization_id` that belongs to another partner returns `404 not_found`. Organizations are managed entirely under the partner key — there are no per-organization logins or passwords.

---

#### `POST /organizations`

Provision a new organization.

> **v1 note:** Only US addresses are supported. The `address` object is structured to accommodate international addresses in a future release.

**Request body:**

```json
{
  "name": "Hoffman & Associates, PC",
  "external_id": "tfs-firm-4821",
  "contact_email": "billing@hoffmanpc.com",
  "company_phone_number": "213-555-0100",
  "address": {
    "line1": "350 S Grand Ave, Suite 2200",
    "line2": null,
    "city": "Los Angeles",
    "state": "CA",
    "zip_code": "90071",
    "country": "US"
  }
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | ✓ | Firm or organization name |
| `external_id` | string | | Your internal ID for this org — stored for cross-reference |
| `contact_email` | string | ✓ | Primary contact email |
| `company_phone_number` | string | ✓ | Must be unique |
| `address.line1` | string | ✓ | |
| `address.line2` | string | | |
| `address.city` | string | ✓ | |
| `address.state` | string | ✓ | US state code |
| `address.zip_code` | string | ✓ | |
| `address.country` | string | ✓ | Must be `"US"` in v1 |

**Response `201 Created`:**

```json
{
  "organization_id": "org_a1b2c3",
  "name": "Hoffman & Associates, PC",
  "external_id": "tfs-firm-4821",
  "contact_email": "billing@hoffmanpc.com",
  "company_phone_number": "213-555-0100",
  "address": {
    "line1": "350 S Grand Ave, Suite 2200",
    "line2": null,
    "city": "Los Angeles",
    "state": "CA",
    "zip_code": "90071",
    "country": "US"
  },
  "created_at": "2026-05-26T18:00:00Z"
}
```

---

#### `GET /organizations/{organization_id}`

Retrieve an organization by ID. **`[CHANGED 2026-06-25]`** Scoped to the authenticating partner — returns `404 not_found` if the org belongs to another partner.

**Response `200 OK`:** same shape as `POST /organizations` response.

---

#### `[CHANGED 2026-06-25]` `GET /organizations`

List organizations belonging to the authenticating partner. **Results are always filtered to the partner's own organizations (scoped by API key)** — a partner can never see another partner's organizations. Use the `external_id` filter to recover the CoS `organization_id` for an org you created (e.g. if you didn't persist it from the `POST` response).

**Query parameters:**

| Param | Type | Description |
|---|---|---|
| `external_id` | string | Return the org matching your own ID for it |
| `page` | integer | Default 1 |
| `per_page` | integer | Default 25, max 100 |

**Response `200 OK`:**

```json
{
  "organizations": [ /* array of organization objects, same shape as GET /organizations/{id} */ ],
  "pagination": {
    "page": 1,
    "per_page": 25,
    "total": 1
  }
}
```

Returns an empty `organizations` array (not `404`) when no org matches the filter within the partner's scope.

---

#### `PATCH /organizations/{organization_id}`

Update organization details (name, contact info, external ID, address). **`[CHANGED 2026-06-25]`** Scoped to the authenticating partner; `404 not_found` for another partner's org.

**Request body:** any subset of the `POST /organizations` fields.

---

### Organization Settings

Firm-level defaults applied to every job submitted by that organization unless overridden at the job level.

---

#### `GET /organizations/{organization_id}/settings`

**Response `200 OK`:**

```json
{
  "organization_id": "org_a1b2c3",
  "return_address": {
    "address_name": "Nancy Hoffman, Trustee",
    "firm_name": "Hoffman & Associates, PC",
    "line1": "350 S Grand Ave, Suite 2200",
    "line2": null,
    "city": "Los Angeles",
    "state": "CA",
    "zip_code": "90071",
    "country": "US"
  },
  "signature": {
    "full_name": "Nancy Hoffman",
    "bar_number": "123456",
    "client_role": "Chapter 13 Trustee"
    /* any optional address fields set on the org appear here */
  },
  "default_court": {
    "state": "CA",
    "district": "CACB",
    "division": null
  },
  "order_preferences": {
    "sides": "double_sided",
    "format": "2up",
    "service": "normal",
    "mail_class": "first_class"
  }
}
```

**`return_address` field reference:**

At least one of `address_name` or `firm_name` is required.

| Field | Type | Required | Notes |
|---|---|---|---|
| `address_name` | string | one of | Individual name, e.g. `"Nancy Hoffman, Trustee"` |
| `firm_name` | string | one of | Firm name |
| `line1` | string | ✓ | |
| `line2` | string | | |
| `city` | string | ✓ | |
| `state` | string | ✓ | US state code |
| `zip_code` | string | ✓ | |
| `country` | string | ✓ | Must be `"US"` in v1 |

**`order_preferences` field reference:**

| Field | Type | Values | Notes |
|---|---|---|---|
| `sides` | string | `"double_sided"` \| `"one_sided"` | Default: `"double_sided"` |
| `format` | string | `"2up"` \| `"1up"` ~~\| `"4up"`~~ | Default: `"2up"`. **`[CHANGED 2026-06-25]` `4up` NOT yet supported by the backend** (print pipeline implements only `1up`/`2up`). Pending eng decision — see handoff doc. |
| `service` | string | `"normal"` \| `"rush"` | Default: `"normal"` |
| `mail_class` | string | `"first_class"` \| `"certified"` \| `"priority_express"` | Default: `"first_class"`. **`certified` and `priority_express` can only be set at the org settings or job level** — not per-recipient. |

**`signature` field reference:**

`full_name`, `bar_number`, and `client_role` are required. Address fields are optional — when omitted, the org's `return_address` is used on the signature block.

| Field | Type | Required | Notes |
|---|---|---|---|
| `full_name` | string | ✓ | Name of the signatory |
| `bar_number` | string | ✓ | |
| `client_role` | string | ✓ | e.g. `"Chapter 13 Trustee"`, `"Attorney for Debtor"` |
| `firm_name` | string | | |
| `address_line1` | string | | |
| `address_line2` | string | | |
| `city` | string | | |
| `state` | string | | US state code |
| `zip_code` | string | | |
| `phone` | string | | |
| `email` | string | | |
| `fax` | string | | |

---

#### `PATCH /organizations/{organization_id}/settings`

Update any subset of the organization's settings. Omitted fields are preserved.

**Request body:**

```json
{
  "return_address": {
    "address_name": "Nancy Hoffman, Trustee",
    "firm_name": "Hoffman & Associates, PC",
    "line1": "350 S Grand Ave, Suite 2200",
    "city": "Los Angeles",
    "state": "CA",
    "zip_code": "90071",
    "country": "US"
  },
  "signature": {
    "full_name": "Nancy Hoffman",
    "bar_number": "123456",
    "client_role": "Chapter 13 Trustee"
  },
  "default_court": {
    "state": "CA",
    "district": "CACB"
  },
  "order_preferences": {
    "sides": "double_sided",
    "format": "2up",
    "service": "normal",
    "mail_class": "first_class"
  }
}
```

---

### Billing

---

#### `POST /organizations/{organization_id}/billing/setup`

Only applicable to organizations configured for Stripe billing. Returns `403` if the organization is on monthly invoicing.

Generates a Stripe-hosted payment setup URL. Direct your customer to this URL to securely enter their card or bank account details. The URL expires after 24 hours. Both card and ACH (US bank account) are supported.

If a payment method is already on file, it will be replaced when the customer completes this flow.

**Request body:**

```json
{
  "success_url": "https://your-app.com/billing/success",
  "cancel_url": "https://your-app.com/billing/cancel"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `success_url` | string | ✓ | Redirects here after successful setup |
| `cancel_url` | string | ✓ | Redirects here if the customer abandons setup |

**Response `200 OK`:**

```json
{
  "organization_id": "org_a1b2c3",
  "setup_url": "https://checkout.stripe.com/c/pay/cs_live_...",
  "expires_at": "2026-05-27T18:00:00Z"
}
```

---

#### `GET /organizations/{organization_id}/billing/status`

Check whether a valid payment method is on file. Only applicable to organizations configured for Stripe billing; returns `403` for monthly-invoiced orgs.

**Response `200 OK`:**

```json
{
  "organization_id": "org_a1b2c3",
  "payment_configured": true,
  "payment_method": {
    "type": "card",
    "last4": "4242",
    "brand": "visa"
  },
  "payment_standing": "ok",
  "orders_blocked": false,
  "outstanding_balance": { "amount": 0.00, "currency": "USD" }
}
```

If no payment method is configured, `payment_configured` will be `false` and `payment_method` will be `null`.

**`[CHANGED 2026-06-25]` Declined-payment semantics.** Per partner request, an organization with an unresolved declined payment must be prevented from submitting new jobs until it clears the outstanding balance **and** supplies a new acceptable payment method. The platform already tracks this state internally (job status `completed_payment_declined`, `order.payment_failed_at`, and admin notifications), so the partner API surfaces it here rather than introducing a separate endpoint:

| Field | Type | Notes |
|---|---|---|
| `payment_standing` | string | `"ok"` \| `"declined"` \| `"past_due"`. Reflects whether the org has an unresolved failed payment. |
| `orders_blocked` | boolean | `true` when submitting a job (`POST /jobs/mailings/{id}/submit`) will be rejected for payment reasons. Driven by `payment_standing` and `payment_configured`. |
| `outstanding_balance` | object | Amount that must be cleared before `orders_blocked` returns to `false`. `{ amount, currency }`. |

When `orders_blocked` is `true`, `POST /jobs/mailings/{id}/submit` returns `402 payment_required` (a `draft` can still be created and estimated). To recover, the partner directs the customer back through `POST /organizations/{id}/billing/setup` (re-auth flow) and settles the outstanding balance; the block lifts automatically once both are resolved.

---

### Terms of Service

> **`[CHANGED 2026-06-25]` New section.** Added per partner request: customers must formally accept the CoS Terms of Service before any mailing is sent. **Display is partner-managed** — the partner renders the ToS text (returned by `GET .../terms/status`) and the acceptance UX (checkbox, submit) inside their own product, then records the acceptance via the API. CoS does not host a redirect page for this. For partners not configured to require terms, `terms_required` is `false` and `terms_accepted` is always `true`.

---

#### `GET /organizations/{organization_id}/terms/status`

Check whether the organization has accepted the current Terms of Service. Mirrors the shape of `billing/status` so partners can gate onboarding on both with one pattern.

**Response `200 OK`:**

```json
{
  "organization_id": "org_a1b2c3",
  "terms_required": true,
  "terms_accepted": false,
  "current_version": "2026-06-01",
  "accepted_version": null,
  "accepted_at": null,
  "terms_url": "https://www.certificateofservice.com/legal/tos/2026-06-01"
}
```

| Field | Type | Notes |
|---|---|---|
| `terms_required` | boolean | `false` for partners not configured to require ToS — in which case `terms_accepted` is always `true`. |
| `terms_accepted` | boolean | `true` only when `accepted_version` matches `current_version`. |
| `current_version` | string | Identifier of the ToS version currently in force. |
| `accepted_version` | string \| null | Version the org last accepted, if any. |
| `accepted_at` | string \| null | ISO 8601 timestamp of acceptance. |
| `terms_url` | string | Canonical URL of the ToS text for the partner to display. |

A new acceptance is required whenever `current_version` advances beyond `accepted_version`.

---

#### `POST /organizations/{organization_id}/terms/acceptance`

Record that the organization has accepted the current Terms of Service. The partner calls this after their customer has acknowledged and submitted acceptance in the partner UI.

**Request body:**

```json
{
  "accepted_version": "2026-06-01",
  "accepted_by": "nancy@hoffmanpc.com",
  "accepted_at": "2026-06-25T17:00:00Z"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `accepted_version` | string | ✓ | Must equal the `current_version` returned by `GET .../terms/status`. A stale version returns `409 conflict`. |
| `accepted_by` | string | ✓ | Identifier (email/name) of the person who accepted, stored for audit. |
| `accepted_at` | string |  | ISO 8601 timestamp; defaults to receipt time if omitted. |

**Response `200 OK`:** same shape as `GET .../terms/status` with `terms_accepted: true`.

---

### Jobs

All mailing jobs live under `/jobs/mailings`. This path is structured to allow other job categories to be added in the future without breaking existing integrations.

---

#### `POST /jobs/mailings`

**`[CHANGED 2026-06-25]`** Create a new mailing job as a **draft** and return an itemized cost estimate. Documents must be uploaded first via `POST /documents`. The job is **not** released for printing until you confirm it via `POST /jobs/mailings/{job_id}/submit`. For PACER-sourced jobs the PACER lookup runs now (at draft creation), so the estimate reflects the actual recipient list. A draft that is never submitted expires after 48 hours.

**Request body (JSON):**

```json
{
  "organization_id": "org_a1b2c3",
  "type": "bankruptcy_notice",
  "documents": ["doc_abc123", "doc_def456"],
  "recipients": {
    "source": "pacer"
  },
  "order_preferences": {
    "sides": "double_sided",
    "format": "2up",
    "service": "normal",
    "mail_class": "first_class"
  },
  "external_reference": "case-10001-notice-q1",
  "bankruptcy_options": {
    "case_numbers": ["2:24-bk-10001"],
    "court_location": { "state": "CA", "district": "CACB" }
  }
}
```

**Field reference:**

| Field | Type | Required | Notes |
|---|---|---|---|
| `organization_id` | string | ✓ | Owning org |
| `type` | string | ✓ | See job types below |
| `documents` | array | ✓ | 1–15 `document_id` strings. **Array order is respected** — documents print in the order listed. Document role (`standard`, `ballot`, `proof_of_claim`) is set at upload time via `POST /documents`. |
| `recipients.source` | string | ✓ | `"pacer"` or `"user_supplied"` |
| `recipients.addresses` | array | if source=user_supplied | See recipient object below |
| `order_preferences.sides` | string | | `"double_sided"` (default) or `"one_sided"` |
| `order_preferences.format` | string | | `"2up"` (default) or `"1up"`. **`[CHANGED 2026-06-25]` `4up` not yet supported — see handoff doc.** |
| `order_preferences.service` | string | | `"normal"` (default) or `"rush"` |
| `order_preferences.mail_class` | string | | `"first_class"` (default), `"certified"`, or `"priority_express"`. Overrides org default. **`certified` and `priority_express` are only settable at the org settings or job level.** |
| `return_address` | object | | Overrides org default. Same shape as `return_address` in settings. |
| `signature` | object | | Overrides org default. See signature object below. |
| `external_reference` | string | | Your reference ID; stored for your records |
| `bankruptcy_options` | object | if type=bankruptcy_notice | See bankruptcy options object below |

**Job types (`type`):**

| Value | Description | v1 Scope |
|---|---|---|
| `bankruptcy_notice` | Standard BN notice | ✓ Tier 1 |
| `legal` | General legal mailing | Tier 2 (future) |
| `direct_mailing` | Direct mail campaign | Tier 3 (future) |

Use `"pacer"` to pull the recipient list from PACER using the submitted court and case number. Use `"user_supplied"` to supply addresses directly.

If PACER is unavailable or the case cannot be found, the job submission will return a `422` with code `pacer_error`.

**Recipient object (when `source = "user_supplied"`):**

```json
"addresses": [
  {
    "name": "Bank of America NA",
    "address": [
      "PO Box 15019",
      "Wilmington, DE 19850"
    ]
  }
]
```

**Bankruptcy options object (`bankruptcy_options`):**

Required when `type` is `"bankruptcy_notice"`. Debtor name, joint debtor name, and case chapter are pulled automatically from PACER and do not need to be supplied.

| Field | Type | Required | Notes |
|---|---|---|---|
| `case_numbers` | array | ✓ | One or more case number strings |
| `court_location` | object | ✓ | `state`, `district`, optional `division` |
| `adversary_proceeding` | object | | All-or-nothing: omit entirely or supply all fields (see below) |
| `return_envelope` | object | | See return envelope object below |
| `certificate_preferences` | object | | See certificate preferences object below |

**Adversary proceeding object (`bankruptcy_options.adversary_proceeding`):**

All fields are required if the object is present. Omit the entire object if there is no adversary proceeding.

| Field | Type | Required | Notes |
|---|---|---|---|
| `adversary_number` | string | ✓ | |
| `adversary_plaintiff` | string | ✓ | Max 40 characters |
| `adversary_defendant` | string | ✓ | Max 40 characters |

**Return envelope object (`bankruptcy_options.return_envelope`):**

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | ✓ | Max 144 characters |
| `office` | string | | Max 144 characters |
| `address` | string | ✓ | Max 144 characters |
| `city` | string | ✓ | Max 144 characters |
| `state` | string | ✓ | US state code |
| `zip_code` | string | ✓ | |
| `is_postage_included` | boolean | ✓ | |

**Certificate preferences object (`bankruptcy_options.certificate_preferences`):**

| Field | Type | Notes |
|---|---|---|
| `should_attach_docs` | boolean | Whether to attach submitted documents to the certificate PDF |
| `custom_file_name` | string | Override the default certificate filename |
| `should_include_nef` | boolean | Whether to include the NEF on the certificate |
| `hearing_information.hearing_date` | string | |
| `hearing_information.hearing_time` | string | |
| `hearing_information.hearing_location` | string | |
| `hearing_information.response_date` | string | |

**Signature object (`signature`):**

Overrides the org-level signature default for this job. `full_name`, `bar_number`, and `client_role` are required if the object is present. Address fields are optional — when omitted, they default to the org's `return_address`.

| Field | Type | Required | Notes |
|---|---|---|---|
| `full_name` | string | ✓ | Name of the signatory |
| `bar_number` | string | ✓ | |
| `client_role` | string | ✓ | e.g. `"Chapter 13 Trustee"`, `"Attorney for Debtor"` |
| `firm_name` | string | | |
| `address_line1` | string | | |
| `address_line2` | string | | |
| `city` | string | | |
| `state` | string | | US state code |
| `zip_code` | string | | |
| `phone` | string | | |
| `email` | string | | |
| `fax` | string | | |

**Response `201 Created`:** **`[CHANGED 2026-06-25]`** the job is created in `draft` status with an itemized `cost_estimate`. Review it, then confirm with `POST /jobs/mailings/{job_id}/submit`.

```json
{
  "job_id": "job_z9y8x7",
  "organization_id": "org_a1b2c3",
  "status": "draft",
  "type": "bankruptcy_notice",
  "case_number": "2:24-bk-10001",
  "external_reference": "case-10001-notice-q1",
  "recipient_count": 47,
  "cost_estimate": {
    "document_processing": 0.00,
    "usps_postage": 32.17,
    "per_notice_fee": 8.46,
    "subtotal": 40.63,
    "sales_tax": 0.00,
    "total": 40.63,
    "currency": "USD"
  },
  "expires_at": "2026-05-28T18:05:00Z",
  "created_at": "2026-05-26T18:05:00Z"
}
```

---

#### `[CHANGED 2026-06-25]` `POST /jobs/mailings/{job_id}/submit`

Confirm a `draft` job and release it for printing. The job transitions `draft` → `submitted` and is mailed exactly as estimated — no re-pricing and no second PACER lookup. The onboarding gate is enforced here (not at draft creation): returns `402 payment_required` or `403 terms_not_accepted` if the org isn't cleared, `409 conflict` if the job is not in `draft` status, or `422 validation_error` if the draft has expired.

**Response `200 OK`:**

```json
{
  "job_id": "job_z9y8x7",
  "status": "submitted",
  "created_at": "2026-05-26T18:05:00Z"
}
```

---

#### `GET /jobs/mailings/{job_id}`

Get job status and details. **Poll this endpoint to track progress.**

**Response `200 OK`:**

```json
{
  "job_id": "job_z9y8x7",
  "organization_id": "org_a1b2c3",
  "status": "completed",
  "type": "bankruptcy_notice",
  "case_number": "2:24-bk-10001",
  "external_reference": "case-10001-notice-q1",
  "recipient_count": 47,
  "certificate_ready": true,
  "cost": {
    "document_processing": 0.00,
    "usps_postage": 32.17,
    "per_notice_fee": 8.46,
    "subtotal": 40.63,
    "sales_tax": 0.00,
    "total": 40.63,
    "currency": "USD"
  },
  "created_at": "2026-05-26T18:05:00Z",
  "mailed_at": "2026-05-27T14:30:00Z"
}
```

**`[CHANGED 2026-06-25]`** For PACER-sourced jobs the PACER lookup runs at **draft creation**, so `recipient_count` and the cost are known from the `draft` onward (returned as `cost_estimate`). Once the job reaches `completed`, `cost` reflects final actuals.

**Job status values:**

| Status | Description |
|---|---|
| `draft` | **`[CHANGED 2026-06-25]`** Created with a cost estimate; not yet submitted. Expires after 48h if not confirmed. |
| `submitted` | Job confirmed and received by CoS |
| `in_queue` | Queued for printing |
| `processing` | Being prepared for print |
| `printing` | Being printed |
| `completed` | Envelopes mailed; certificate of service available |
| `cancelled` | Cancelled before printing |
| `on_hold` | On hold — CoS will reach out if action is needed |

**Suggested polling interval:** 30 seconds while status is `submitted`, `in_queue`, or `processing`. Once `completed`, stop polling.

---

#### `GET /jobs/mailings`

List mailing jobs for an organization.

**Query parameters:**

| Param | Type | Description |
|---|---|---|
| `organization_id` | string | Required |
| `status` | string | Filter by status |
| `case_number` | string | Filter by case number |
| `external_reference` | string | Filter by your reference ID |
| `created_after` | ISO 8601 datetime | |
| `created_before` | ISO 8601 datetime | |
| `page` | integer | Default 1 |
| `per_page` | integer | Default 25, max 100 |

**Response `200 OK`:**

```json
{
  "mailings": [ /* array of job objects (same shape as GET /jobs/mailings/{id}) */ ],
  "pagination": {
    "page": 1,
    "per_page": 25,
    "total": 142
  }
}
```

---

#### `POST /jobs/mailings/{job_id}/cancel`

Cancel a job. Only valid while status is `submitted` or `in_queue`.

**Response `200 OK`:**

```json
{
  "job_id": "job_z9y8x7",
  "status": "cancelled"
}
```

---

### Documents

Documents must be uploaded before a job is submitted. Upload returns a `document_id` you include in `POST /jobs/mailings`.

---

#### `POST /documents`

Upload a document. Multipart form upload.

**Request:** `multipart/form-data`

| Field | Type | Description |
|---|---|---|
| `file` | binary | PDF file. Max 20 MB per file. |
| `organization_id` | string | Owning org |
| `role` | string | `standard` (default) \| `ballot` \| `proof_of_claim` |
| `docket_description` | string | Appears on the certificate of service for this document. Max 85 characters. |
| `docket_reference_number` | string | Optional document reference number. Max 4 characters. |

**Constraints:** PDF only. Max 20 MB per file, max 100 MB total across all documents in a single job.

**Response `201 Created`:**

```json
{
  "document_id": "doc_abc123",
  "filename": "motion-to-sell.pdf",
  "page_count": 12,
  "organization_id": "org_a1b2c3",
  "created_at": "2026-05-26T17:50:00Z"
}
```

---

#### `GET /documents/{document_id}`

Get document metadata.

**Response `200 OK`:**

```json
{
  "document_id": "doc_abc123",
  "filename": "motion-to-sell.pdf",
  "page_count": 12,
  "role": "standard",
  "organization_id": "org_a1b2c3",
  "docket_description": "Motion to Sell Property",
  "docket_reference_number": null,
  "created_at": "2026-05-26T17:50:00Z"
}
```

---

### Certificates

The certificate of service PDF is generated when the job completes. It is stored for **90 days** from the mail date.

---

#### `GET /jobs/mailings/{job_id}/certificate`

Download the certificate of service. Returns a signed URL that expires in 15 minutes and can be re-fetched at any time within the 90-day retention window.

**Response `200 OK`:**

```json
{
  "job_id": "job_z9y8x7",
  "certificate_url": "https://certificates.certificateofservice.com/signed/...",
  "url_expires_at": "2026-05-26T18:30:00Z",
  "generated_at": "2026-05-27T14:35:00Z",
  "stored_until": "2026-08-25T14:35:00Z"
}
```

Returns `404` if the certificate is not yet ready (check `certificate_ready` on `GET /jobs/mailings/{job_id}` first) or if the 90-day retention window has passed.

---

### Job Cost Breakdown

Detailed per-recipient cost data for billing passthrough. Chapter 13 trustees use this to populate the Trustee's Final Report (actual postage + $0.18/notice federal allowance).

---

#### `GET /jobs/mailings/{job_id}/cost`

Returns `null` for all fields until the job reaches `completed` status.

**Response `200 OK`:**

```json
{
  "job_id": "job_z9y8x7",
  "case_number": "2:24-bk-10001",
  "recipient_count": 47,
  "document_processing": 0.00,
  "usps_postage": 32.17,
  "per_notice_fee": 8.46,
  "per_notice_rate": 0.18,
  "subtotal": 40.63,
  "sales_tax": 0.00,
  "total": 40.63,
  "currency": "USD"
}
```

---

## Errors

All errors return a consistent envelope:

```json
{
  "error": {
    "code": "validation_error",
    "message": "Field 'case_numbers' is required for type 'bankruptcy_notice'.",
    "job_id": null
  }
}
```

**Error codes:**

| HTTP | Code | Meaning |
|---|---|---|
| 400 | `invalid_request` | Missing or malformed field |
| 401 | `unauthorized` | Invalid or missing API key |
| 402 | `payment_required` | No valid payment method on file, **or `[CHANGED 2026-06-25]` an unresolved declined payment is blocking new orders** (Stripe-billed orgs only). Check `payment_standing` / `orders_blocked` on `GET .../billing/status`. |
| 403 | `terms_not_accepted` | **`[CHANGED 2026-06-25]`** Org has not accepted the current Terms of Service; record acceptance via `POST .../terms/acceptance` first (applies only where `terms_required` is `true`). |
| 403 | `forbidden` | Credential lacks scope for this action |
| 404 | `not_found` | Resource doesn't exist |
| 409 | `conflict` | Duplicate `external_reference` (scoped per org) or non-unique phone number |
| 422 | `validation_error` | Input passes format checks but fails business logic |
| 422 | `pacer_error` | PACER unavailable or case not found — job not created |
| 429 | `rate_limited` | Too many requests — see `Retry-After` header |
| 500 | `internal_error` | CoS-side error |