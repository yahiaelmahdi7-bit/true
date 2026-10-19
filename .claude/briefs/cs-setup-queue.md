# Clip Studio — account setup queue + Chrome autofill helper

Repo: ~/Projects/clip-studio (you are in a worktree off main @5ad6e76; ecosystem merged, gates green: engine 1028 pass, swift 115/0).
Read first: docs/ECOSYSTEM.md (contract), engine/clipengine/accounts.py, engine/clipengine/inbox.py,
Sources/ClipStudioCore/CreateFlow.swift, Sources/ClipStudioCore/Credentials.swift, Sources/ClipStudio/AccountsView.swift.

## Goal (Yahia, verbatim intent)
"Automated into autofill when I'm setting it up, and once one account is set up and mail confirms it, we move to the next one
loaded into autofill. I'll just set up all the accounts you need on the platforms you want."
So: the SYSTEM decides which accounts are needed, loads each into autofill in Chrome, catches the verification mail, advances.
Yahia types nothing he doesn't have to; he still clicks submit, solves CAPTCHAs and does any phone check himself.

## What exists (reuse, don't duplicate)
accounts table (one row per campaign x platform, planned→created→connected→posting), handle ideas / bio / avatar kit,
mailboxes on the catch-all `in.prismlens.net` with code+link extraction (inbox.py), passwords in Keychain only
(CredentialStore: service `ClipStudio.account`, account = account id), the one-at-a-time "New account" sheet (CreateFlow).

## Build
1. Engine `account-queue` (new module accounts_queue.py; CLI `account-queue build|list|current|confirm|skip|profile` --json):
   - build: for every campaign with status='joined' (or --campaign), each platform its rules allow (default all three):
     accounts.plan + inbox.assign_next. Idempotent. Order: campaign joined order, then tiktok, instagram, youtube.
   - current: first planned, not-skipped account → {account_id, campaign name, platform, kind, email, handle + 4 alternates,
     display_name, bio, avatar path, signup_url, step, code, link, n_done, n_total}.
     kind = "new_account" for TikTok/Instagram; YouTube = "brand_channel": NO new Google account — a brand channel under
     Yahia's existing Google login (checklist: switch account → create a channel → name = display_name → handle).
   - code arrival: a mail to the account's address received after the item became current, with a code or link.
   - confirm (handle actually used, may differ) → accounts.advance(status='created'), event `account.created`, returns next current.
   - Auto-advance: advance WITHOUT a click when there is evidence the account exists: a second mail from that platform after the
     code mail that is a welcome / account-created mail. That is a classify step → Jev call via engine/clipengine/jev.py
     (noul: "is this an account-created/welcome mail from <platform> for this address?"), route on confidence, log it;
     below the floor → the panel asks "Done? → Next" (one click). Never advance on the code mail alone.
   - profile: Yahia's own full name + birthday, entered ONCE in the app, stored locally in config `setup.profile`
     (signup forms ask for them). Never generate or invent identities or birthdays.
2. Native messaging host — NO localhost port. engine/clipengine/setup_host.py speaks Chrome native messaging
   (4-byte little-endian length + JSON on stdio). `account-queue install-extension` writes
   ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.clipstudio.setup.json (allowed_origins = the
   extension's fixed ID, derived from a "key" in its manifest so the unpacked ID is stable). Messages: current, confirm, skip,
   poll(account_id) → inbox sync throttled to ≤1 Resend call per 3 s while a queue item is open, password(account_id) →
   Keychain read via `security find-generic-password -s ClipStudio.account -a <id> -w`; if none exists yet, generate a strong
   one and store it with `security add-generic-password ... -T /usr/bin/security -T <ClipStudio.app path>` so both the app and
   the host can read it without repeated prompts; set accounts has_password=1. Passwords never reach disk, logs, events,
   stdout logging, the DB or chrome.storage.
3. Chrome extension extension/clipstudio-setup/ (Manifest V3, no remote code, no third-party libs):
   - Side panel: "Account 3 of 9 · TikTok · <campaign>", each field with Copy, a Fill button, an "auto-fill when the signup
     page opens" toggle, "Waiting for the code…" → code shown + filled when it arrives, Done→Next, Skip.
   - Content scripts for the signup pages of tiktok.com, instagram.com and youtube.com channel creation. Find fields by
     autocomplete / type / name / aria-label / placeholder / label text (never generated class names); set values with the
     native value setter + input/change events so React forms accept them.
   - NEVER click submit/next/continue, never touch CAPTCHA, phone or anti-bot elements, no fingerprint or proxy tricks.
     A field it can't find → the panel says which, and Copy is the fallback.
4. App: Accounts → "Set up accounts": progress (3 of 9), current card, done/next/skipped list, profile form, and an
   "Install Chrome helper" step (runs install-extension, shows the folder to Load unpacked at chrome://extensions with
   Developer mode). Keep the existing single "New account" sheet working.

## Tests + proof
No network in tests. Engine: queue build/order/idempotence, confirm/skip, code-arrival window, auto-advance routing (Jev mocked,
both sides of the floor), native-messaging framing round-trip, Keychain via a mocked runner. Extension: field detection against
hand-written HTML fixtures shaped like each signup form (`node --test` if node exists; else document why skipped).
Swift: queue view model tests. Stills (light + dark) of the Set up accounts view: populated, waiting-for-code, code arrived,
all done, helper not installed — through the existing screenshot harness, then LOOK at them.
Gates (foreground): `cd engine && PYTHONPATH=$PWD ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` and
`swift test` AT REPO ROOT (not app/). Before every commit: `git checkout -- docs/proof/submit/happy.png;
rm -f docs/proof/submit/happy-watched-run.png`.

## Rules
Never flip post.golive. Never touch ~/Projects/clip-studio.live or the main checkout (only run its venv python). No real signups,
no real mail sends, no Chrome automation from you. `__main__.py`: append imports/add() at the END of their blocks.
Report in docs/lanes/setup-queue.md: built, gate tails, verified vs NOT verified, any contract change (+ ECOSYSTEM.md §10 line).

```
DISCIPLINE (non-negotiable):
- Commits: atomic, message says what+why. NEVER push, NEVER merge. The user pushes, not you.
- Gates: run in the FOREGROUND and wait. NO background shells, NO watch modes, NO until-loops.
- Claims: 'done' means you ran the gate and pasted the passing output. Code written ≠ working.
- Decisions: classify/route/gate/verify steps are Jev calls via engine/clipengine/jev.py: code owns the flow, Jev answers narrow
  typed questions, route on confidence, log the decision. No LLM prompt-and-parse, no keyword lists as the decider.
- If blocked: say BLOCKED + one line why. Do not invent extra scope.
```
