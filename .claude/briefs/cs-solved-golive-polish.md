# cs-solved-golive-polish — Solved branding, marketing captions, US-time slots (Yahia 2026-10-14)

You are in a builder worktree of ~/Projects/clip-studio, branched from main AFTER the clipfarm integration merge (per-platform lanes/texts from cs-clipfarm-submit are already in slot.py / autopilot.py — build on them, don't undo them). Engine: engine/clipengine.

Yahia approved the 4 queued Solved clips but wants, before posting:

## 1. Logo + end line (on every Solved clip)
- Logo: ~/Projects/clip-studio-research/solved-brand/solved_logo.png (white "Solved." wordmark, transparent, 372x91, cut from an official episode's quote card). Small, top-right corner, whole clip, ~18% of frame width, inside platform safe zones (clear of IG/YT right-rail buttons and top UI), slight soft shadow so it reads on light backgrounds (Solved's set is pale pink/beige).
- Use the existing hook: `render.campaign_overlay(s)` reads campaign rules `overlay_path` + `placement`. Copy the PNG into the app's campaign assets folder (APP_SUPPORT/campaigns/<id>/) and set it on campaign cmp_6fe50dcdb4 via a migration/CLI step that is idempotent — but in the proof run use a SANDBOX home only. Write the one command that sets it on the real library in your report; do NOT run it on ~/Library/Application Support/ClipStudio.
- End line: last 2.0 s of the clip, centred lower-third: "Full episode:" / "Solved with Mark Manson" (two lines, house caption font, white with the same outline/shadow as captions). Make it a campaign-rules field (e.g. `end_card: {lines:[...], seconds:2}`) so other campaigns can use it; captions must not overlap it (shift or end captions before it, or move the end line — no collision).
- Must not break: depth captions, stack/card layouts, caption_readability, the QA gate.

## 2. Post text = written hook + CTA + required tags, different per platform
- Today the text is the first spoken line + tags ("It's when I've, I feel like I've failed people @solvedpodcast @markmanson"). Replace with: one-line hook true to what is said in the clip (no clickbait — Clip Farm rejects mismatches), optional single emoji, blank line, CTA naming the show + required tags, e.g. IG: "Why failing people hurts more than failing yourself 👀\n\nFull episode on @solvedpodcast with @markmanson"; YT: different hook wording + "@solvedpodcast @iammarkmanson" (+ a YouTube title ≤ 70 chars, no hashtags spam).
- Generate with the existing hook/title machinery (find it; reuse faith gate / tag_check / per-platform variant code from the submit merge). Jev for selection/verification where a judgment is needed; no new paid API.
- Hard checks (tests): every required tag present per platform (editroom.tag_check), IG ≠ YT text, hook faithful to transcript words, profanity censored like captions (f***), length limits per platform.

## 3. Slots pinned to US Eastern prime time
- The Mac's clock is Asia/Dubai. slot.py uses local wall-clock (`time.localtime`), so 12:00/16:30/21:00 fire at 04:00/08:30/13:00 New York. Make slot times timezone-aware: config `post.tz` default "America/New_York", slots 12:00 / 16:30 / 21:00 in that zone (= 20:00 / 00:30 / 05:00 Dubai). Fix every place that compares slot times or computes "today" (posts_today, day0, launchd calendar at slot.py ~l.178 — launchd StartCalendarInterval uses the Mac's local time, so convert NY→local and handle DST changes, e.g. re-render the plist daily or schedule by UTC).
- Tests with a frozen clock across a DST boundary.

## 4. Mac awake for overnight slots
- Content Rewards needs the submit within 30 min of posting, so the Mac must be awake at 00:30 and 05:00 Dubai. Add a user LaunchAgent (no sudo) that runs `caffeinate -s` (prevents system sleep ONLY on AC power) while the Solved campaign is live/golive=1; install/uninstall via the clip CLI; document that the lid must stay open or on an external display (Apple Silicon sleeps on lid-close regardless). Do not install it on the real machine — report the one command.

## Proof
- Sandbox CLIPSTUDIO_HOME (copy /tmp/cs-tune-home if present, symlink models + media; NEVER write ~/Library/Application Support/ClipStudio). Re-render mom_39a28580a8 and mom_acf19653bf with CLIP_PIPELINE=v2 CLIP_VERIFY=1 CLIP_TOOLS_EXTRA=caption_readability → docs/proof/solved-brand/ab.mp4 = synced side-by-side VIDEO, old vs new (no still grids). View frames yourself at 1 s, mid, and last 2 s (logo + end line visible, captions not colliding).
- Dry-run the slot step for one queued clip in the sandbox: print the IG and YT post text + title + scheduled NY/Dubai times. Nothing posted.
- Full suite: `cd engine && env -u CLIP_PIPELINE ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q -p no:cacheprovider` (report baseline you started from and final counts). Commit on your branch.

## Rules
- Settled, don't reintroduce: no word punch-in zooms, no pop/boop SFX, no scrim box, no music on Solved, captions spoken-only and on time.
- No location faking / proxies of any kind.
- Don't touch main, push, post, submit, flip post.golive or autopilot.pause, or install anything on the real machine.
- Done = 1-4 working with tests, ab.mp4 watched, docs/proof/solved-brand/REPORT.md in plain English incl. the exact commands Yahia/I run to apply it to the real library.
