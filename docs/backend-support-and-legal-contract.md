# Support & Legal — Backend Contract (mobile-side spec)

This is the contract the mobile apps now consume. The mobile side is built and ready; please confirm shape/codes before we cut a release. **No work has shipped to production — until these endpoints exist, the mobile UI will surface "Couldn't load…" states and ticket creation will fail.**

Owner (mobile): Ayiks
Mobile branch: `staging`
Affected packages: `packages/shared_models`, `packages/api_client`, `packages/shared_ui`, `apps/client`, `apps/provider`

## Conventions

- Base URL prefix: `/v1`
- Auth: existing JWT — same header / refresh flow as the rest of the API
- Envelope: existing `{ success: true, data: … }` / `{ success: false, error: { code, message, details } }` shape
- Timestamps: ISO 8601 UTC strings
- Cursor pagination: forward-only; response `{ items: [...], nextCursor: string | null }`

## 1. Support tickets

### `POST /v1/support/tickets`

Create a ticket.

```json
{
  "category": "account | payments | rides | jobs | payouts | verification | safety | bug | other",
  "subject": "string, 1–120",
  "description": "string, 1–4000",
  "priority": "low | normal | high | urgent",        // optional, advisory
  "attachments": [                                    // optional
    { "url": "https://…", "mime": "image/jpeg", "sizeBytes": 12345, "filename": "…" }
  ],
  "referenceType": "ride | job | bid | payout | payment",  // optional
  "referenceId": "string"                             // optional
}
```

Response: `SupportTicket` (see schema below).

Errors:
- `422 SUBJECT_TOO_LONG | DESCRIPTION_TOO_LONG | MESSAGE_EMPTY`
- `413 ATTACHMENT_TOO_LARGE | TOO_MANY_ATTACHMENTS`
- `429 SUPPORT_RATE_LIMITED`

Server-side rules:
- Safety / fraud reports SHOULD auto-bump priority to `high` regardless of caller value.
- `referenceType`/`referenceId` are advisory — used by the agent console to deep-link into the underlying record.
- If `attachments[].url` doesn't match a previously confirmed `support_attachment` upload (see §4), return 422.

### `GET /v1/support/tickets`

List the caller's own tickets.

Query: `cursor`, `limit` (default 20, cap 50), `status` (filter, optional)

Response:
```json
{ "items": [SupportTicket, …], "nextCursor": "…" | null }
```

### `GET /v1/support/tickets/:id`

Single-ticket header for the detail screen. Returns `SupportTicket`.

Errors:
- `404 TICKET_NOT_FOUND`
- `403 NOT_TICKET_OWNER`

### `GET /v1/support/tickets/:id/messages`

Chat history, **ascending** by `createdAt`. Forward-only cursor pagination — older messages page in as the user scrolls back.

Query: `cursor`, `limit` (default 50, cap 100)

Response:
```json
{ "items": [TicketMessage, …], "nextCursor": "…" | null }
```

### `POST /v1/support/tickets/:id/messages`

Reply on the caller's own ticket.

```json
{
  "body": "string, 1–4000",
  "attachments": [{ "url": "…", "mime": "…", "sizeBytes": 0, "filename": "…" }]
}
```

Response: persisted `TicketMessage`.

Errors:
- `410 TICKET_CLOSED` (status `closed`; reopen first)
- `422 MESSAGE_EMPTY | MESSAGE_TOO_LONG`
- `403 NOT_TICKET_OWNER`

Server-side rule: a successful user reply on a `waiting_user` ticket SHOULD flip it back to `open`.

### `PATCH /v1/support/tickets/:id/status`

User-initiated state change. Mobile only ever sends `resolved` (close my ticket) or `reopened` (re-open within 7 days of resolution).

```json
{ "status": "resolved | reopened" }
```

Response: updated `SupportTicket`.

Errors:
- `409` if the requested transition is illegal (e.g. trying to reopen a `closed` ticket older than 7 days)

### `POST /v1/support/tickets/:id/messages/read`

Best-effort, idempotent. Marks every agent/system message ≤ `upToMessageId` as read by the caller.

```json
{ "upToMessageId": "string" }   // optional; if omitted, mark everything read
```

Response: `{ success: true }` (empty data is fine).

## 2. Help articles (CMS)

All endpoints accept `audience=client|provider` and filter accordingly. Search is server-side; the mobile debounces 300 ms and gates to `q.length >= 2`.

### `GET /v1/support/help/categories?audience=…`

```json
[
  { "slug": "account", "title": "Account & sign-in", "iconName": "account_circle", "articleCount": 12, "description": "Reset PIN, change phone…" }
]
```

`iconName` is a hint — recognised values: `account | account_circle | payments | credit_card | safety | shield | fraud | rides | ride | jobs | job | payouts | verification | bug`. Anything else falls back to a default icon.

### `GET /v1/support/help/categories/:slug/articles?audience=…`

`HelpArticle[]` summary form (no `bodyMarkdown`).

### `GET /v1/support/help/articles/:slug?audience=…`

`HelpArticle` full form. `bodyMarkdown` REQUIRED. The mobile renders with `flutter_markdown` (HTML disabled), so ship sanitised Markdown only.

### `GET /v1/support/help/search?q=&audience=`

Full-text search. `q.length >= 2` enforced server-side too. Returns `HelpArticle[]` summary form. Recommend ranking by `category` exact-match → title match → body match.

## 3. Legal documents

### `GET /v1/legal/:slug?audience=client|provider`

```json
{
  "slug": "terms",
  "title": "Terms of Service",
  "version": "1.0.0",
  "effectiveAt": "2026-01-01T00:00:00Z",
  "bodyMarkdown": "…sanitised markdown…",   // required EXCEPT when externalUrl is set
  "externalUrl": "https://…"                 // optional; for third-party-licenses or externally hosted docs
}
```

Slugs the mobile already iterates over (in this order):
- `terms`
- `privacy`
- `acceptable-use`
- `community-guidelines`
- `third-party-licenses` — **expected to ship with `externalUrl` only** (license bundle is huge)
- `cookie-policy`

The mobile considers any other slug an error (404 → 'Document not available').

This endpoint is **public** (no JWT required). The mobile may hit it on the welcome / sign-up screens later for the consent footer.

## 4. Attachment uploads (reuses existing media pipeline)

The mobile uses the **existing** `POST /v1/media/upload-url` + `POST /v1/media/confirm` pipeline with `purpose: 'support_attachment'`. **No new endpoint needed.** Just allow that purpose value and store under `media/support_attachment/<userId>/...`.

Mobile flow:
1. `POST /v1/media/upload-url { purpose: 'support_attachment', mimeType, fileSize }`
2. PUT the file to the presigned URL
3. `POST /v1/media/confirm { storageKey, remoteUrl }`
4. Pass returned `url` into `attachments[]` on `POST /v1/support/tickets` or `…/messages`

Backend hardening:
- Reject images > 5 MB and any non-image MIME for `support_attachment` purpose
- Cap 4 attachments per ticket / per message (mobile already enforces)

## 5. Push notifications (FCM)

Mobile already wires these — backend just needs to emit them.

```jsonc
// New reply from agent on a ticket
{
  "type": "support_ticket_message",
  "ticketId": "tkt_…",
  "messageId": "msg_…",
  "title": "New reply from support",     // optional, used as banner title
  "body": "<message preview>",            // optional, truncated to ~120 chars
  "notificationId": "ntf_…"               // optional, for read tracking
}

// Status flipped server-side (agent resolved / closed / etc.)
{
  "type": "support_ticket_status_changed",
  "ticketId": "tkt_…",
  "status": "resolved | closed | in_progress | waiting_user",
  "notificationId": "ntf_…"
}
```

Both deep-link to `/profile/support/tickets/:id` (client) or `/account/support/tickets/:id` (provider). The mobile invalidates the affected ticket detail provider on receipt — no WebSocket needed for v1.

Notification mobile constants live at:
- `apps/client/lib/src/core/services/local_notification_service.dart`
- `apps/provider/lib/src/core/services/local_notification_service.dart`
(constants `typeSupportTicketMessage`, `typeSupportTicketStatusChanged`, `keyTicketId`, `keyMessageId`)

## 6. Schemas

### `SupportTicket`

```json
{
  "id": "string",
  "category": "account | payments | rides | jobs | payouts | verification | safety | bug | other",
  "subject": "string",
  "description": "string?",                     // omitted on list, present on detail
  "status": "open | in_progress | waiting_user | resolved | closed",
  "priority": "low | normal | high | urgent",
  "createdAt": "ISO8601",
  "updatedAt": "ISO8601",
  "lastMessagePreview": "string?",
  "lastMessageAt": "ISO8601?",
  "unreadCount": 0,
  "referenceType": "string?",
  "referenceId": "string?",
  "attachments": [TicketAttachment]             // original-filing attachments only
}
```

### `TicketMessage`

```json
{
  "id": "string",
  "ticketId": "string",
  "senderRole": "user | agent | system",        // 'support' is also accepted as alias for 'agent'
  "senderId": "string?",                        // optional; user id of agent for audit
  "body": "string",
  "attachments": [TicketAttachment],
  "createdAt": "ISO8601",
  "readAt": "ISO8601?"
}
```

### `TicketAttachment`

```json
{
  "url": "https://…",
  "mime": "image/jpeg",
  "sizeBytes": 12345,
  "filename": "string?"
}
```

### `HelpCategory`

```json
{
  "slug": "string",
  "title": "string",
  "description": "string?",
  "iconName": "string?",
  "articleCount": 0
}
```

### `HelpArticle`

```json
{
  "slug": "string",
  "title": "string",
  "summary": "string?",
  "bodyMarkdown": "string?",        // omitted on list endpoints
  "categorySlug": "string?",
  "categoryTitle": "string?",
  "updatedAt": "ISO8601?"
}
```

### `LegalDocument`

```json
{
  "slug": "string",
  "title": "string",
  "version": "string (semver-ish)",
  "effectiveAt": "ISO8601?",
  "bodyMarkdown": "string?",
  "externalUrl": "https://…?"
}
```

## 7. Out of scope for v1

- Re-consent flow for legal version bumps. `version`/`effectiveAt` are in the schema so we can layer this in later without a migration.
- WebSocket delivery of ticket messages. FCM-driven invalidation is sufficient for pilot — re-evaluate once we have hot-conversation usage data.
- Help-article feedback POST (thumbs up/down). Mobile UI is wired but a no-op until backend exposes `POST /v1/support/help/articles/:slug/feedback`.

## 8. Mobile-side error mapping

The mobile maps backend `error.code` strings via `SupportErrorCodes` constants in `packages/api_client/lib/src/models/support_dtos.dart`. Please use those exact strings for the listed cases — anything else falls back to a generic toast.

## Open questions to confirm

1. Is `support_attachment` an acceptable `purpose` to add to the existing media pipeline, or do you want a separate `/v1/support/uploads/sign` endpoint?
2. Confirm `/v1/legal/:slug` is allowed unauthenticated.
3. Confirm SupportAgent role (EDD L4) has an existing admin route to view/respond to tickets — if not, please flag what timeline that lands on.
4. Any objection to the proposed FCM `type` strings? They follow the `<domain>_<event>` convention used by the rest of the notifications.
