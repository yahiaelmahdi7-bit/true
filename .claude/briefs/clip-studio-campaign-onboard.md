# Clip Studio: Campaign Onboarding — scan every new campaign, full day-1 kit on join

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clip-studio, worktree off main 1290124. No push,
no merge, never relaunch the ClipStudio app, never write to the real library or lab home (tests: fixtures / tmp; proof:
CLIPSTUDIO_HOME=<tmp copy>, CLIPSTUDIO_LAB_HOME=<tmp>). NEVER post, publish or enqueue for posting. Worktrees have no venv: run
`PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the worktree's engine/; build the gitignored Swift
binaries (engine/native/framescan, engine/native/personmask) in the worktree first. Two other builders are editing right now:
editroom/depth/editcraft (caption flow) and trendscout/stylepack/stylelearn/framescan (scout r2) — do NOT edit those files;
call their public functions/CLI only. Write result.md EARLY and extend it as you go.

## The ask (Yahia)
"we need a campgaine onbroding system/pipline to get all the content and matreial and trneds in the area needd to suceed and
setup from day 1". His decisions: (1) every new campaign the feed finds gets a cheap SCAN; FULL onboarding runs when he joins
one. (2) Full onboarding ends with a research kit + edit setup + 6 rendered drafts (two days at the 3/day cap) waiting in the
approval queue.

## Already exists — orchestrate, do not rebuild (read before writing code)
campaigns.py (campaign-add / refresh / rules / check: public page → rules, Jev red/amber verdict; campaign-sources: allowlisted
download plan; campaign-assets; campaign-music; campaign-tags; campaign-live), campaign_feed.py (marketplace discovery),
route.py (niche), ingest / transcribe / moments (moment mining + Jev scores), editroom (edit-broll-index, edit-music-index,
edit-style, edit-run/render), trendscout (lab-scout/fetch/learn/trends; `lab-templates` lands with scout r2 — feature-detect it),
launch.py (account day 0/1/2 plan + readiness, account side only), accounts. Find the existing "joined" signal for a campaign
(e.g. an account linked to it, or campaign-live); if there is none, add `campaign-join <id>` and make it trigger onboarding.

## 1. Scan (automatic, cheap, NO downloads) — `campaign-scan <id>`, auto-run on new feed rows
- Rules: refresh + parse + red/amber verdict (existing). Payout per view, platforms, allowed formats (clips / edits / fan edits
  / compilations), music rules, required tags/links, banned content.
- Creator demand (YouTube Data API, official, quota-metered, keychain `youtube-api`): the creator's channel(s) from source links →
  channel stats + their own top shorts; other people's clips of this creator in the last 30 days (search creator name, short)
  → view distribution and outliers. That is the "does this sell" signal.
- Niche (route.py) and a fit score: Jev `score` with concrete levels on {rules summary, payout, allowed formats, source type
  (long-form talking / stream / other), demand numbers}. Levels describe situations, e.g. "red rule or no usable source" …
  "long-form talking source, allowed clip format, proven demand".
- Output: scan card stored in DB + `campaign-scan` JSON event. Auto: hook campaign_feed.run so new rows get a scan, with a daily
  cap (named constant) and the shared YouTube quota floor; over cap → queued for tomorrow, logged.

## 2. Full onboarding (on join) — `campaign-onboard <id>`, resumable stage table, never redoes a finished stage without --redo
Each stage writes status + numbers + reason; a failed stage stops the stages that depend on it, not the others.
1. **rules** — fresh refresh; red → stop and report; amber → flagged for Yahia, continue.
2. **sources** — download the allowlisted plan (config: N latest + M most-viewed long-form, defaults small), transcribe, mine
   moments (existing commands). Only allowlisted/campaign-provided sources.
3. **proven** — what already works for THIS creator: the top outlier shorts from the scan (theirs + other clippers'), learned
   through the lab (fetch → learn, grammar only) → their styles + topics. Topic overlap with our moments = a ranking boost.
4. **niche trends** — scout queries built from the niche + creator name, genres talking and (if the campaign allows edits)
   fan_edit → trends + templates when `lab-templates` exists, else "templates: pending scout r2" (not an error).
5. **material** — b-roll index from the downloaded sources, music index (campaign-provided licensed tracks only; licence gate),
   assets (logos/overlays from campaign links), tags.
6. **setup** — proposed per-campaign edit_style: frame, preset (Jev pick, existing), music_bed only if licensed, template pick
   (Jev `choice` over templates + "none" given campaign rules, allowed formats and the creator's footage features), depth_captions
   stays OFF (Yahia's call, never auto-enabled). Written with `set_by: onboarding` and the previous value kept.
7. **drafts** — top 6 moments (moment score + proven-topic boost, one per topic where possible) rendered through the normal Edit
   Room run into the approval queue (status awaiting approval). Never posted, never auto-approved.
8. **launch** — for each account linked to the campaign: existing launch-plan; none linked → kit says so and points at account-kit.
9. **kit** — `campaign-kit <id>`: a readiness checklist (go / no-go per item with the numbers: rules, sources, moments over floor,
   b-roll shots, music status, template, drafts awaiting approval, accounts) + `kit.md` in the campaign asset dir + JSON.

## Rules (settled — never change)
Rights gate on every source and asset; third-party refs = grammar only, never reuse their footage/audio/words, never commit them.
Music: licence gate always; never AI, commercial or ElevenLabs music. Official sources only: no logins, cookies or proxies.
Approval gate + 3/day cap + go-live gate stay; nothing here posts. One account per platform per campaign. Numbers we have not
measured are labelled unverified.

## Proof (tmp home)
Scan 3 real campaigns from a COPY of the feed table (scan cards in result.md). Then full onboarding of PB Blake (cmp_77539b16a8)
from scratch in a fresh tmp home holding only its campaign row, small N (3 sources): stage table, kit.md, 6 drafts. Contact
sheet per draft from the real MP4s — LOOK at them (picture, captions, no black frames, audio present). Quota units used,
wall time per stage. Unit tests: stage resume/skip/--redo, dependency stop, scan cap, fit-score request shape (Jev mocked),
draft picker, kit checklist.

## Done =
Whole engine pytest green incl. new tests; proof run in result.md with the drafts looked at; result.md says plainly what is weak
or pending (e.g. templates until scout r2 merges).
