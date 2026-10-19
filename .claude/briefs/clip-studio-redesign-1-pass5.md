PASS 5 — same worktree/branch. Sounds tiles + Moments tiles get the same simple ring treatment as Campaigns (pass 4), and
approving a moment becomes one full-screen player with Edit / Approve / Publish in one place.

Yahia (verbatim): "also for the music make it simple like that with length and trendiness score with also the same thing with
our tiles for the 9:16 moments show a activy ring of trendiblity score with a progress shown in a ciruyclar aapple hig sample
book activity ring and simplgy the approve sytem with a full screen with the clip playing in moments within the ui and a way to
edit and approve it n publish it"

## Data truth (checked — do not invent numbers)
- Moments: `moments.score` is the real 0–1 Clip score (shown as 0–100 today, MomentsView.swift:116). There is no separate
  "trend score" for moments — the ring shows the Clip score and is labelled "Clip score" (its help text already says it
  includes trend match). The Clip score floor already exists ("under the Clip score floor") — reuse it.
- Sounds (trending feed, soundintel.feed): rank, rank_change, usage_count, growth, trend history. NO duration field.
  Trendiness = rank percentile in the current chart: `1 - (rank-1) / max(chartCount-1, 1)` (rank 1 = full ring). No rank →
  no ring (dashed empty track), never a made-up value. Show the formula in the ring's .help tooltip.
- Length: trending sounds have none → omit the length (no "0:00", no dash placeholder that looks like data). A separate music
  builder is adding a local music library (tracks with real durations) on another branch; make the tile take
  `lengthSec: Double?` and `trend: Double?` so those tracks drop in later. Do NOT build the library wiring here.

## Build
1. Reusable `ActivityRing` (one component; replace pass 4's `BudgetRing` in CampaignsView.swift and `ProgressRing` in
   Players.swift with it, same look as pass 4's ring): Apple Fitness style — thick round-capped stroke, muted track of the same hue, value 0–1,
   optional centre label, nil value = dashed track only. Sizes ~44 pt on tiles, ~64 pt in the full-screen rail.
   Money green #2BD46A for at/above the floor; below the floor the ring uses text3 grey (not red). Light + dark.
2. Sounds tile (same card surface/grid rhythm as the pass-4 campaign tiles): ONLY title (bold, 2 lines max) · artist (one
   line, text2) · length "0:42" when known · trend ring with "#rank" centred · tiny ↑/↓ for rank_change. Everything else
   (sources, tags, mood/niche/meme/risk chips, usage, rights chip, results, sparkline) moves to a right-side inspector on
   click, same pattern as Campaigns. The rights/usable chip stays visible on the tile ONLY when the sound is NOT usable
   (amber dot + tooltip) — that one matters before picking.
3. Moments tiles (9:16): poster + hook as the title (2 lines) + Clip-score ring (centre = score 0–100) in the bottom corner
   of the card, status as a small dot (approved green / rejected grey). Remove the inline Approve button from the tile; the
   right-click menu keeps Approve / Reject / Find similar for speed. Below-floor moments keep their greyed treatment.
4. Full-screen review player — click a moment tile → a full-window overlay inside the app (not a sheet, not a new window):
   dark scrim; the clip plays LARGE in 9:16, centred, looping, with sound (reuse LoopingPlayer / ClipPlayerCard's AVPlayer);
   no rendered clip yet → play the source segment start…end and show "Not rendered yet" + Render.
   Right rail (one column): Clip-score ring (64 pt) + reason line · Hook text field · Trim (start/end, the existing
   `model.rerender(moment, start:end:hook:)`) · Layout row ONLY if the engine reports layouts (hide it otherwise — layouts
   ship on another branch) · then the actions: Approve (green primary), Publish (secondary), Reject (quiet).
   Publish = the EXISTING guarded publish/queue path (go-live gate, rights gate, dry-run defaults, auto-post guard) — add no
   new posting route and no bypass. Disabled with the gate's reason when a gate blocks it.
   Keys: Space play/pause · ←/→ previous/next moment in the current filter · A approve · R reject · E focus hook ·
   Esc close. Moving to the next moment after Approve/Reject is automatic (review a batch fast).
5. Bug from pass 3: "Format as clip" failure always shows "needs the layouts update" (AppModel.swift ~494, stderr discarded).
   Show the real error: last non-empty stderr line of the job (trimmed to ~140 chars), full text in the job log.
6. Taste: ~/.claude/skills/taste/SKILL.md applies. Money green only for rings, approved dots and primary actions.

## Gates
swift build, swift build --build-tests, swift test (grep "Executed"). Render into docs/screens/redesign/: sounds-light,
sounds-dark, sounds-light with inspector open, moments-light, moments-dark, review-fullscreen-light, review-fullscreen-dark
(a moment with a rendered clip, poster frame showing), campaigns-light (ring swap must not regress pass 4). Read your own
renders before reporting. Commit; no push/merge; no engine/ changes; do NOT quit or relaunch any running ClipStudio.app;
CLIPSTUDIO_HOME sandbox only — the real library under ~/Library/Application Support/ClipStudio is off limits.

## Also in this pass (Yahia, new — verbatim)
"for home and trending tab and live need work they look like the free yt recommend ones whioch is a bunch of slop we dont
wnat or watch and also the cards tiles on the home have no boreeder and look messy like the campgaines aswell"
7. Home tiles = the same card system as pass-4 Campaigns: every Home tile is a bordered card (hairline + soft shadow, equal
   heights per row). "Needs you" / "Ready to post" use the NEW Moments tile from item 3 (poster + hook + Clip-score ring);
   Home's "Campaigns" row uses the pass-4 campaign tile (title · rate · $ left · ring) — delete the old StatusChip /
   CampaignStats / budgetLabel text wall. "Recent sources" become bordered cards too. No bare posters floating on the page.
8. Remove Home's "Trending" row (generic top live streams) for now — what replaces it is pending Yahia's call; do NOT
   redesign Discover or Live content in this pass.
9. Pass-4 regression: with the inspector open at 1440 the campaign grid collapses to one wide off-centre column. Keep ≥2
   columns at 1440 with the inspector open (smaller min tile width while open, or narrower inspector), centred.
Extra renders: home-light, home-dark (all light renders are stale since the pass-4 page/card colour change — re-render
every screen in light at the end and read home/moments/sounds/campaigns).
