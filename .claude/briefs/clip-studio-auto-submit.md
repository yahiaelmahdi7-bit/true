# Clip Studio: campaign auto-submit — 30-minute submit window, submission ledger, linked-account check, in-app submit

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clip-studio (worktree off main at or after
9461932). No push, no merge, never relaunch the ClipStudio app, never write to the real library (`?mode=ro` only; tests use
fixtures / a tmp CLIPSTUDIO_HOME copy). Never post, queue or SUBMIT anything for real; never load contentrewards.com in a test.
Write result.md EARLY and extend it as you go. Worktrees have no venv: run tests as
`PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the worktree's engine/; Swift: `swift build` + `swift test`.

## Why (Yahia, 2026-10-12)
Content Rewards' "Submit clip" dialog (Solved, cmp_6fe50dcdb4) auto-rejects unless: (a) posted from one of your linked accounts,
(b) not already submitted to this campaign, (c) posted within the last 30 MINUTES; plus a tick on "I've read the requirements
and accept that non-compliant submissions may be auto-rejected." Platform icons Instagram + YouTube; link field placeholder
"https://www.tiktok.com/@username/video..."; buttons "Cancel" / "Submit clip". Yahia chose: FULLY AUTOMATIC submission, and
scheduled posts stay allowed. Today: rules parser misses this wording, countdown starts at the Upload-Post request (not go-live),
nothing records campaign submissions, only `.joined` campaigns get countdowns (CampaignExtras.swift syncCountdowns ~l.110).

## Lane discipline (other builders edit campaigns/onboarding, render.py, effects, playbook.py right now)
New engine module `engine/clipengine/submit.py` + new Swift file(s) (e.g. `Sources/ClipStudio/AutoSubmit.swift`). Existing
files: small additive call sites only. Schema changes additive (CREATE TABLE IF NOT EXISTS / ADD COLUMN), never rewrite rows.

## 1. Parser (campaigns.py ~l.146)
`within\s+(\d+)\s*minutes?` misses "Posted within the last 30 minutes". Accept "within (the )?(last|first )?N min/mins/minutes",
"N-minute window". Tests with the exact CR string above + the existing Lovable/Whop strings (no regressions).

## 2. Real go-live time + public link
Countdown and submission start from when the post is actually LIVE on that platform (Upload-Post status for the request_id),
per platform, never from posts.created. Scheduled posts: start at go-live. Store live_at + public post URL per (post, platform).
If Upload-Post's API can't give live time/URL, poll the status endpoint until it does and say exactly what it returns in result.md.

## 3. Submission ledger (enforces "not already submitted")
Table `campaign_submissions(id, campaign_id, post_id, platform, post_url, account_handle, state, live_at, deadline, attempted_at,
submitted_at, evidence_path, detail)`, UNIQUE(campaign_id, post_url). States: pending → submitted | needs_you | failed | expired.
A URL already present never gets submitted again. Countdown UI reads the ledger (remove the UserDefaults-only start keys or
migrate them).

## 4. Linked-account check
Per marketplace, store the handles Yahia linked (Settings field + read from the CR connected-accounts page in the in-app browser
when visible). Auto-submit only if the posting account's handle (per platform, from the Upload-Post profile) is in that list;
unknown/mismatch → needs_you with the reason. Never guess a handle.

## 5. In-app auto-submit (InAppBrowser / WKWebView, Yahia's own CR session; no login automation, no cookies export)
Preconditions, ALL required, else needs_you: campaign joined + auto_submit ON for it; post approved by Yahia (existing gate),
dry_run=0, live, public URL resolves; clip's campaign rules check is green; linked-account check passes; not in ledger;
now < deadline - 2 min. Steps: open campaign page → open Submit dialog → pick platform → fill URL → wait for the three
checks to resolve → if any check is not green: stop (needs_you, keep dialog open, notify). Tick the acknowledgement ONLY if
its label text matches the known sentence above (normalised whitespace/quotes); any other checkbox, extra terms, or changed
wording → stop, needs_you. Press "Submit clip", then READ the post-state (success toast / the submission listed) and save a
snapshot as evidence; no confirmation read = failed, never "submitted". Max 2 attempts. Window passed → expired + notify.
FIRST real submission per marketplace = watched run: do everything, pause before "Submit clip", notify Yahia to press it;
after one confirmed success, fully automatic. Per-campaign toggle `auto_submit`, default ON for joined campaigns with a
submit window (Yahia's call), + a global kill switch. Fallback on any stop: dialog left open with URL filled,
link on clipboard, notification with minutes left.
Scheduled posts: auto-submit needs the app open + Mac awake at go-live; scheduling UI for submit-window campaigns shows
"Clip Studio must be open at <time> to auto-submit"; on launch, any missed window → expired + notify.

## Proof (local only)
Local HTML fixtures mirroring the dialog (from the description above): happy path; one check red; changed acknowledgement
text; extra checkbox; duplicate URL; deadline passed; slow check resolution. `--qa-snapshot` PNGs of each in docs/proof/submit/.
result.md: table fixture → final state + evidence path; exact Upload-Post status fields used for live_at/URL.

## Done =
Whole engine pytest + swift test green; new tests for parser, ledger uniqueness, deadline math (scheduled + immediate), every
precondition failing → needs_you, acknowledgement-text mismatch → never ticked, no "submitted" without a read confirmation.
