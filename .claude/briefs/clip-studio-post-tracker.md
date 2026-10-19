# Clip Studio — fix the dead Post button + live post tracker

FIRST: this worktree must start from the redesign branch, not main:
`git reset --hard b6331cb` (pass 9 head of builder/clip-studio-redesign-1-20261012-132440). Another builder is
running pass 10 (captions/types engine) on that branch in parallel — stay out of captions/cliptype/moments/depth
files; touch only the posting path, analytics and their UI so the merge is clean.

## 1. Bug: Post does nothing (Yahia, 2026-10-13 ~01:50)
Observed: he clicked post on an approved clip in the open app (pass-7b build) → nothing visible happened.
Real library has 0 rows in `posts` (not even dry-run), Upload-Post history = 0, slot log says
"no approved clip waiting" at 16:30 and 21:00. Only app log line near then: AVPlayer err -12852/-12780 at 01:49.
So the click never reached `clipengine publish` (publish.py cmd_publish always inserts a posts row, even dry-run).
- Reproduce in a CLIPSTUDIO_HOME sandbox copy of the real library (copy read-only via sqlite3 "file:...?mode=ro"
  .backup). Trace the Swift Approve/Post action → engine call → result handling. Find why it silently no-ops
  (unwired action, swallowed error, gating like can_publish/rights/campaign rules/accounts.check_publish dying
  with the message never shown, approved state not persisted so the slot sees nothing, etc.).
- Fix it, and NEVER fail silently again: every post attempt shows a visible result (posted / scheduled for X /
  dry-run because go-live is off / refused because <reason in plain English>).
- Go-live gate stays (config post.golive off = dry-run). Do NOT flip it, do NOT send a real upload. Prove with the
  dry-run path end to end + a mocked live path in tests. Yahia flips go-live himself.

## 2. Live tracker for posts the app makes
- Track only Clip Studio posts (posts table, dry_run=0). Engine: metrics snapshot already exists
  (publish.py cmd_metrics_snapshot via GET /api/uploadposts/post-analytics/{request_id}; hourly <48h then daily).
  Add: job status polling (submitted → published/failed + platform URL), the scheduler (LaunchAgent plist written,
  NOT loaded — Yahia approves loading), and account-level stats from GET /api/analytics/default (TikTok
  eliteclipperzz1 is the only connected account; it currently reports 0s — show that honestly).
- App: a "Posted" tracker view (lives in For you → Posted tab already in the nav): per post views/likes/comments/
  shares/avg view %, sparkline over snapshots, status, link out, last-updated time, auto-refresh while open.
  Empty state when nothing posted yet. Never fake or interpolate numbers.
- The analytics JSON shape for per-post is unverified (e2e.py notes it) — write the parser defensively, and test
  with fixtures; read ONE real GET of account analytics to confirm that shape (GETs are fine, no POSTs).

## Rules
Real library read-only; writes only in sandbox. Don't quit/relaunch ClipStudio, no package.sh, don't load the
LaunchAgent, never push, never merge to main, no real uploads. Commit on this branch.
Gates: swift build, swift build --build-tests, swift test, engine pytest on touched tests. Renders of the Posted
view (empty + fixture-filled, light+dark, 1280). Report plain English, verdict first: root cause of the dead button
in one sentence.
