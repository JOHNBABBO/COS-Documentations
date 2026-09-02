# API — Available Endpoints

**Last updated:** September 1, 2026

This document lists the endpoints currently implemented and available for integration testing. The API specification remains the source of truth for request and response shapes, field definitions, and error codes.

---

## Getting connected

**Base URL (staging):** `https://backend.staging.thenoticingcenter.com/v1/cos`

Note that this differs from the production base URL documented in the specification. All testing should target the staging host above.

**Authentication.** Every request requires an `Authorization: Bearer <api-key>` header. See the specification for header format and error responses.

**Getting your key.** API keys are issued by CoS. We will share API keys with partners directly. Keys are not created or retrieved through the API, and a key is shown only once at the time it is issued, so store it securely on receipt.

**Key rotation.** Rotation is handled by CoS on request. Contact us and we will issue a new key; your existing key continues to authenticate for a transition window, so there is no interruption while you cut over. Please tell us the window you need when you make the request. There is no partner-facing endpoint for this.

**One caution:** keys carry the same `cos_live_` prefix in every environment, so a staging key and a production key look alike. Keep them clearly separated on your side.

---

## Available now

**Organizations**
- `POST /organizations`
- `GET /organizations/{id}`
- `PATCH /organizations/{id}`

---

## Available after September 9

**Organizations**
- `PATCH /organizations/{id}/settings`

**Billing**
- `POST /organizations/{id}/billing/setup`
- `GET /organizations/{id}/billing/status`

**Terms of service**
- `GET /organizations/{id}/terms/status`

**Jobs**
- `POST /jobs/mailings`
- `POST /jobs/mailings/{id}/submit`

Organizations whose configuration does not require terms acceptance will always report as accepted, and the onboarding gate will not block on terms.

---

## Not yet available

Please do not build test coverage against these yet. We will update this document as they come online.

- `GET /organizations/{id}/settings`
- `GET /organizations/{id}/contacts`, `POST`, and the item-level `GET` / `PATCH` / `DELETE`
- `GET /organizations/{id}/return-addresses`, `POST`, and the item-level `GET` / `PATCH` / `DELETE`
- `GET /organizations/{id}/signatures`, `POST`, and the item-level `GET` / `PATCH` / `DELETE`
- `POST /organizations/{id}/terms/acceptance`
- `GET /jobs/mailings`
- `GET /jobs/mailings/{id}`
- `POST /jobs/mailings/{id}/cancel`
- `GET /jobs/mailings/{id}/certificate`
- `GET /jobs/mailings/{id}/cost`

---

## Notes for testing

**Draft creation is not yet fully validated.** `POST /jobs/mailings` currently handles request parsing. File validation, recipient validation, and bankruptcy and order preference validation are still in progress, so a draft may be accepted from input that will be rejected once validation is complete. Test cases asserting on rejection behavior at draft creation should wait.

**Settings cannot be read back.** `PATCH /organizations/{id}/settings` is available without its matching `GET`. There is no way to confirm a settings write through the API for now.

**Submitted jobs cannot be polled.** Until job detail is available, please let us know about any job you submit in staging and we will confirm its status directly.

**IP allowlists and per-credential scopes.** These appear in the current specification but are not implemented and are not planned. Please disregard those sections; a corrected specification will follow.

---
