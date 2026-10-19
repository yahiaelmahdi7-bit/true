# cs-posted-tiles — Posted page = real post tiles with small analytics (Yahia 2026-10-14 19:08)
Yahia: "lets get the pages cleaned up where to show real tile cards of the post and the analytics under ismall so we know what we posted and where".
Screenshot of today's Posted tab: ~/Library/Application Support/True/ScreenshotTray/shots/ (latest, 19:08) — Home > Posted · 1. Problems seen:
- The post is a text row "Choosing how you react to your own emotions. Yes" (stray trailing "Yes" from transcript title) + "Instagram" "Youtube" plain words + PUBLISHED + Open. No thumbnail, no links per platform.
- Metrics are huge em-dashes (VIEWS/LIKES/COMMENTS/SHARES/AVG VIEW/NEEDS 2+ CHECKS) — loud and empty.
- "Account totals" shows a TikTok account (all zeros) though Solved posts go to Instagram (clipfarmsolvedmark.clips) + YouTube (Elite-Clipperzz / @clipfarmsolvedmark).
You are in a builder worktree of ~/Projects/clip-studio (Swift app Sources/ClipStudio*, engine engine/clipengine). Real data: post_261447fffa (clip_0954e02e7d) IG https://www.instagram.com/reel/DeemQcxEegf/ + YT https://www.youtube.com/watch?v=_MqxD5EJJYQ; campaign_submissions has both as submitted (by hand).

## Build
1. Posted = a grid of TILE CARDS, one per post (newest first): 9:16 thumbnail (clip poster/thumb; play on hover or click opens the mp4), clean title (strip trailing filler like "Yes"/"Yeah"; prefer the post's written hook/title), posted time (relative + exact on hover), campaign name, and one small chip PER PLATFORM with the account handle that opens the live post URL. Submission state per platform (Submitted ✓ / Not submitted / Expired) small.
2. Under each tile, SMALL analytics per platform: views · likes · comments · shares (compact numbers, small type). No data yet = one quiet line ("First numbers after the next check, ~HH:MM"), never big dashes.
3. Account totals: only the accounts we actually post to (from posts/profile handles), per platform, small; hide accounts with no posts. Remove the TikTok-zeros block unless TikTok has posts.
4. Wire to real data (posts, post_live, metrics/metric_snapshots, campaign_submissions, Upload-Post per-post analytics endpoint already used by tracker). No fake numbers.
## Process
- Read ~/.claude/skills/taste/SKILL.md and the existing app design tokens first; match the app's dark style; v1 must pass /taste.
- STILLS FIRST: render screenshots of the new Posted page with the real post (scripts/shoot*.sh pattern) into docs/proof/posted-tiles/ — 1 post and a mocked 6-post state (mock only in the screenshot fixture, clearly separate from real data). Do NOT install or replace ~/Projects/clip-studio/ClipStudio.app — Yahia OKs stills first.
- UI copy plain + short, no raw ids/codes. `swift build` + `swift test` + engine pytest (baseline ~1372 passed / 3 skipped) green. Commit on your branch.
## Rules
Don't touch main, push, post, submit, flip post.golive/autopilot.pause, or install the app. Done = stills + REPORT.md in docs/proof/posted-tiles/.
