# Clip Studio publish fix1 — source↔campaign binding, campaign rules as truth, ONE slot routine (post → live → submit)

Repo ~/Projects/clip-studio (main = 566a09d). Engine tests: `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q`
from the worktree's engine/. Swift: `swift build` + `swift test` from the worktree root. Another builder (quality-fix1) owns b-roll,
presets, profanity, account-kit, depthlook, trendscout, onboard yield — stay out of those. Evidence: `clipengine e2e` break lists in
docs/proof/e2e/*.md + result.md. Each item: fix + test + one line in result.md. Tmp library/home only; NEVER write the real library
(~/Library/Application Support/ClipStudio) — anything that must change real rows ships as a command with --dry-run that I run.

1. P0 SOURCE↔CAMPAIGN BINDING. `sources` has no campaign link: e2e for Solved fell back to "any rights=campaign source" and rendered
   a PB Blake video (src_72d04eaf17, A5xYfRsaFIU) as a Solved clip, then passed it against PB's own allowlist. Fix: additive column
   `sources.campaign_id`; set it at every ingest/onboard/campaign-sources path; EVERY campaign-scoped query (moments, edit-run
   --campaign, onboarding drafts, publish, submit, e2e) filters by it and FAILS CLOSED on a missing/mismatched source (no fallback).
   Backfill command `clipengine sources-bind [--apply]` (default = dry-run preview table): binds by channel / campaign_rules
   campaign id / "solved-<videoId>" title; sets sources.url (Solved rows: title solved-<id> → https://www.youtube.com/watch?v=<id>,
   note ids can start with "-") and rights_note = "<campaign name> campaign source: <campaign url> · <watch url>" where empty.
   Unbindable rows are listed, never guessed. Real library: 5 Solved (url empty, note empty) + 9 PB Blake (note empty).
2. P0 CAMPAIGN RULES = ONE TRUTH. Persist platforms, min/max seconds, required tags/mentions and sources_allowlist on
   campaigns.rules at join/seed/onboard; publish.rules_for, render compliance and QC read campaign rules merged OVER the source copy.
   Solved has no allowlist or source_links: derive the allowlist from the URLs of sources bound to it (mark "derived: campaign-
   provided sources") and say so in result.md. Required-tag match on token boundaries (e2e: '@pbblake' found inside '@PBBlakeYT').
3. P0 ONE SLOT ROUTINE (Yahia 2026-10-12, settled). Each daily slot runs ONE job: next approved clip for the campaign (FIFO by
   approval) → OUR routine posts it directly via Upload-Post (no scheduled_date), payload.user = profile `default`, platforms =
   campaign platforms ∩ platforms linked on `default` (none linked → needs_you, post nothing) → poll go-live (submit.py) → mark the
   submission due → the app's AutoSubmit driver submits → retry until deadline - MARGIN → else needs_you + notification.
   - Slots = publish.slots with launch.PRIME (12:00 / 16:30 / 21:00 local, >= 3 h gap). The slots ARE the 3/day cap: the cap counts
     POSTS (one per slot), not renders; a `rendering` row older than 30 min becomes failed and never counts.
   - Clock = a launchd LaunchAgent with StartCalendarInterval per slot (fires on wake if the Mac slept, so post and submit stay
     together). Ship `clipengine slot-install [--apply]` (default prints the plist + target path; I install it after review).
   - If ClipStudio is not running when submit is due, the routine runs `open -g -a ClipStudio` (Yahia approved) and the app's
     coordinator picks the due row from the ledger. Respect the auto-submit kill switch + per-campaign toggle.
   - Gates checked AT the post step (last step before output): go-live gate (posts stay dry_run until Yahia flips it — do NOT flip
     it), approval, requires_manual_edit if present, campaign status == joined (PB Blake is `watching` → no post), rights + binding,
     spend ceiling. Replace the broken queue h_post path (never set payload.user, ignored campaign platforms) with this routine.
4. P1 SPEND CEILING (settled 2026-10-11): $25/month across Upload-Post + paid APIs, alert at $20, stop at $25. settings key +
   enforcement in queue.lease/run_job and the moments/critique callers; the slot routine refuses past it. Show it in result.md.
5. P2 moments: when Claude returns no JSON candidates, log the raw reply, retry once with a stricter JSON instruction, and mark the
   fallback (origin=heuristic) visibly in the Moments UI.
6. e2e HARNESS: pick_source never falls back to another campaign's source; allowlist comes from the campaign only; stage 9 gets a
   local fixture adapter for submit (go-live → due → submitted on a fixture page, no network); stage 8 exercises the slot routine
   in dry run; process exit code != 0 when any stage FAILs (test it).

Proof (LOOK before claiming): `sources-bind` dry-run table against a COPY of the real library (cp to tmp, then run); `slot-install`
printed plist; e2e on both campaigns against a tmp copy after the bind: Solved must pick a Solved source; table + stills in
docs/proof/e2e/. Commit on the builder branch only; never push; never touch the real library, lab home or ClipStudio.app; nothing
posts live (dry run only); one GET to Upload-Post /users at most per e2e run.
