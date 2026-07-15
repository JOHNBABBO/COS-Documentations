# Certificate of Service — Partner API Spec

> **Status:** Working draft. Endpoints are subject to change prior to general availability.
>
> **Revision note (2026-07-14):** This copy incorporates the amendments agreed in the 2026-07-14 CoS ↔ Verita working session. All additions/edits are tagged inline with **`[CHANGED 2026-07-14]`** so they can be reviewed before merging. Main additions: organization-level **contacts**, **return addresses**, and **signatures** are now reusable, multi-record collections with their own nested endpoints and default semantics; jobs can reference saved records by ID or override inline (with explicit precedence rules); a per-job **notifications** block (primary email + CC list); `debtor_name`, `chapter`, and `judge_name` added to `bankruptcy_options` and echoed on job responses; PACER/case errors split into distinct codes including a first-class `debtor_name_mismatch`; and draft **snapshot** semantics for referenced saved records. The singular `contact_email` / `company_phone_number` fields and the singular `settings.return_address` / `settings.signature` objects from earlier drafts are **removed outright** in favor of the collections — no integrations are live against this API, so no deprecation path is carried.
>
> **Revision note (2026-06-25):** This copy incorporates the partner asks raised since the June 5 draft (partner discovery conversations in June). Main additions: onboarding gate + terms-of-service acceptance; declined-payment semantics on billing status; a `draft` → estimate → submit job flow (pre-submission invoice estimate); organization tenancy + lookup by `external_id`; a partner-configuration note; and `4up` flagged as not yet supported by the backend.
---

## Overview

The CoS Partner API allows integration partners to submit physical mailing jobs, retrieve certificates of service, and manage organization and billing settings programmatically.

Billing is optional and configured per your business agreement with CoS. Organizations are set up for either direct Stripe payment (card or ACH) or monthly invoicing — this is determined during onboarding and is transparent to the API. When billing is enabled via Stripe, a valid payment method must be on file before jobs can be submitted.

**Onboarding gate.** For partners whose customers pay CoS directly, an organization must clear a two-condition **onboarding gate** before it can submit jobs: **(1) a valid payment method is on file** *and* **(2) the customer has accepted the current CoS Terms of Service.** Either condition can be checked independently (see `GET /organizations/{id}/billing/status` and `GET /organizations/{id}/terms/status`). For partners not configured to require direct payment or terms (the default), both conditions are treated as satisfied automatically and customers are never prompted.

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

> A small number of settings are configured by CoS per your business agreement during onboarding. **You cannot change these via the API** — they're documented here only so you understand how your integration will behave. They apply to every organization you provision.

| Setting            | Values                        | What it changes for you                                                                                                                                                                                  |
| ------------------ | ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Billing mode**   | `stripe` \| `monthly_invoice` | `stripe`: your customers pay CoS directly; `billing/setup` and `billing/status` are active and a valid payment method is required before jobs can be submitted. `monthly_invoice`: CoS invoices in arrears; the `billing/*` endpoints return `403` and no payment method is required. |
| **Terms required** | `true` \| `false`             | When `true`, each customer must accept the CoS Terms of Service before jobs can be submitted (observable via `GET /organizations/{id}/terms/status`). When `false`, terms are treated as accepted automatically and customers are never prompted. |

A "payment method required" gate is **not** a separate setting — it is implied by billing mode (`stripe` always requires one; `monthly_invoice` never does). The onboarding gate for an organization is therefore: *(payment method on file, if billing mode is `stripe`)* **and** *(terms accepted, if terms required)*.

---

## Data Model

**`[CHANGED 2026-07-14]`** Contacts, return addresses, and signatures are now **reusable collections** on the organization rather than single settings values. Jobs may reference a saved record by ID, override inline, or fall back to the org default.

```
Organization (a firm or trustee account in your platform)
  └── Contacts (saved contact records; zero or one default)
  └── Return Addresses (saved return address records; zero or one default)
  └── Signatures (saved certificate signature records; zero or one default)
  └── Settings (default_court, order_preferences, default pointers)
  └── Billing (optional — Stripe or monthly invoice, per partner agreement)
        └── Payment method (Stripe only; required before submitting jobs if Stripe billing is enabled)
  └── Jobs
        └── Mailings
              ├── Documents (uploaded PDFs)
              ├── Recipients (PACER pull or provided)
              ├── Notifications (primary email + CC list)
              ├── Snapshot of referenced contact / return address / signature
              ├── Cost breakdown
              └── Certificate (PDF, available on completion)
```

---

## Endpoints

### Organizations

An **organization** represents a firm or customer account within your platform. Partners can provision organizations programmatically.

**Tenancy.** Every organization endpoint is scoped to the authenticating partner's API key. A partner can only read, update, or list organizations it created; requesting an `organization_id` that belongs to another partner returns `404 not_found`. Organizations are managed entirely under the partner key.

---

#### `POST /organizations`

Provision a new organization.
> **v1 note:** Only US addresses are supported. The `address` object is structured to accommodate international addresses in a future release.

**Account setup.** When an organization is provisioned, CoS automatically sends a welcome email to the initial default contact's email with a link to set a password on the CoS platform. This is a one-time step that lets the customer access CoS directly if needed. In most partner integrations, customers set their password once and continue to operate entirely within your platform. The email is sent from a CoS email address.

**One organization per customer.** Each customer should be provisioned as a single organization. Creating duplicate organizations for the same customer is not supported.

**`[CHANGED 2026-07-14]` Initial contact.** Provisioning takes a `contact` object, which is created as the organization's first saved contact with `is_default: true`. Additional contacts are managed through the [Organization Contacts](#organization-contacts) endpoints. The `contact_email` and `company_phone_number` fields from earlier drafts are removed.

**Request body:**

```
{
  "name": "Hoffman & Associates, PC",
  "external_id": "tfs-firm-4821",
  "contact": {
    "name": "Nancy Hoffman",
    "email": "billing@hoffmanpc.com",
    "phone": "213-555-0100",
    "role": "admin"
  },
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

| Field                  | Type   | Required | Notes                                                      |
| ---------------------- | ------ | -------- | ---------------------------------------------------------- |
| `name`                 | string | ✓        | Firm or organization name                                  |
| `external_id`          | string |          | Your internal ID for this org — stored for cross-reference |
| `contact`              | object | ✓        | Initial default contact `[CHANGED 2026-07-14]` — see [Organization Contacts](#organization-contacts) for field rules. `email` required; `phone` must be unique across organizations (used for account matching). |
| `address.line1`        | string | ✓        |                                                            |
| `address.line2`        | string |          |                                                            |
| `address.city`         | string | ✓        |                                                            |
| `address.state`        | string | ✓        | US state code                                              |
| `address.zip_code`     | string | ✓        |                                                            |
| `address.country`      | string | ✓        | Must be `"US"` in v1                                       |

**Response `201 Created`:**

```
{
  "organization_id": "org_a1b2c3",
  "name": "Hoffman & Associates, PC",
  "external_id": "tfs-firm-4821",
  "contact": {
    "contact_id": "con_123",
    "name": "Nancy Hoffman",
    "email": "billing@hoffmanpc.com",
    "phone": "213-555-0100",
    "role": "admin",
    "is_default": true
  },
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

Retrieve an organization by ID. Scoped to the authenticating partner — returns `404 not_found` if the org belongs to another partner.

**Response `200 OK`:** same shape as `POST /organizations` response.

---

#### `GET /organizations`

List organizations belonging to the authenticating partner. **Results are always filtered to the partner's own organizations (scoped by API key)** — a partner can never see another partner's organizations. Use the `external_id` filter to recover the CoS `organization_id` for an org you created (e.g. if you didn't persist it from the `POST` response).

**Query parameters:**

| Param         | Type    | Description                                |
| ------------- | ------- | ------------------------------------------ |
| `external_id` | string  | Return the org matching your own ID for it |
| `page`        | integer | Default 1                                  |
| `per_page`    | integer | Default 25, max 100                        |

**Response `200 OK`:**

```
{
  "organizations": [
    /* array of organization objects, same shape as GET /organizations/{id} */
  ],
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

Update organization details (name, contact info, external ID, address). Scoped to the authenticating partner; `404 not_found` for another partner's org.

**Request body:** any subset of the `POST /organizations` fields.

**`[CHANGED 2026-07-14]`** This endpoint covers org metadata only (name, external ID, address). Contacts, return addresses, and signatures are managed exclusively through the nested resource endpoints below.

---

### Organization Contacts

**`[CHANGED 2026-07-14]`** *New section.* Saved contact records for an organization. Different trustees/users within the same trustee group may need different phone and email values, so an organization can now store **multiple contacts**, optionally marking one as the default. Jobs can rely on the default contact, reference a specific saved contact by `contact_id`, or override notification values one-off (see [Jobs](#jobs)).

**Contact resource:**

```
{
  "contact_id": "con_123",
  "name": "Nancy Hoffman",
  "email": "nancy@hoffmanpc.com",
  "phone": "213-555-0100",
  "role": "admin",
  "is_default": true,
  "created_at": "2026-07-14T18:00:00Z",
  "updated_at": "2026-07-14T18:00:00Z"
}
```

| Field        | Type    | Required | Notes                                                                    |
| ------------ | ------- | -------- | ------------------------------------------------------------------------ |
| `contact_id` | string  | —        | Generated by CoS                                                         |
| `name`       | string  |          | Optional but recommended                                                 |
| `email`      | string  | ✓        | Required — the default contact's email receives job lifecycle notifications when no job-level email is supplied |
| `phone`      | string  |          |                                                                          |
| `role`       | string  |          | Free-form label, e.g. `"admin"`, `"trustee"`, `"operations"`             |
| `is_default` | boolean |          | At most one default per organization. Defaults to `false`.               |

**Behavior:**

- An organization always has **at least one contact**: the `contact` supplied at provisioning becomes the initial default. The last remaining contact cannot be deleted.
- Contact uniqueness is enforced on `email` within an organization (`409 conflict` on duplicates). `phone` is not required to be unique across contacts within the same organization — different trustees within a trustee group may share a phone number. The **default contact's phone** must be unique **across organizations** (CoS uses it for account matching/linkage).
- If a job omits all notification email fields, the fallback chain is: selected `contact_id`'s email → org default contact's email. See [Job notifications](#job-notifications).
- Default lifecycle rules are shared across all saved-record types — see [Defaults: lifecycle rules](#defaults-lifecycle-rules).

#### `GET /organizations/{organization_id}/contacts`

List saved contacts. **Response `200 OK`:** `{ "contacts": [ /* contact objects */ ] }`

#### `POST /organizations/{organization_id}/contacts`

Create a saved contact. Request body: contact fields above (no `contact_id`). Setting `is_default: true` automatically clears the previous default. **Response `201 Created`:** the contact object.

#### `GET /organizations/{organization_id}/contacts/{contact_id}`

Retrieve one saved contact. **Response `200 OK`:** the contact object. `404 contact_not_found` if it doesn't exist.

#### `PATCH /organizations/{organization_id}/contacts/{contact_id}`

Update any subset of fields on one saved contact. Omitted fields are preserved. Setting `is_default: true` clears the previous default.

#### `DELETE /organizations/{organization_id}/contacts/{contact_id}`

Delete a saved contact. See [Deletion rules](#deletion-rules-for-saved-records). **Response `204 No Content`.**

---

### Organization Return Addresses

**`[CHANGED 2026-07-14]`** *New section.* An organization may need **multiple return addresses**, and jobs may need to select a specific one rather than relying on a single global default. Each saved return address has a stable ID, a required label (`name`), and an optional default flag. This replaces the singular `settings.return_address` object from earlier drafts.

**Return address resource:**

```
{
  "return_address_id": "ra_123",
  "name": "Default Trustee Address",
  "is_default": true,
  "address_name": "Nancy Hoffman, Trustee",
  "firm_name": "Hoffman & Associates, PC",
  "line1": "350 S Grand Ave, Suite 2200",
  "line2": null,
  "city": "Los Angeles",
  "state": "CA",
  "zip_code": "90071",
  "country": "US",
  "created_at": "2026-07-14T18:00:00Z",
  "updated_at": "2026-07-14T18:00:00Z"
}
```

| Field               | Type    | Required | Notes                                                          |
| ------------------- | ------- | -------- | -------------------------------------------------------------- |
| `return_address_id` | string  | —        | Generated by CoS                                               |
| `name`              | string  | ✓        | Label for selection in partner UI; unique within the org       |
| `is_default`        | boolean |          | At most one default per organization. Defaults to `false`.     |
| `address_name`      | string  | one of   | Individual name, e.g. `"Nancy Hoffman, Trustee"`. At least one of `address_name` / `firm_name` is required. |
| `firm_name`         | string  | one of   | Firm name                                                      |
| `line1`             | string  | ✓        |                                                                |
| `line2`             | string  |          |                                                                |
| `city`              | string  | ✓        |                                                                |
| `state`             | string  | ✓        | US state code                                                  |
| `zip_code`          | string  | ✓        |                                                                |
| `country`           | string  | ✓        | Must be `"US"` in v1                                           |

**Limits:** max **25** saved return addresses per organization. `address_name`, `firm_name`, and `line1`/`line2` are limited to **40 characters** each to guarantee clean label output.

#### `GET /organizations/{organization_id}/return-addresses`

List saved return addresses. **Response `200 OK`:** `{ "return_addresses": [ /* objects */ ] }`

#### `POST /organizations/{organization_id}/return-addresses`

Create a saved return address. Setting `is_default: true` clears the previous default. **Response `201 Created`.**

#### `GET /organizations/{organization_id}/return-addresses/{return_address_id}`

Retrieve one saved return address. `404 return_address_not_found` if it doesn't exist.

#### `PATCH /organizations/{organization_id}/return-addresses/{return_address_id}`

Update any subset of fields. Omitted fields are preserved.

#### `DELETE /organizations/{organization_id}/return-addresses/{return_address_id}`

Delete a saved return address. See [Deletion rules](#deletion-rules-for-saved-records). **Response `204 No Content`.**

---

### Organization Signatures

**`[CHANGED 2026-07-14]`** *New section.* Organizations can save **multiple certificate signatures** — the signatory role differs by case (Chapter 7 trustee, Chapter 11 trustee, attorney, trustee in possession, etc.) — and select one per job. This replaces the singular `settings.signature` object from earlier drafts.

**Signature resource:**

```
{
  "signature_id": "sig_123",
  "name": "Chapter 13 Trustee",
  "is_default": true,
  "full_name": "Nancy Hoffman",
  "bar_number": "123456",
  "client_role": "Chapter 13 Trustee",
  "firm_name": "Hoffman & Associates, PC",
  "address_line1": "350 S Grand Ave, Suite 2200",
  "address_line2": null,
  "city": "Los Angeles",
  "state": "CA",
  "zip_code": "90071",
  "phone": "213-555-0100",
  "email": "nancy@hoffmanpc.com",
  "fax": null,
  "created_at": "2026-07-14T18:00:00Z",
  "updated_at": "2026-07-14T18:00:00Z"
}
```

| Field           | Type    | Required | Notes                                                          |
| --------------- | ------- | -------- | -------------------------------------------------------------- |
| `signature_id`  | string  | —        | Generated by CoS                                               |
| `name`          | string  | ✓        | Label for selection in partner UI; unique within the org       |
| `is_default`    | boolean |          | At most one default per organization. Defaults to `false`.     |
| `full_name`     | string  | ✓        | Name of the signatory                                          |
| `bar_number`    | string  |          | Optional — trustees who are not attorneys will not have one `[CHANGED 2026-07-14]` |
| `client_role`   | string  | ✓        | e.g. `"Chapter 13 Trustee"`, `"Attorney for Debtor"`           |
| `firm_name`     | string  |          |                                                                |
| `address_line1` | string  |          | Optional — inherits from the resolved return address when omitted (see Address inheritance) |
| `address_line2` | string  |          |                                                                |
| `city`          | string  |          |                                                                |
| `state`         | string  |          | US state code                                                  |
| `zip_code`      | string  |          |                                                                |
| `phone`         | string  | ✓        | Required on saved signatures `[CHANGED 2026-07-14]`            |
| `email`         | string  |          |                                                                |
| `fax`           | string  |          |                                                                |

**Address inheritance.** When a signature's address fields are omitted, the signature block inherits the address from the return address resolved for that job (job override → referenced saved record → org default). If the signature has no embedded address **and** no return address can be resolved for the job, the job is rejected with `422 validation_error`.

**Limits:** max **25** saved signatures per organization.

#### `GET /organizations/{organization_id}/signatures`

List saved signatures. **Response `200 OK`:** `{ "signatures": [ /* objects */ ] }`

#### `POST /organizations/{organization_id}/signatures`

Create a saved signature. Setting `is_default: true` clears the previous default. **Response `201 Created`.**

#### `GET /organizations/{organization_id}/signatures/{signature_id}`

Retrieve one saved signature. `404 signature_not_found` if it doesn't exist.

#### `PATCH /organizations/{organization_id}/signatures/{signature_id}`

Update any subset of fields. Omitted fields are preserved.

#### `DELETE /organizations/{organization_id}/signatures/{signature_id}`

Delete a saved signature. See [Deletion rules](#deletion-rules-for-saved-records). **Response `204 No Content`.**

---

### Defaults: lifecycle rules

**`[CHANGED 2026-07-14]`** *New section.* These rules apply uniformly to contacts, return addresses, and signatures:

- **Zero or one default** per resource type per organization. Attempting to create a second default in a single request without clearing the first returns `422 multiple_defaults_not_allowed` — but in practice this cannot occur, because:
- **Setting a new default automatically clears the previous one.** Creating or patching a record with `is_default: true` demotes the prior default in the same operation.
- **If no default exists** for a resource type, a job must either reference a saved record by ID or supply an inline override. A job that supplies neither is rejected with `422 default_required`.
- **Deleting a default is allowed** and leaves the organization with no default for that type until another record is promoted. Future jobs must then explicitly specify a record or override until a new default is set.

### Deletion rules for saved records

**`[CHANGED 2026-07-14]`** *New section.*

- **Non-default records** are always deletable.
- **Default records** are deletable; the org is left with no default for that type (see above). To avoid a gap, promote another record (`PATCH ... is_default: true`) before or after the delete.
- **Records referenced by drafts or submitted jobs** are safely deletable, because referenced records are **snapshotted onto the job at draft creation** (see [Job snapshot semantics](#job-snapshot-semantics)). Deleting a saved record never mutates or invalidates an existing draft or job.
- The **last remaining contact** on an organization cannot be deleted (`422 validation_error`) — CoS requires at least one contact for account communication.

---

### Organization Settings

Firm-level defaults applied to every job submitted by that organization unless overridden at the job level.

**`[CHANGED 2026-07-14]`** Settings now carries only true org-level defaults: `default_court`, `order_preferences`, and read-only pointers to the current default saved records. The singular `return_address` and `signature` objects previously stored here are removed — those records live in the nested collections.

---

#### `GET /organizations/{organization_id}/settings`

**Response `200 OK`:**

```
{
  "organization_id": "org_a1b2c3",
  "default_contact_id": "con_123",
  "default_return_address_id": "ra_123",
  "default_signature_id": "sig_123",
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

| Field                        | Type           | Notes                                                                                 |
| ---------------------------- | -------------- | ------------------------------------------------------------------------------------- |
| `default_contact_id`         | string \| null | Read-only pointer to the default contact. Manage via the contacts endpoints.          |
| `default_return_address_id`  | string \| null | Read-only pointer to the default return address.                                      |
| `default_signature_id`       | string \| null | Read-only pointer to the default signature.                                           |
| `default_court`              | object         | `state`, `district`, optional `division`                                              |
| `order_preferences`          | object         | See field reference below                                                             |

**`order_preferences` field reference:**

| Field        | Type   | Values                                                   | Notes                                                                                                                                  |
| ------------ | ------ | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `sides`      | string | `"double_sided"` \| `"one_sided"`                        | Default: `"double_sided"`                                                                                                              |
| `format`     | string | `"2up"` \| `"1up"` ~~\| `"4up"`~~                        | Default: `"2up"`. `4up` is not yet supported by the backend (print pipeline implements only `1up`/`2up`).                              |
| `service`    | string | `"normal"` \| `"rush"`                                   | Default: `"normal"`                                                                                                                    |
| `mail_class` | string | `"first_class"` \| `"certified"` \| `"priority_express"` | Default: `"first_class"`. **`certified` and `priority_express` can only be set at the org settings or job level** — not per-recipient. |

---

#### `PATCH /organizations/{organization_id}/settings`

Update any subset of the organization's settings. Omitted fields are preserved.

**`[CHANGED 2026-07-14]`** This endpoint accepts only `default_court` and `order_preferences`. Contacts, return addresses, and signatures are managed exclusively through their nested resource endpoints (`POST` to create, `PATCH` to update one record, `DELETE` to remove one record).

**Request body:**

```
{
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

Payment collection is handled through an embedded Stripe flow hosted within your platform. CoS stores only the Stripe payment token — no raw card or bank account details are ever held by CoS. Customers who need to update their payment method must go through a new Stripe setup flow, which you initiate via `POST /organizations/{id}/billing/setup`.

---

#### `POST /organizations/{organization_id}/billing/setup`

Only applicable to organizations configured for Stripe billing. Returns `403` if the organization is on monthly invoicing.

Generates a Stripe-hosted payment setup URL. Direct your customer to this URL to securely enter their card or bank account details. The URL expires after 24 hours. Both card and ACH (US bank account) are supported.

If a payment method is already on file, it will be replaced when the customer completes this flow.

**Request body:**

```
{
  "success_url": "https://your-app.com/billing/success",
  "cancel_url": "https://your-app.com/billing/cancel"
}
```

| Field         | Type   | Required | Notes                                         |
| ------------- | ------ | -------- | --------------------------------------------- |
| `success_url` | string | ✓        | Redirects here after successful setup         |
| `cancel_url`  | string | ✓        | Redirects here if the customer abandons setup |

**Response `200 OK`:**

```
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

```
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
  "outstanding_balance": { "amount": 0.0, "currency": "USD" }
}
```

If no payment method is configured, `payment_configured` will be `false` and `payment_method` will be `null`.

**Declined-payment semantics.** An organization with an unresolved declined payment is prevented from submitting new jobs until it clears the outstanding balance **and** supplies a new acceptable payment method. The platform tracks this state internally (job status `completed_payment_declined`, `order.payment_failed_at`, and admin notifications), so the partner API surfaces it here rather than introducing a separate endpoint:

| Field                 | Type    | Notes                                                                                                                                                         |
| --------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `payment_standing`    | string  | `"ok"` \| `"declined"` \| `"past_due"`. Reflects whether the org has an unresolved failed payment.                                                            |
| `orders_blocked`      | boolean | `true` when submitting a job (`POST /jobs/mailings/{id}/submit`) will be rejected for payment reasons. Driven by `payment_standing` and `payment_configured`. |
| `outstanding_balance` | object  | Amount that must be cleared before `orders_blocked` returns to `false`. `{ amount, currency }`.                                                               |

When `orders_blocked` is `true`, `POST /jobs/mailings/{id}/submit` returns `402 payment_required` (a `draft` can still be created and estimated). To recover, the partner directs the customer back through `POST /organizations/{id}/billing/setup` (re-auth flow) and settles the outstanding balance; the block lifts automatically once both are resolved.

---

### Terms of Service

> Customers must formally accept the CoS Terms of Service before any mailing is sent. **`[CHANGED 2026-07-14]` Acceptance is CoS-managed.** The flow mirrors the Stripe billing setup pattern: the partner requests a CoS-hosted acceptance URL via `POST .../terms/setup` and presents it to the customer (pop-up, modal, or redirect). The customer reviews the ToS and accepts **directly on the CoS-hosted page**, and CoS records the acceptance (version, timestamp, acceptor) as the system of record. The partner never attests on the customer's behalf — it simply checks `GET .../terms/status` to see whether the org is cleared. For partners not configured to require terms, `terms_required` is `false` and `terms_accepted` is always `true`.
---

#### `GET /organizations/{organization_id}/terms/status`

Check whether the organization has accepted the current Terms of Service. Mirrors the shape of `billing/status` so partners can gate onboarding on both with one pattern.

**Response `200 OK`:**

```
{
  "organization_id": "org_a1b2c3",
  "terms_required": true,
  "terms_accepted": false,
  "current_version": "2026-06-01",
  "accepted_version": null,
  "accepted_at": null,
  "accepted_by": null,
  "terms_url": "https://www.certificateofservice.com/legal/tos/2026-06-01"
}
```

| Field              | Type           | Notes                                                                                                 |
| ------------------ | -------------- | ----------------------------------------------------------------------------------------------------- |
| `terms_required`   | boolean        | `false` for partners not configured to require ToS — in which case `terms_accepted` is always `true`. |
| `terms_accepted`   | boolean        | `true` only when `accepted_version` matches `current_version`.                                        |
| `current_version`  | string         | Identifier of the ToS version currently in force.                                                     |
| `accepted_version` | string \| null | Version the org last accepted, if any.                                                                |
| `accepted_at`      | string \| null | ISO 8601 timestamp of acceptance, recorded by CoS when the customer accepts on the hosted page.       |
| `accepted_by`      | string \| null | Email of the person who accepted, captured on the CoS-hosted acceptance page. `[CHANGED 2026-07-14]`  |
| `terms_url`        | string         | Canonical CoS-hosted URL of the current ToS text (read-only reference — acceptance happens via the hosted flow below). |

A new acceptance is required whenever `current_version` advances beyond `accepted_version`.

---

#### `POST /organizations/{organization_id}/terms/setup`

**`[CHANGED 2026-07-14]`** *Replaces `POST .../terms/acceptance`.* Generates a CoS-hosted Terms of Service acceptance URL. Direct your customer to this URL (pop-up, modal, or redirect) — the page displays the current ToS and an accept action, and CoS records the acceptance directly when the customer confirms. The URL expires after 24 hours and always presents the `current_version` in force at the time it is opened.

Only applicable while `terms_required` is `true`; returns `403` otherwise. If the org has already accepted the current version, the endpoint still returns a URL (the page will show the terms as already accepted).

**Request body:**

```
{
  "success_url": "https://your-app.com/terms/success",
  "cancel_url": "https://your-app.com/terms/cancel"
}
```

| Field         | Type   | Required | Notes                                                        |
| ------------- | ------ | -------- | ------------------------------------------------------------ |
| `success_url` | string | ✓        | Redirects here after the customer accepts                    |
| `cancel_url`  | string | ✓        | Redirects here if the customer dismisses without accepting   |

**Response `200 OK`:**

```
{
  "organization_id": "org_a1b2c3",
  "acceptance_url": "https://www.certificateofservice.com/terms/accept/ts_live_...",
  "terms_version": "2026-06-01",
  "expires_at": "2026-07-15T18:00:00Z"
}
```

**Recording.** On acceptance, CoS stores `accepted_version`, `accepted_at`, and `accepted_by` (email captured on the hosted page) and `GET .../terms/status` flips to `terms_accepted: true`. The redirect to `success_url` is a UX convenience only — treat `GET .../terms/status` as the source of truth before submitting jobs, exactly as with `billing/status`. When a new ToS version is published, `terms_accepted` reverts to `false` and the customer must be sent through a new setup flow.

---

### Jobs

All mailing jobs live under `/jobs/mailings`. This path is structured to allow other job categories to be added in the future without breaking existing integrations.

---

**Job timing and cancellation windows.** Once a job is submitted, there is a window during which it can be edited or cancelled before it locks in for printing:

- **Normal service, submitted before noon PST** — the job locks in 15 minutes after submission. Cancellation is available up until that point.
- **Rush service, submitted after noon PST** — the job also locks in 15 minutes after submission regardless of time of day.
- **Deferred jobs** (normal service, submitted after noon PST) — the job does not enter the print queue until the end of the business day at 4:00 PM PST. Cancellation is available any time before 4:00 PM PST on the day of submission.

Cancellation is only possible while the job is in `in_queue` status. Once a job advances to `processing` or beyond, it cannot be cancelled.

---

**`[CHANGED 2026-07-14]` Saved-record references, overrides, and precedence.** Jobs can now select the contact, return address, and signature three ways. For each of the three record types, resolution follows this precedence:

1. **Inline override on the job** (`return_address`, `signature`, `notifications` objects) — highest precedence
2. **Referenced saved record** (`contact_id`, `return_address_id`, `signature_id`)
3. **Organization default** saved record

If a job supplies both an ID reference and an inline object for the same type, the **inline object wins** and the ID is ignored. If a job supplies neither and the organization has no default for that type, draft creation is rejected with `422 default_required`.

**`[CHANGED 2026-07-14]` Job snapshot semantics.** Any organization-level saved records referenced (or resolved via default) during draft creation are **materialized onto the draft at creation time**. Subsequent edits or deletions of organization-level records do **not** mutate existing drafts or submitted jobs. This preserves auditability and keeps deletes simple — a saved record can always be deleted without breaking in-flight work.

---

#### `POST /jobs/mailings`

Create a new mailing job as a **draft** and return an itemized cost estimate. Documents are uploaded inline as part of this request using `multipart/form-data`. The job is **not** released for printing until you confirm it via `POST /jobs/mailings/{job_id}/submit`. For PACER-sourced jobs the PACER lookup runs at draft creation, so the estimate reflects the actual recipient list. A draft that is never submitted expires after 48 hours.

**Request:** `multipart/form-data`

The request body is split into two parts: a JSON metadata field named `job` containing all job configuration, and one or more binary file fields containing the PDF documents.

**File fields:**

| Field               | Count | Description                                              |
| ------------------- | ----- | -------------------------------------------------------- |
| `files`             | 1–15  | Standard notice documents (PDF). Max 20 MB each.         |
| `ballotFiles`       | 0–1   | Ballot document (PDF), if applicable. Max 20 MB.         |
| `proofOfClaimFiles` | 0–1   | Proof of claim document (PDF), if applicable. Max 20 MB. |

**Constraints:** PDF only. Max 20 MB per file, max 100 MB total across all files in a single job. At least one file in `files` is required.

**`job` metadata field (JSON):**

```
{
  "organization_id": "org_a1b2c3",
  "type": "bankruptcy_notice",
  "documents": [
    {
      "docket_description": "Motion to Sell Property",
      "docket_reference_number": "1"
    },
    {
      "docket_description": "Notice of Hearing",
      "docket_reference_number": "2"
    }
  ],
  "recipients": {
    "source": "pacer"
  },
  "contact_id": "con_123",
  "return_address_id": "ra_123",
  "signature_id": "sig_123",
  "notifications": {
    "primary_email": "trustee@example.com",
    "cc_emails": ["ops@example.com", "txi+123@veritatfs.com"]
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
    "court_location": { "state": "CA", "district": "CACB", "division": "2" },
    "debtor_name": "Acme Debtor LLC",
    "chapter": "11",
    "judge_name": "Hon. Jane Smith"
  }
}
```

Each object in the `documents` array corresponds positionally to a file in the `files` field — `documents[0]` is the metadata for `files[0]`, `documents[1]` for `files[1]`, and so on. The same positional pairing applies to `ballots` and `proofOfClaims` with their respective file fields.

**`job` field reference:**

| Field                                 | Type   | Required                   | Notes                                                                                                                                                                            |
| ------------------------------------- | ------ | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `organization_id`                     | string | ✓                          | Owning org                                                                                                                                                                       |
| `type`                                | string | ✓                          | See job types below                                                                                                                                                              |
| `documents`                           | array  | ✓                          | 1–15 document metadata objects. Array order is respected — documents print in the order listed. Each object maps positionally to a file in the `files` field.                    |
| `documents[].docket_description`      | string |                            | Appears on the certificate of service for this document. Max 85 characters.                                                                                                      |
| `documents[].docket_reference_number` | string |                            | Optional reference number for this document. Max 4 characters.                                                                                                                   |
| `ballots`                             | array  |                            | Up to 1 ballot document metadata object. Maps positionally to `ballotFiles`.                                                                                                     |
| `proofOfClaims`                       | array  |                            | Up to 1 proof of claim metadata object. Maps positionally to `proofOfClaimFiles`.                                                                                                |
| `recipients.source`                   | string | ✓                          | `"pacer"` or `"user_supplied"`                                                                                                                                                   |
| `recipients.addresses`                | array  | if source=user\_supplied   | See recipient object below                                                                                                                                                       |
| `contact_id`                          | string |                            | `[CHANGED 2026-07-14]` Reference a saved org contact for this job's notifications. `404 contact_not_found` if unknown.                                                           |
| `return_address_id`                   | string |                            | `[CHANGED 2026-07-14]` Reference a saved org return address. `404 return_address_not_found` if unknown. Ignored when an inline `return_address` is supplied.                     |
| `signature_id`                        | string |                            | `[CHANGED 2026-07-14]` Reference a saved org signature. `404 signature_not_found` if unknown. Ignored when an inline `signature` is supplied.                                    |
| `notifications`                       | object |                            | `[CHANGED 2026-07-14]` See job notifications below                                                                                                                              |
| `order_preferences.sides`             | string |                            | `"double_sided"` (default) or `"one_sided"`                                                                                                                                      |
| `order_preferences.format`            | string |                            | `"2up"` (default) or `"1up"`. `4up` is not yet supported.                                                                                                                        |
| `order_preferences.service`           | string |                            | `"normal"` (default) or `"rush"`                                                                                                                                                 |
| `order_preferences.mail_class`        | string |                            | `"first_class"` (default), `"certified"`, or `"priority_express"`. Overrides org default. `certified` and `priority_express` are only settable at the org settings or job level. |
| `return_address`                      | object |                            | One-off inline override — highest precedence. Same shape as a saved return address (minus `return_address_id` / `name` / `is_default`).                                          |
| `signature`                           | object |                            | One-off inline override — highest precedence. See signature object below.                                                                                                        |
| `external_reference`                  | string |                            | Your reference ID; stored for your records                                                                                                                                       |
| `bankruptcy_options`                  | object | if type=bankruptcy\_notice | See bankruptcy options object below                                                                                                                                              |

**Job types (`type`):**

| Value               | Description           | v1 Scope        |
| ------------------- | --------------------- | --------------- |
| `bankruptcy_notice` | Standard BN notice    | ✓ Tier 1        |
| `legal`             | General legal mailing | Tier 2 (future) |
| `direct_mailing`    | Direct mail campaign  | Tier 3 (future) |

Use `"pacer"` to pull the recipient list from PACER using the submitted court and case number. Use `"user_supplied"` to supply addresses directly.

**`[CHANGED 2026-07-14]`** If the PACER/case lookup fails, draft creation returns a `422` with one of the specific case-resolution codes: `pacer_unavailable`, `case_not_found`, `case_ambiguous`, or `debtor_name_mismatch` (see [Errors](#errors)).

**Recipient object (when `source = "user_supplied"`):**

```
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

**Job notifications (`notifications`):** `[CHANGED 2026-07-14]` *New object.*

```
"notifications": {
  "primary_email": "trustee@example.com",
  "cc_emails": ["ops@example.com", "txi+123@veritatfs.com"]
}
```

| Field           | Type   | Required | Notes                                                                    |
| --------------- | ------ | -------- | ------------------------------------------------------------------------ |
| `primary_email` | string |          | Receives **all** job lifecycle notifications (submission confirmation, completion, certificate delivery, cancellation/failure) plus billing issues. |
| `cc_emails`     | array  |          | Up to **10** additional addresses. Receive **completion/certificate and failure** notifications only — not billing. Duplicates are deduped automatically. |

**Fallback chain when `primary_email` is omitted:** the email of the job's referenced `contact_id` → the org's default contact email. If no address can be resolved, draft creation is rejected with `422 missing_contact_email`. An invalid email anywhere in the block rejects the request with `422 invalid_notification_email`; more than 10 CC addresses returns `422 too_many_cc_emails`.

> **Phasing note:** the `notifications` contract is defined here so partners can build against it now; CC delivery (`cc_emails`) ships in the phase following MVP.

**Bankruptcy options object (`bankruptcy_options`):**

Required when `type` is `"bankruptcy_notice"`.

**`[CHANGED 2026-07-14]`** `debtor_name`, `chapter`, and `judge_name` are now part of the request contract. Previously the draft stated that debtor name and chapter were pulled from PACER and did not need to be supplied; partners can now send them. `debtor_name` is treated as **advisory input validated against PACER** — supplying it lets CoS uniquely identify the correct case without prompting the user, and a material mismatch is rejected with `422 debtor_name_mismatch`. `chapter` and `judge_name` are **recorded and placed on the certificate**; CoS stores them as supplied and does not independently verify them in v1.

| Field                     | Type   | Required | Notes                                                          |
| ------------------------- | ------ | -------- | -------------------------------------------------------------- |
| `case_numbers`            | array  | ✓        | One or more case number strings                                |
| `court_location`          | object | ✓        | `state`, `district`, optional `division`. The division code is critical for districts with multiple divisions. |
| `debtor_name`             | string |          | `[CHANGED 2026-07-14]` Validated against the PACER-resolved case. Strongly recommended for PACER-sourced jobs — disambiguates when multiple cases match. |
| `chapter`                 | string |          | `[CHANGED 2026-07-14]` e.g. `"7"`, `"11"`, `"13"`. Stored and shown on the certificate.  |
| `judge_name`              | string |          | `[CHANGED 2026-07-14]` Stored and shown on the certificate.    |
| `adversary_proceeding`    | object |          | All-or-nothing: omit entirely or supply all fields (see below) |
| `return_envelope`         | object |          | See return envelope object below                               |
| `certificate_preferences` | object |          | See certificate preferences object below                       |

**Debtor-name comparison rules.** `[CHANGED 2026-07-14]` CoS normalizes case, whitespace, and punctuation before comparing the supplied `debtor_name` against the PACER-resolved debtor. Materially different names are rejected with `422 debtor_name_mismatch`, and the error payload includes both the provided and resolved names so the partner can surface an actionable message (see [Errors](#errors)).

**Adversary proceeding object (`bankruptcy_options.adversary_proceeding`):**

All fields are required if the object is present. Omit the entire object if there is no adversary proceeding.

| Field                 | Type   | Required | Notes             |
| --------------------- | ------ | -------- | ----------------- |
| `adversary_number`    | string | ✓        |                   |
| `adversary_plaintiff` | string | ✓        | Max 40 characters |
| `adversary_defendant` | string | ✓        | Max 40 characters |

**Return envelope object (`bankruptcy_options.return_envelope`):**

| Field                 | Type    | Required | Notes              |
| --------------------- | ------- | -------- | ------------------ |
| `name`                | string  | ✓        | Max 144 characters |
| `office`              | string  |          | Max 144 characters |
| `address`             | string  | ✓        | Max 144 characters |
| `city`                | string  | ✓        | Max 144 characters |
| `state`               | string  | ✓        | US state code      |
| `zip_code`            | string  | ✓        |                    |
| `is_postage_included` | boolean | ✓        |                    |

**Certificate preferences object (`bankruptcy_options.certificate_preferences`):**

| Field                                  | Type    | Notes                                                        |
| -------------------------------------- | ------- | ------------------------------------------------------------ |
| `should_attach_docs`                   | boolean | Whether to attach submitted documents to the certificate PDF |
| `custom_file_name`                     | string  | Override the default certificate filename                    |
| `should_include_nef`                   | boolean | Whether to include the NEF on the certificate                |
| `hearing_information.hearing_date`     | string  |                                                              |
| `hearing_information.hearing_time`     | string  |                                                              |
| `hearing_information.hearing_location` | string  |                                                              |
| `hearing_information.response_date`    | string  |                                                              |

**Signature object (`signature`):**

One-off inline override for this job — takes precedence over `signature_id` and the org default. `full_name` and `client_role` are required if the object is present (`bar_number` is optional everywhere — trustees who are not attorneys will not have one). Address fields are optional — when omitted, they inherit from the return address resolved for this job.

| Field           | Type   | Required | Notes                                                |
| --------------- | ------ | -------- | ---------------------------------------------------- |
| `full_name`     | string | ✓        | Name of the signatory                                |
| `bar_number`    | string |          | Optional `[CHANGED 2026-07-14]`                      |
| `client_role`   | string | ✓        | e.g. `"Chapter 13 Trustee"`, `"Attorney for Debtor"` |
| `firm_name`     | string |          |                                                      |
| `address_line1` | string |          |                                                      |
| `address_line2` | string |          |                                                      |
| `city`          | string |          |                                                      |
| `state`         | string |          | US state code                                        |
| `zip_code`      | string |          |                                                      |
| `phone`         | string |          |                                                      |
| `email`         | string |          |                                                      |
| `fax`           | string |          |                                                      |

**Response `201 Created`:** The job is created in `draft` status with an itemized `cost_estimate`. Review it, then confirm with `POST /jobs/mailings/{job_id}/submit`. `[CHANGED 2026-07-14]` The response echoes `debtor_name`, `chapter`, and `judge_name` as stored/resolved by CoS so partners can reconcile them.

```
{
  "job_id": "job_z9y8x7",
  "organization_id": "org_a1b2c3",
  "status": "draft",
  "type": "bankruptcy_notice",
  "case_number": "2:24-bk-10001",
  "debtor_name": "Acme Debtor LLC",
  "chapter": "11",
  "judge_name": "Hon. Jane Smith",
  "external_reference": "case-10001-notice-q1",
  "recipient_count": 47,
  "cost_estimate": {
    "document_processing": 0.0,
    "usps_postage": 32.17,
    "per_notice_fee": 8.46,
    "subtotal": 40.63,
    "sales_tax": 0.0,
    "total": 40.63,
    "currency": "USD"
  },
  "expires_at": "2026-05-28T18:05:00Z",
  "created_at": "2026-05-26T18:05:00Z"
}
```

---

#### `POST /jobs/mailings/{job_id}/submit`

Confirm a `draft` job and release it for printing. The job transitions `draft` → `submitted` and is mailed exactly as estimated — no re-pricing and no second PACER lookup. The onboarding gate is enforced here (not at draft creation): returns `402 payment_required` or `403 terms_not_accepted` if the org isn't cleared, `409 conflict` if the job is not in `draft` status, or `422 validation_error` if the draft has expired.

**Response `200 OK`:**

```
{
  "job_id": "job_z9y8x7",
  "status": "submitted",
  "created_at": "2026-05-26T18:05:00Z"
}
```

---

#### `GET /jobs/mailings/{job_id}`

Get job status and details. **Poll this endpoint to track progress.**

**Response `200 OK`:** `[CHANGED 2026-07-14]` now includes `debtor_name`, `chapter`, and `judge_name` as stored by CoS.

```
{
  "job_id": "job_z9y8x7",
  "organization_id": "org_a1b2c3",
  "status": "completed",
  "type": "bankruptcy_notice",
  "case_number": "2:24-bk-10001",
  "debtor_name": "Acme Debtor LLC",
  "chapter": "11",
  "judge_name": "Hon. Jane Smith",
  "external_reference": "case-10001-notice-q1",
  "recipient_count": 47,
  "certificate_ready": true,
  "cost": {
    "document_processing": 0.0,
    "usps_postage": 32.17,
    "per_notice_fee": 8.46,
    "subtotal": 40.63,
    "sales_tax": 0.0,
    "total": 40.63,
    "currency": "USD"
  },
  "created_at": "2026-05-26T18:05:00Z",
  "mailed_at": "2026-05-27T14:30:00Z"
}
```

For PACER-sourced jobs the PACER lookup runs at **draft creation**, so `recipient_count` and the cost are known from the `draft` onward (returned as `cost_estimate`). Once the job reaches `completed`, `cost` reflects final actuals.

**Job status values:**

| Status       | Description                                                                          |
| ------------ | ------------------------------------------------------------------------------------ |
| `draft`      | Created with a cost estimate; not yet submitted. Expires after 48h if not confirmed. |
| `submitted`  | Job confirmed and received by CoS                                                    |
| `in_queue`   | Queued for printing                                                                  |
| `processing` | Being prepared for print                                                             |
| `printing`   | Being printed                                                                        |
| `completed`  | Envelopes mailed; certificate of service available                                   |
| `cancelled`  | Cancelled before printing                                                            |
| `on_hold`    | On hold — CoS will reach out if action is needed                                     |

**Suggested polling interval:** 30 seconds while status is `submitted`, `in_queue`, or `processing`. Once `completed`, stop polling.

---

#### `GET /jobs/mailings`

List mailing jobs for an organization.

**Query parameters:**

| Param                | Type              | Description                 |
| -------------------- | ----------------- | --------------------------- |
| `organization_id`    | string            | Required                    |
| `status`             | string            | Filter by status            |
| `case_number`        | string            | Filter by case number       |
| `external_reference` | string            | Filter by your reference ID |
| `created_after`      | ISO 8601 datetime |                             |
| `created_before`     | ISO 8601 datetime |                             |
| `page`               | integer           | Default 1                   |
| `per_page`           | integer           | Default 25, max 100         |

**Response `200 OK`:**

```
{
  "mailings": [
    /* array of job objects (same shape as GET /jobs/mailings/{id}) —
       includes debtor_name, chapter, judge_name [CHANGED 2026-07-14] */
  ],
  "pagination": {
    "page": 1,
    "per_page": 25,
    "total": 142
  }
}
```

---

#### `POST /jobs/mailings/{job_id}/cancel`

Cancel a job. Only valid while the job is in `in_queue` status.

**Response `200 OK`:**

```
{
  "job_id": "job_z9y8x7",
  "status": "cancelled"
}
```

---

### Certificates

The certificate of service PDF is generated when the job completes. It is stored for **90 days** from the mail date.

---

#### `GET /jobs/mailings/{job_id}/certificate`

Download the certificate of service. Returns a signed URL that expires in 15 minutes and can be re-fetched at any time within the 90-day retention window.

**Response `200 OK`:**

```
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

```
{
  "job_id": "job_z9y8x7",
  "case_number": "2:24-bk-10001",
  "recipient_count": 47,
  "document_processing": 0.0,
  "usps_postage": 32.17,
  "per_notice_fee": 8.46,
  "per_notice_rate": 0.18,
  "subtotal": 40.63,
  "sales_tax": 0.0,
  "total": 40.63,
  "currency": "USD"
}
```

---

## Errors

All errors return a consistent envelope:

```
{
  "error": {
    "code": "validation_error",
    "message": "Field 'case_numbers' is required for type 'bankruptcy_notice'.",
    "job_id": null
  }
}
```

**Error codes:**

| HTTP | Code                 | Meaning                                                                                                                                                                                       |
| ---- | -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 400  | `invalid_request`    | Missing or malformed field                                                                                                                                                                    |
| 401  | `unauthorized`       | Invalid or missing API key                                                                                                                                                                    |
| 402  | `payment_required`   | No valid payment method on file, or an unresolved declined payment is blocking new orders (Stripe-billed orgs only). Check `payment_standing` / `orders_blocked` on `GET .../billing/status`. |
| 403  | `terms_not_accepted` | Org has not accepted the current Terms of Service; direct the customer through the hosted flow via `POST .../terms/setup` (applies only where `terms_required` is `true`).                                   |
| 403  | `forbidden`          | Credential lacks scope for this action                                                                                                                                                        |
| 404  | `not_found`          | Resource doesn't exist                                                                                                                                                                        |
| 404  | `contact_not_found`  | `[CHANGED 2026-07-14]` `contact_id` does not exist on this organization                                                                                                                       |
| 404  | `return_address_not_found` | `[CHANGED 2026-07-14]` `return_address_id` does not exist on this organization                                                                                                          |
| 404  | `signature_not_found` | `[CHANGED 2026-07-14]` `signature_id` does not exist on this organization                                                                                                                    |
| 409  | `conflict`           | Duplicate `external_reference` (scoped per org), non-unique phone number, or duplicate contact email / record name within an org                                                              |
| 422  | `validation_error`   | Input passes format checks but fails business logic                                                                                                                                           |
| 422  | `default_required`   | `[CHANGED 2026-07-14]` Job supplied neither an inline override nor a saved-record reference, and the org has no default for that record type                                                  |
| 422  | `multiple_defaults_not_allowed` | `[CHANGED 2026-07-14]` Request would result in more than one default record of a type                                                                                              |
| 422  | `invalid_notification_email` | `[CHANGED 2026-07-14]` A `notifications` email failed format validation                                                                                                               |
| 422  | `too_many_cc_emails` | `[CHANGED 2026-07-14]` `notifications.cc_emails` exceeds the maximum of 10                                                                                                                    |
| 422  | `missing_contact_email` | `[CHANGED 2026-07-14]` No notification email could be resolved (no `primary_email`, no contact email, no org default contact)                                                              |
| 422  | `pacer_unavailable`  | `[CHANGED 2026-07-14]` PACER or the related lookup service is unavailable — job not created; retry later                                                                                      |
| 422  | `case_not_found`     | `[CHANGED 2026-07-14]` No case found for the supplied case number / court location                                                                                                            |
| 422  | `case_ambiguous`     | `[CHANGED 2026-07-14]` Multiple possible cases matched — supply `court_location.division` and/or `debtor_name` to disambiguate                                                                |
| 422  | `debtor_name_mismatch` | `[CHANGED 2026-07-14]` Supplied `debtor_name` did not match the PACER-resolved case (see example below)                                                                                     |
| 429  | `rate_limited`       | Too many requests — see `Retry-After` header                                                                                                                                                  |
| 500  | `internal_error`     | CoS-side error                                                                                                                                                                                |

**Example — `debtor_name_mismatch`:** `[CHANGED 2026-07-14]`

```
{
  "error": {
    "code": "debtor_name_mismatch",
    "message": "The debtor name provided does not match the case number resolved through PACER.",
    "job_id": null,
    "details": {
      "provided_debtor_name": "Acme Debtor LLC",
      "resolved_debtor_name": "Acme Debtor Liquidation LLC",
      "case_number": "2:24-bk-10001"
    }
  }
}
```

**Example — `case_ambiguous`:** `[CHANGED 2026-07-14]`

```
{
  "error": {
    "code": "case_ambiguous",
    "message": "Multiple cases matched '24-10001' in district CACB. Supply court_location.division and/or debtor_name to disambiguate.",
    "job_id": null,
    "details": {
      "case_number": "24-10001",
      "candidates": [
        { "case_number": "2:24-bk-10001", "debtor_name": "Acme Debtor LLC" },
        { "case_number": "6:24-bk-10001", "debtor_name": "Bravo Holdings Inc" }
      ]
    }
  }
}
```

**Example — `default_required`:** `[CHANGED 2026-07-14]`

```
{
  "error": {
    "code": "default_required",
    "message": "No signature was supplied and the organization has no default signature. Reference a saved signature_id, supply an inline signature, or set a default.",
    "job_id": null
  }
}
```

---

## Changelog

### 2026-07-14

> Incorporates the amendments agreed in the 2026-07-14 CoS ↔ Verita working session.

**Organizations — reusable saved-record collections** *(new sections)*

- Added **Organization Contacts**: organizations can now store multiple contacts (different trustees/users within a trustee group may need different phone/email values), with at most one default. Nested CRUD endpoints at `/organizations/{id}/contacts`.
- Added **Organization Return Addresses**: multiple named return addresses per org with a stable `return_address_id`, a required `name` label, and at most one default. Nested CRUD endpoints at `/organizations/{id}/return-addresses`.
- Added **Organization Signatures**: multiple named certificate signatures per org (roles differ by case — Chapter 7 trustee, Chapter 11 trustee, attorney, trustee in possession, etc.), with at most one default. Nested CRUD endpoints at `/organizations/{id}/signatures`.
- Signature field requirements adjusted: `bar_number` is now optional everywhere (non-attorney trustees have none); `phone` is required on saved signatures. Address fields remain optional on both saved signatures and inline overrides — when omitted, the signature block inherits the job's resolved return address.
- Documented **default lifecycle rules** (zero-or-one default per type; setting a new default clears the previous one; jobs with no resolvable record are rejected with `default_required`) and **deletion rules** (defaults deletable; snapshotting makes deletes safe for in-flight jobs; last contact not deletable).
- `contact_email` and `company_phone_number` on the organization are **removed**; `POST /organizations` now takes an initial `contact` object that becomes the default contact. The default contact's phone must be unique across organizations (account matching); contacts within one organization may share a phone number.

**Organization Settings — narrowed scope**

- `settings` now carries only true settings: `default_court`, `order_preferences`, and read-only default pointers (`default_contact_id`, `default_return_address_id`, `default_signature_id`).
- The singular `return_address` and `signature` objects in settings are **removed**. `PATCH .../settings` accepts only `default_court` and `order_preferences`; add/update/delete of individual records goes through the nested resource endpoints (`POST` / `PATCH` / `DELETE`).

**Jobs — saved-record references, overrides, and precedence**

- Added `contact_id`, `return_address_id`, and `signature_id` to the job payload for referencing saved org records.
- Inline `return_address` and `signature` remain supported as one-off overrides.
- Documented explicit precedence: **inline override → referenced saved record → organization default**; jobs resolving to none are rejected with `default_required`.
- Documented **snapshot semantics**: referenced/default records are materialized onto the draft at creation time; later edits or deletions of org-level records never mutate existing drafts or submitted jobs.

**Jobs — notifications block** *(new)*

- Added `notifications.primary_email` (all job lifecycle notifications + certificate + billing) and `notifications.cc_emails` (up to 10; completion/certificate and failure notifications only).
- Documented the fallback chain when `primary_email` is omitted: referenced contact's email → org default contact email; otherwise `missing_contact_email`.
- CC delivery is defined in the contract now and ships in the phase following MVP.

**Bankruptcy metadata**

- Added `debtor_name`, `chapter`, and `judge_name` to `bankruptcy_options`. `debtor_name` is validated against the PACER-resolved case (normalized for case, whitespace, and punctuation) and reduces case ambiguity so users aren't prompted; `chapter` and `judge_name` are stored and placed on the certificate.
- `debtor_name`, `chapter`, and `judge_name` are echoed back on `POST /jobs/mailings`, `GET /jobs/mailings/{id}`, and `GET /jobs/mailings` responses so partners can reconcile what CoS stored/used.

**Errors**

- Replaced the blanket `pacer_error` with `pacer_unavailable`, `case_not_found`, `case_ambiguous`, and `debtor_name_mismatch`.
- Added saved-record errors (`contact_not_found`, `return_address_not_found`, `signature_not_found`), default-management errors (`default_required`, `multiple_defaults_not_allowed`), and notification errors (`invalid_notification_email`, `too_many_cc_emails`, `missing_contact_email`).
- Added worked examples for `debtor_name_mismatch`, `case_ambiguous`, and `default_required`.

**Terms of Service — acceptance is now CoS-managed**

- Replaced `POST .../terms/acceptance` (partner-recorded acceptance) with `POST .../terms/setup`, which returns a CoS-hosted acceptance URL (mirroring the Stripe billing setup pattern). The partner displays it as a pop-up/modal/redirect; the customer accepts directly on the CoS page and CoS records `accepted_version`, `accepted_at`, and `accepted_by` as the system of record.
- Added `accepted_by` to `GET .../terms/status`. Partners treat `terms/status` as the source of truth before submitting jobs; a new ToS version reverts `terms_accepted` to `false` and requires a new setup flow.

---

### 2026-07-08

**Jobs — `POST /jobs/mailings` (document upload model)**

- Changed request format from `application/json` to `multipart/form-data`. Documents are now uploaded inline as part of the job creation request rather than in a separate pre-upload step.
- The `documents` field in the `job` metadata no longer accepts an array of `document_id` strings. It now accepts an array of metadata objects (one per file), each containing optional `docket_description` and `docket_reference_number`. Each metadata object corresponds positionally to a file in the `files` multipart field.
- Added `ballotFiles` and `proofOfClaimFiles` as separate multipart file fields for ballot and proof of claim documents. Their metadata is provided via `ballots` and `proofOfClaims` arrays in the `job` field respectively.
- File constraints remain unchanged: PDF only, max 20 MB per file, max 100 MB total per job.

**Documents section — removed**

- `POST /documents` (standalone document pre-upload) has been removed from v1. Documents are submitted inline with `POST /jobs/mailings`.
- `GET /documents/{document_id}` has been removed from v1.

**Organizations — `POST /organizations`**

- Added account setup note: CoS sends a welcome email to `contact_email` on provisioning with a one-time password setup link. Email is sent from a CoS email address.
- Added note clarifying that each customer should be provisioned as a single organization.

**Jobs — cancellation and timing**

- Added a **Job timing and cancellation windows** section describing when jobs lock in for printing and when cancellation is permitted:
  * Normal service pre-noon and rush service jobs lock in 15 minutes after submission.
  * Deferred jobs (normal service, submitted post-noon) lock in at 4:00 PM PST on the day of submission.
  * Cancellation is only available while the job is in `in_queue` status.

**Billing**

- Added an introductory note to the Billing section clarifying that payment is collected through an embedded Stripe flow within the partner platform, that CoS stores only the Stripe token (not raw payment details), and that customers update payment details by initiating a new Stripe setup flow via `POST /organizations/{id}/billing/setup`.

---

### 2026-06-25

> **Revision note (2026-06-25):** This copy incorporates the partner asks raised since the June 5 draft (partner discovery conversations in June). Main additions: onboarding gate + terms-of-service acceptance; declined-payment semantics on billing status; a `draft` → estimate → submit job flow (pre-submission invoice estimate); organization tenancy + lookup by `external_id`; a partner-configuration note; and `4up` flagged as not yet supported by the backend.

**Organizations**

- All organization endpoints are now scoped to the authenticating partner's API key. A partner can only access organizations it created; requesting an `organization_id` belonging to another partner returns `404 not_found`.
- Added `GET /organizations` — list organizations belonging to the authenticating partner, with optional `external_id` filter for cross-reference lookup.
- Added `external_id` field to `POST /organizations` and `PATCH /organizations/{id}` — partners can store their own internal ID for each org.

**Partner configuration**

- Documented partner-level configuration settings (billing mode, terms required) that are set by CoS during onboarding. These are not configurable via the API.

**Onboarding gate**

- Organizations configured for Stripe billing must satisfy two conditions before jobs can be submitted: (1) a valid payment method on file and (2) acceptance of the current CoS Terms of Service. Each condition can be checked independently via the billing and terms status endpoints.

**Billing**

- Added `payment_standing` field to `GET .../billing/status`: `"ok"` | `"declined"` | `"past_due"`.
- Added `orders_blocked` boolean to `GET .../billing/status` — `true` when an unresolved declined payment is blocking new job submissions.
- Added `outstanding_balance` field to `GET .../billing/status`.
- When `orders_blocked` is `true`, `POST /jobs/mailings/{id}/submit` returns `402 payment_required`. Draft creation and estimation are still permitted.

**Terms of Service** *(new section)*

- Added `GET /organizations/{id}/terms/status` — check whether the org has accepted the current Terms of Service.
- Added `POST /organizations/{id}/terms/acceptance` — record acceptance after the partner's customer completes the acceptance flow in the partner UI.

**Jobs**

- `POST /jobs/mailings` now creates a job in `draft` status and returns an itemized `cost_estimate`. The job is not released for printing until confirmed via `POST /jobs/mailings/{id}/submit`.
- For PACER-sourced jobs, the PACER lookup now runs at draft creation so the cost estimate reflects the actual recipient list.
- A draft that is never submitted expires after 48 hours.
- Added `POST /jobs/mailings/{id}/submit` — confirms a draft and transitions it to `submitted`. The onboarding gate is enforced at this step.
- Added `draft` to job status values.
- Added `cost_estimate` to the `POST /jobs/mailings` response (pre-submission) and `cost` to the `GET /jobs/mailings/{id}` response (post-completion).

**Order preferences**

- `4up` format is not yet supported by the backend print pipeline (only `1up` and `2up` are implemented).

### 2026-06-05

- Initial working draft published.
