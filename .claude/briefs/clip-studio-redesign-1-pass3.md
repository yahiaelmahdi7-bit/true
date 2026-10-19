PASS 3 — same worktree/branch. Source tile actions: left-click gives the actions, and "Format as clip" joins "Find clips".

Yahia (verbatim, with a screenshot of the Library → Sources grid showing the right-click "Find clips" menu on a Twitch clip):
"also the find clips should not just be find clips it should be clip or format as a clip and also when i click it i need to
right click to get the find clips button rather than just left click it"

Today (LibraryViews.swift sourceTile ~:62-77): left-click only selects (`onTapGesture { model.selectedSource = s.id }`); the
actions are hidden in a right-click `.contextMenu { Button("Find clips") }`; the caption's "Clip" button shows only when the
source has 0 moments.

## Build
1. Two actions, one name each, used everywhere (tile, context menu, inspector, banners):
   - "Find clips" = search the source for moments (today's model.clip(s) → enqueuePipeline).
   - "Format as clip" = take the WHOLE source as one clip and format it (layout system: split/card for content clips with a
     webcam inset, normal frame for cam clips). Engine call: `clipengine edit-run --campaign <C> --source <id> --whole`
     where C = the source's bound campaign_id, else its channel (e.g. "designedbymalik" → use "malik" if a campaign label
     with that name exists in edits, else the channel), else "own". `--whole` is being added on the layouts branch — if the
     engine rejects the flag, show the banner "Format as clip needs the layouts update" (no crash, no silent no-op).
2. Left-click on the poster opens the actions: on hover the poster shows two buttons over a scrim — for sources ≤ 90 s
   "Format as clip" is primary (money-green) and "Find clips" secondary; for longer sources "Find clips" primary and
   "Format as clip" hidden (a 20-min video is never one clip). Clicking the caption/title area still selects the source
   (timeline below). Keyboard: Return = primary action on the selected tile.
3. Right-click keeps a context menu with the same actions (Format as clip only when ≤ 90 s) + "Reveal in Finder".
4. Remove the 0-moments-only "Clip" caption button (the hover actions replace it).
5. After an action starts: the tile shows a progress state (spinner + "Formatting…" / "Finding clips…"), driven by the
   existing job/pipeline state — no fake progress.

## Gates
swift build, swift build --build-tests, swift test (grep "Executed"), re-render sources-light/dark (+ a hover-state still of a
short Twitch tile showing both buttons) into docs/screens/redesign/. Commit; no push/merge. Do NOT quit or relaunch the running
ClipStudio.app (Yahia is using a build from this worktree). No engine/ changes.
