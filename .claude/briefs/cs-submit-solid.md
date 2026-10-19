# cs-submit-solid — posting + Content Rewards submit must never silently miss the 30-min window

Repo ~/Projects/clip-studio (engine/ Python + Sources/ClipStudio Swift app). Branch from main. Do NOT push, do NOT install LaunchAgents on the real machine, do NOT flip live config.

## Incident (2026-10-17/18, real data)
4 approved Solved clips posted (13:48 and 00:58 Dubai). All 4 Content Rewards submissions EXPIRED. Root cause: ClipStudio.app was not running.
- `submit.sync` (engine/clipengine/submit.py:~137: polls Upload-Post for live URLs into post_live, adds ledger rows, expires) is only driven by the app (AutoSubmit.swift tick). App down -> 00:58 posts never got post_live rows; running `clipengine submit-sync` 13 h later added them instantly.
- The actual click (AutoSubmit.swift process()) needs the app's logged-in browser. App down -> nothing submits; rows expire.
- Posting (conductor/slot LaunchAgents) kept running regardless -> clips burned with no submit.

## Build
1. Engine drives sync: conductor tick AND right after every live post (autopilot.post_phase / slot.post_step) call submit.sync; also add a fast follow-up (e.g. slot/conductor re-sync every ~2 min for 35 min after a post, or a dedicated short-interval LaunchAgent plist generator `submit-install` like slot-install — generate + test, don't install).
2. Submitter heartbeat: app writes config `submit.heartbeat` (unix ts) every tick. Engine `submit.healthy(c)` = heartbeat < 3 min old and kill switch off.
3. Post gate: post_phase / slot live post REFUSE to post to a campaign with a submit window when the submitter is unhealthy; one plain event ("Not posting: the submitter isn't running — open Clip Studio") + macOS notification (osascript, once per hour). Clip stays approved/ready for the next slot.
4. Keep the app alive: `app-install` plist generator (LaunchAgent, KeepAlive + RunAtLoad, opens ~/Projects/clip-studio/ClipStudio.app or packaged path) — generate + print the `!` commands for Yahia; don't load it.
5. At-risk alert: any ledger row pending/needs_you with <15 min left -> notification + event (engine side, so it fires even if app is wedged).
6. Watchdog: `clipengine submit-health` prints heartbeat age, pending rows + minutes left, last submit result.
7. Tests for all of the above (fake clock, fake fetch). Full suite must stay green (baseline main: 1476 passed / 2 skipped). swift build must pass.
8. Proof: docs/proof/submit-solid/REPORT.md — sandbox run showing: app heartbeat stale -> post refused + notified; heartbeat fresh -> post -> sync adds ledger row within one tick -> app submits (or fake submit). Plain English, short.
