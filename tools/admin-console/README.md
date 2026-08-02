# GojoAdmin, locally

A stopgap operator console for the jobs that need a human **now** — reviewing partner
applications, reviewing vehicles, working the moderation queue and watching for a
raised SOS — while the real GojoAdmin is still unbuilt.

It is deliberately small and deliberately disposable. It has **no database, no build
step and no dependencies**: every screen is a renderer for `/v1/partner/admin/**`,
`/v1/moderation/admin/**` and `/v1/travel/admin/sos` — the same public REST surface
ARCHITECTURE §10b reserves for GojoAdmin ("no private tables and no parallel data path"). The day the
real console exists, this directory is deleted and nothing has to be unwound.

## Running it

Node 18+ (uses built-in `fetch`). No `npm install` — there is nothing to install.

```bash
PARTNER_ADMIN_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id gojogo/partner-admin-token --query SecretString --output text) \
  npm start --prefix tools/admin-console
```

Then open **http://127.0.0.1:4319**.

### Signing decisions with your name instead

The break-glass token works, but it signs every decision as an anonymous operator. If
you are in the `platform-admin` Cognito group, pass your own ID token instead and the
audit trail carries your name:

```bash
GOJOGO_ADMIN_JWT=<your Cognito ID token> npm start --prefix tools/admin-console
```

Both may be set; the JWT is preferred by the API. Neither is stored anywhere, and
**neither ever reaches the browser** — see below.

### Other knobs

| Variable | Default | Why |
|---|---|---|
| `PORT` | `4319` | Change if it clashes. |
| `GOJOGO_API` | `https://api.gojogo.app` | Point at a different environment. |

## Why there is a server and not just an HTML file

Two reasons, both about not degrading production to make a local tool work.

**CORS stays off in prod.** The backend serves only the iOS app today —
`WEB_ALLOWED_ORIGINS` is empty, so it sends no CORS headers at all. A page opened from
disk calling `api.gojogo.app` would be blocked, and the "fix" would be adding localhost
to an allowlist on the live task definition. Proxying through this process makes every
request same-origin, so **production needs no change whatsoever**.

**The credential never reaches the browser.** It is read from the environment in
`server.mjs` and attached there. Nothing in `public/` has ever seen it — not in a fetch
header, not in `localStorage`, not in the DOM. A token that lives in one process cannot
leak from a browser extension, a screenshot or a shared tab.

Two consequences worth knowing:

- The proxy is **not open**. `ALLOWED` in `server.mjs` is an explicit method + path
  allowlist, and anything else gets a 403 that tells you so. A process holding an
  operator credential that forwards whatever it is asked is a hole; adding a screen
  means adding its route, and that friction is the point.
- It binds to **127.0.0.1 only**, never `0.0.0.0`. This credential should not be
  reachable from the café wifi.

## What it does

| Screen | What it covers |
|---|---|
| **Applications** | The partner queue by status and kind; full detail with the stake, the identity check, every uploaded document behind a short-lived signed link, and each vehicle with its papers. Approve / reject / suspend / restore, and submit a draft on the applicant's behalf. |
| **Reports** | The moderation queue. Hide, remove, suspend, restore, dismiss — with the context a decision needs (how many other reports are open on the same target, whether the content is already gone). |
| **SOS** | Trips somebody raised an alarm on (Phase 3 M5), newest first: when, who raised it, the driver and their plate, and the route. **Read-only, deliberately** — there is no "resolve" button because there is no honest thing for one to mean. A trip in trouble is dealt with by a person picking up a phone, and a status changing in a queue would only make it look handled. |
| **File an application** | The admin-side create. Restaurants are created here rather than in the app (decided 2026-07-27). |

Two rules it holds to throughout:

1. **The server decides, the console renders.** It never computes whether an
   application may be approved, what a stake should be, or which documents are
   missing — `submitBlocker`, `missingDocuments`, `canSubmit` and `stake` are all
   fields the API already answers. A second copy of a rule is a rule that will
   eventually disagree with the first.
2. **Consequential actions are confirmed and say what they will do.** Approving
   provisions a real driver or restaurant into a vertical; suspending takes a live
   merchant out of the catalog; remove is the door that only opens outward. Each names
   its consequence before it runs, and reject requires a reason because the applicant
   reads it.

## What it deliberately does not do

- **Edit platform config.** There is no write endpoint — values are seeded by migration
  until real GojoAdmin owns them (SPECS §14).
- **Edit menus or storefronts.** Those are the owner's own `/mine` surfaces, driven with
  the owner's JWT. An admin mirror of them is exactly the parallel data path §10b forbids.
- **Store anything.** Close it and no state is lost, because there was none.

## Known limits

- **A driver or merchant still has to pass their own ID check before an application can
  be submitted.** Nobody can do a liveness check on somebody else's behalf, and this
  console cannot either — it will show you the refusal, in the server's words.
- Vehicle *photos* are not rendered (there is a table and a cap, but no client picker
  yet, so there is nothing to show).
- No pagination: the queue reads the newest 100 of a status. If that ever truncates
  something you needed, that is the moment to build the real console rather than to add
  a page control here.
