# Clip Studio — Ecosystem Contract v1 (2026-10-13)

**Goal:** Clip Studio runs each campaign end to end on its own (campaign → sources → moments → edits → approval → post →
metrics → learning), every section talks to the next through one event log, everything is organised per campaign, and the
analytics are deep enough to tell us what works, where we are strong, what we earn, where the pipeline jams, and what to change
next — then measure whether the change helped.

This file is the source of truth for every lane. Base branch: `ecosystem/base` (main + autopilot + vibes, later + accounts/mail +
10s-flash). If something here contradicts the code, the code is wrong unless the contract says "existing".

## Yahia's decisions (do not re-ask)
- Fully hands-off for campaigns marked **trusted**; untrusted campaigns stop at Review for his approval.
- `post.golive` still governs real posting. Code NEVER flips it. Launchd plists are written, never loaded, by builders.
- Analytics first pass covers ALL of: what edits work · money per campaign · pipeline health · audience (region, age) ·
  content-type and platform strengths · ranked improvement suggestions fed back into the system.
- Team budget $300 total. No push. Merges happen only on `ecosystem/base`, done by the lead session.

## 1. Campaign is the root
Every unit of work carries `campaign_id`: sources (via existing binding), moments, edits (existing), clips, posts,
metric_snapshots, campaign_submissions (existing), events. Add the missing columns with an additive migration plus a backfill
(moment → source → binding; clip → edit; post → clip). Rows that can't be resolved get `campaign_id = NULL` and show under
"Unassigned" in the UI; never guess.

## 2. One event log (`events`)
`events(id INTEGER PK, ts REAL, campaign_id TEXT, kind TEXT, subject_type TEXT, subject_id TEXT, actor TEXT, data TEXT JSON,
cause_id INTEGER)`; indexes on (campaign_id, ts) and (kind, ts).
API (engine/clipengine/events.py, owned by L1, first commit of L1):
`emit(c, kind, campaign_id=None, subject_type=None, subject_id=None, actor="system", cause_id=None, **data) -> id`
`since(c, ts=0, campaign_id=None, kinds=None, limit=500) -> list[dict]`
`actor` ∈ system | conductor | auto | yahia | jev. Kinds (dot names, past tense):
campaign.joined · campaign.trusted · campaign.untrusted · source.added · source.transcribed · moment.found · moment.scored ·
edit.rendered · edit.qc_failed · edit.approved · edit.rejected · edit.pulled_back · edit.needs_sound · post.scheduled ·
post.published · post.failed · submission.sent · submission.paid · metrics.snapshot · audience.snapshot · account.connected ·
account.expired · suggestion.created · suggestion.applied · suggestion.dismissed · suggestion.kept · suggestion.reverted ·
conductor.tick · conductor.blocked · conductor.unblocked.
`autopilot_events` stays readable (migrate rows into `events`, keep a compatibility VIEW with the old name/columns).
Every stage transition in the engine emits exactly one event. A contract test greps that each kind above has an emitter.

## 3. Stages (one vocabulary, used by engine, CLI and UI)
`sourcing → transcribing → finding → cutting → review → ready → posted → measured`
- review = edit awaiting approval (untrusted, or trusted but below the bar)
- ready = approved: queued for a slot, or `needs_your_sound`
- measured = posted and ≥ 1 metrics snapshot
Stuck = time in stage > SLA (config `sla.<stage>` minutes; defaults: transcribing 60, finding 30, cutting 60, review 1440,
ready 1440, posted→measured 180).

## 4. One conductor
`clipengine conduct tick|status|pause|resume [--campaign X] [--dry-run] --json` (engine/clipengine/conductor.py, L1).
One tick, per active campaign, in order: refresh sources if due → transcribe pending → find moments → cut edits (caps) → gate
(trusted auto-approve, else leave in review) → queue → track due posts → (nightly) analyze + feedback. `agent tick` and
`autopilot tick` become stage functions it calls (keep their CLIs working as thin wrappers). Single-instance lock, idempotent,
each step time-boxed, failures emit `conductor.blocked` with a human sentence + the fix action and never stop other campaigns.
Global kill switch and per-campaign pause (existing autopilot ones, generalised). `autopilot_state` generalises to
`campaign_state(campaign_id, stage_counts JSON, line, blocker, blocker_action, updated)`.
Scheduling: write `com.clipstudio.conductor.plist` (every 10 min) and a tracker job that runs with the app closed; DO NOT load.

## 5. Trust and auto-approve
`campaigns.trusted INTEGER DEFAULT 0`. `clipengine campaign-trust --campaign X --on|--off --json` returns eligibility.
Eligibility: ≥ 30 of Yahia's keep/reject labels for the campaign (or its niche if the campaign has < 30), and on a held-out 25 %
of those labels (time split, newest held out) the auto-approve rule reaches precision ≥ 0.90. The rule: Jev quality probability
(existing scorer) ≥ a floor fitted on the training 75 %, plus every existing autopilot gate (rules, platform linked, HD QC,
duplicate check, caps, end date, kill switch). Not eligible → the toggle explains "needs N more reviews" or "holdout precision
0.84 < 0.90". Auto-approved edits carry actor=auto and a one-click "Pull back" until posted. Refit nightly; store the floor,
n, and holdout precision per campaign so the UI can show them.

## 6. Analytics warehouse (L2)
Tables (own module `engine/clipengine/analytics/`, own migrate()):
- `post_facts` — one row per post × platform: campaign_id, account, platform, post_id, edit_id, moment_id, source_id,
  posted_at, **features** (hook_type, vibe, style_pack, length_s, caption_mode, has_flash, is_suggested_flash, post_hour,
  post_dow, source_kind, moment_score, jev_quality, auto_approved), **outcomes** (views, likes, comments, shares, saves,
  avg_view_pct, watch_time, views_24h, views_72h, views_7d, engagement_rate).
- `audience_snapshots(account, platform, fetched_at, dimension ∈ country|age|gender|device, bucket, share)`.
  Sources: YouTube Analytics API via the direct-auth tokens (readonly analytics scope), Instagram Graph insights
  (follower_demographics / engaged_audience_demographics; needs ≥ 100 followers), Upload-Post analytics if it exposes them,
  TikTok only what its official API returns. Unavailable → stored as status "not available from <platform>" and shown
  honestly. Never scrape.
- `earnings(campaign_id, post_id, platform, period, verified_views, rate_per_1k, estimated_usd, paid_usd, status ∈
  estimated|submitted|approved|paid, source)`. Rate from campaign rules. paid_usd from a manual "Mark paid" entry or a
  marketplace API if one exists. Estimates are always labelled estimates.
- `costs` = existing `api_calls` + render seconds per edit (record it in the render step).
- `stage_metrics(day, campaign_id, stage, entered, exited, median_minutes, stuck, failed, top_fail_reason)` from `events`.
- `suggestions(id, created, campaign_id, area, title, evidence JSON, expected_lift, confidence, rank_score, action JSON,
  status ∈ open|applied|dismissed|kept|reverted, applied_at, measure_until, outcome JSON)`.
- `perf_weights(campaign_id, feature, value, weight, n, validated_lift, updated)`.
Analyses — `clipengine analyze [--campaign X] --json` (nightly via the conductor):
- **What works:** per feature value, median views / avg_view_pct / engagement vs. the campaign baseline with bootstrap 90 %
  CI; min n = 8 per bucket, otherwise "not enough data" (never crown a winner below n).
- **Strengths:** platform × country × age × content type (type/vibe/style) ranking of where we perform best.
- **Money:** estimated and paid per campaign, per clip, per platform, cost per clip, net, trend.
- **Health:** from stage_metrics: throughput, bottleneck stage, stuck items, failure reasons, source→post lead time.
- **Trends:** our own weekly cohorts over time + external `lab_ref_stats` trends side by side (what the market does vs. us).
- **Suggestions:** deterministic generators turn analyses into concrete changes ("Post Kai clips at 18:00: +34 % median views,
  n=22, CI +12..+51 %"), each with an `action` that changes ONE config key (slot times, hook-type weight, style-pack weight,
  length target, campaign focus/caps, platform mix). Rank = expected_lift × confidence; Jev only breaks near-ties and vetoes
  implausible ones. Applying starts a measure window (default 14 days); afterwards compare against the prior window and the
  untouched campaigns, then mark kept or auto-revert. That closes the loop.
- **Feedback into clipping:** `perf_weights` blend into moment ranking and cut choices ONLY after validation on unseen posts
  (time split: fit on older posts, test on the newest 20 %; adopt only if lift > 0 with CI excluding 0). Log every adoption as
  an event. Label-based learning (calibrate, taste) stays; perf_weights add to it.
- The tracker's per-post parsing must be verified against a REAL recorded Upload-Post response (record one with the existing
  read-only GET, redact ids, commit as a fixture). Tracking must run with the app closed (conductor).

## 7. App (L3) — campaign-first
Sidebar: **Home** (all campaigns: money, views, health, blockers at a glance) · **each joined campaign** · **Analytics** ·
**Library** (Sources, Studio/Moments, Style Lab, Sounds, Discover) · **Accounts**.
Campaign page = header (name, rate, trusted toggle with eligibility text, autopilot state/blocker + fix button, pause) + tabs:
**Board** (columns = the 8 stages, cards = items, counts, stuck badges, actor=auto marked) · **Review** (this campaign's
approval queue; A/R keys) · **Posted** (posts + live metrics) · **Analytics** (campaign-scoped screens) · **Accounts**
(this campaign's platform accounts) · **Settings** (rules, caps, slots, sounds).
Analytics (global and per campaign): Overview · What works · Audience & platforms · Money · Pipeline health · Suggestions
(ranked; Apply / Dismiss; applied ones show their measuring countdown and then kept/reverted with the result).
Queue and Published become per-campaign tabs; global versions stay reachable from Home. Native controls only, Swift Charts,
light + dark, HIG Sample Book IDs added to docs/DESIGN.md, /taste hard-rejects apply, copy through /humanizer.
The UI reads ONLY these CLIs (fixtures in `engine/tests/fixtures/contracts/`, written by L1/L2 first, used by L3 tests):
- `campaign-board --campaign X --json` → `{campaign:{id,name,rate,trusted,eligibility,paused}, state:{line,blocker,blocker_action},
  stages:[{stage,count,stuck,items:[{id,kind,title,thumb,since,stuck,actor}]}]}`
- `events --campaign X --since T --limit N --json` → `{events:[{id,ts,kind,campaign_id,subject_type,subject_id,actor,text,data}]}`
  (`text` = one human sentence per event)
- `analytics overview|works|audience|money|health|trends [--campaign X] [--range 7d|30d|90d] --json`
- `suggestions list|apply|dismiss [--id] [--campaign X] --json`
- `campaign-trust --campaign X --on|--off|--check --json`, `conduct status|pause|resume --json`

## 8. Lanes (file ownership prevents collisions)
| Lane | Owns | Must not touch |
|---|---|---|
| L1 Spine & conductor | events.py, conductor.py, common.py schema/migrations, agent.py, autopilot.py, slot.py, queue.py, campaign-board/events/trust/conduct CLIs, plists | Swift, analytics/ |
| L2 Analytics | analytics/ package, tracker.py, funnel.py, calibrate.py hook for perf_weights, analytics/suggestions CLIs, tracker fixture | common.py schema (own migrate() only), Swift |
| L3 App | Sources/ClipStudio*, Tests/ClipStudioTests, docs/DESIGN.md | engine/ (reads fixtures only) |
| L4 QA (after L1–L3 merge) | engine/tests/test_ecosystem_e2e.py, fix-ups anywhere with a note | — |
L1's FIRST commit is events.py + the campaign_id migration + the contract fixtures for campaign-board/events, so L2 and L3 build
on real signatures. If L1's code isn't on your branch yet, code against the signatures above with a local shim that has the
same signature, and say so in result.md.
`__main__.py` is shared: append your `add(...)` lines and imports at the END of the relevant blocks only (no reordering), so
merges stay one-line.

## 9. Proof every lane owes
Gate output pasted (full engine pytest + `swift test`), no network in tests (mocks/fixtures), result.md with what's verified vs.
not, and for UI: stills light + dark of every screen and state, viewed and self-critiqued against /taste before finishing.
