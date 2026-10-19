# Clip Studio: Accounts tab — central inbox + email slots + credential tracker

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo ~/Projects/clip-studio (you are in your own worktree/branch).
Engine venv only in main checkout: from the worktree's engine/ run `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q`.
No push, no merge, never relaunch ClipStudio.app, real library read-only (`sqlite3 "file:...?mode=ro"`; tests use fixtures/tmp copies).
NO live network calls to Resend (there is no key yet; mock HTTP in tests). No DNS changes. Never create/automate platform signups, never
post/queue/submit. Write result.md EARLY and extend it as you go. Tests green != right: LOOK at the proof stills and say what looks off.

## Yahia's ask (2026-10-13, verbatim)
"something like agent mail to have all our emails for the accounts we make to flow into one central inbox with just a bunch of the emails
for each account and platform setup and ready to be setup with usernames and passwords and a tracker built for the creds"
DECIDED with Yahia: own catch-all (not AgentMail) · addresses on subdomain `in.prismlens.net` (store as setting `mail.domain`, default
that value) · lives in Clip Studio as an "Accounts" tab · platforms now: tiktok, instagram, youtube.

## How mail arrives (infra Yahia sets up himself — you only build the client)
Resend Receiving: an MX record on `in.prismlens.net` points at Resend, which accepts mail for ANY address there and stores it 30 days.
The app pulls it — no server. Docs (WebFetch them; confirm exact paths/fields before coding):
- List: `GET https://api.resend.com/emails/receiving` — `limit` 1-100, cursor `after`|`before` (an email id), returns
  `{object:"list", has_more, data:[{id,to,from,created_at,subject,cc,bcc,reply_to,message_id,attachments[]}]}`. No body.
  https://resend.com/docs/api-reference/emails/list-received-emails.md
- Body: https://resend.com/docs/api-reference/emails/retrieve-received-email.md (fetch ONLY for ids not already stored).
- Rate limits: https://resend.com/docs/api-reference/rate-limit.md — stay under them (sequential, small sleep, back off on 429).
Key: a SEPARATE Resend account's full-access key (receiving quota must never eat Prism's sending quota). Add a new KeyName (e.g.
`resendInbound`) to the existing Keychain key flow (Sources/ClipStudioCore/Keys.swift KeyResolver, AppModel.saveKey, Settings keys UI);
it reaches the engine the same way the existing Upload-Post key does. Never log it.

## Data model — EXTEND, don't duplicate (one name per thing)
Existing `accounts` table (engine/clipengine/accounts.py): id, campaign_id NOT NULL, platform in (instagram,youtube,tiktok), handle,
status planned|created|connected|posting, UNIQUE(campaign_id, platform). It has 0 rows. Additive migrations only (ALTER ADD COLUMN /
new tables; never rebuild or drop existing tables):
- `accounts` + `email` (address), `username` (login name if it differs from handle), `has_password` 0/1, `has_totp` 0/1.
- NEW `mailboxes(address PK, platform, created, account_id NULL)` = the ready-made addresses. Naming `tt-01@<domain>`, `ig-01@`,
  `yt-01@`, zero-padded, next free number. Seed 5 per platform on first use; "Add 5" per platform in the UI. Creating an account
  assigns the next free mailbox of that platform (editable). Catch-all means every address works instantly — a mailbox is a reservation.
- NEW `inbox_mail(id PK = Resend id, to_addr, from_addr, subject, received_at, platform, code, link, body_text (cap ~20 KB), seen,
  fetched_at)`. Mail to an address with no mailbox row shows as "Unassigned" (typos/spam land there too).
- Engine CLI `clipengine mail sync` (JSON events like the other commands): walk newest-first until a known id, upsert idempotently,
  fetch bodies for new ids, run extraction, emit counts. Visible failure states: no key / 401 / 429 / network — never silent.
- Pure fn `extract_code(subject, text, html) -> (code|None, link|None)`: verification/login codes (4-8 digits, Google "G-123456"
  style), ignoring years, prices, phone numbers, order numbers, zip codes; `link` = the verify/confirm/reset link if any. Platform from
  sender domain (tiktok.com, instagram.com/facebookmail.com/mail.instagram.com, google.com/youtube.com/accounts.google.com).
  Table-driven tests with realistic synthetic emails per platform (code in subject, code only in HTML body, link-only, a promo email
  with prices and a year that must yield NO code, a security alert with no code).

## Credentials — Swift + Keychain ONLY
Passwords, TOTP secrets and backup codes live in the macOS Keychain (SecItem generic password; services `ClipStudio.account`,
`ClipStudio.totp`, `ClipStudio.backup`; account = accounts.id). NEVER in SQLite, logs, run records, proof stills, or the engine.
- Generate: 20 chars, upper/lower/digits + a platform-safe symbol set; store immediately; DB only flips `has_password`.
- Copy puts it on the pasteboard and clears it after 60 s if unchanged; reveal is an explicit toggle that re-hides on deselect.
- TOTP (RFC 6238, SHA1, 6 digits, 30 s; accept otpauth:// URI or base32): live code + countdown. Swift tests with RFC test vectors.
- Tests use a test-only service prefix and clean up after themselves; never touch the real `ClipStudio.*` items.

## UI — "Accounts" tab (follow the app's existing tab/sidebar pattern and design tokens; v1 must pass ~/.claude/skills/taste/SKILL.md)
- Left: "All mail" (the central inbox, unread count) · accounts grouped by platform (handle or "planned", status chip, email, unread dot,
  last mail time) · "Spare addresses" per platform with copy buttons + "Add 5".
- Right, account selected: login card (email, username, password ••• with copy/reveal/generate/set, 2FA live code or "Add 2FA",
  backup codes), then that account's mail newest first; a mail with a code shows the code BIG with one-click copy, and a "Open link"
  button for the verify link. "New account": pick campaign + platform -> mailbox auto-assigned -> password generated -> status planned.
- Sync: on tab open, every 60 s while the app is open, and a refresh button; show "synced 12 s ago" / the failure state + fix.
- Empty states that say what to do (no key: "Add your Resend inbound key in Settings"; no mail yet: show the addresses to sign up with).

## Gates (run them yourself, paste the tails into result.md)
Full engine pytest + `swift build` + `swift test` green. Migration test on a tmp COPY of the real library (`.backup` it into tmp):
existing rows untouched, re-run is a no-op. Proof stills in docs/proof/accounts/ from a seeded TEMP library with FAKE accounts/mail
(All mail, an account with a TikTok code shown big, spare addresses, the no-key empty state) — zero real secrets in any still.
Commit on your branch only: code, tests, stills, result.md.
