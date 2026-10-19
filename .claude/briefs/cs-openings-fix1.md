# cs-openings fix 1: captions collide with the campaign logo

Your openings pass is reviewed. Frame 0, the face gate, the solo layout and the ringed captions all look right. One regression blocks the merge.

## The bug
The bigger captions (ROLE subtitle 1.12 -> 1.3) now run into the top-right campaign logo ("Solved.", brand.py LOGO_Y=316, right margin 48, 18% width).
The logo spot was picked when 2-line captions ended around y 290; they now reach it.
In your ab.mp4 (new side) the caption overlaps the logo in about a quarter of the frames of clips 2 and 3, from about 36 s to 100 s:
"gets hard", "in front", "obviously", "situations", "for yourself", "narrative", "right around", "situation?", "is there any", "your life", "that either", "or didn't", "regular area?", "things and", "shame or guilt".
Clip 1 is clean only because its caption home sits higher.
Reference sheet (logo corner, 1 frame/s, new side): /private/tmp/claude-501/-Users-y-Projects-true/ffdb8d1f-dd47-4859-92e5-5551adebc59a/scratchpad/openings/logo_sheet.jpg

## Step 0: bring main in first
main moved: cs-payout-data was merged (submit chain, money, yt analytics, tier1, report learn). Run `git merge main` on your branch and resolve conflicts on your side, so the final merge into main is a fast-forward or trivial. Run the full suite after.

## Step 1: fix the collision
Rule to enforce: no caption card's visible ink (text + ring + shadow) ever overlaps the logo box plus 12 px padding. That holds for every layout (full / stack / card), every caption home and every campaign with a top-right logo.
- Keep the captions at 1.3x and centred, in one spot per clip (captions v3 rule: one place, no jumping).
- Keep the logo in one fixed spot for the whole clip. It must never move mid-clip.
- Preferred: place the logo per clip, clear of that clip's caption band. You know the band from the real cards: home plus the tallest card. Put the logo just below the band, but keep it above the right-rail zone (about y 760) and off the face where you can. Otherwise put it above the band if there is room under the platform top UI (about y 200 or more).
- Fallback when neither fits: narrow the caption max width for that clip so the text box ends left of the logo. Keep it centred.
- If you find a cleaner approach, use it and explain why in the report.
- Record features.logo_clear (bool), the minimum gap in px, and the logo y used.

## Step 2: cover_ms wiring
publish.py `cover_fields` already forwards cover_timestamp / cover_image, but the payload still uses the 1000 ms default. Make the post path read features.cover_ms when it is present. That covers the slot/autopilot post path and the submit path if it builds its own payload. Add a test.

## Proof
- Re-render the same 3 moments (mom_39a28580a8, mom_e8ac7c07d7, mom_ef4e4c8889) against a tmp CLIPSTUDIO_HOME copy. Never write the real library.
- New docs/proof/openings/ab.mp4: old | new, as before.
- docs/proof/openings/logo_sheet.jpg: the logo corner of the new side at 1 fps, tiled.
- Measure overlap on the actual rendered frames: caption ink pixels inside the logo box, at every frame or at least 5 fps. Report the count, which must be 0. Also report it for the old renders, so the before/after is visible.
- Tests: unit tests with synthetic cards at several homes (high, mid, low, 2-line, long line), the narrow-width fallback, and the cover_ms payload. Run the full suite from the worktree's engine/ and report passed/skipped/failed.

## Rules
- Work only in your worktree and on your branch. No commits to main, no push, no edits to the real library at ~/Library/Application Support/ClipStudio, and don't touch the running ClipStudio app or its launch agents.
- Write the report in plain language: what changed, the numbers, the risks. Update docs/proof/openings/REPORT.md and result.md.
