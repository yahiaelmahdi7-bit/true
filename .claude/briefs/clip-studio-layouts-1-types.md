PASS — CONTENT TYPES: one router, a recipe per clip type (ENGINE, same worktree/branch, after fix1).

Yahia (verbatim): "we need a divers system for all these modes and diffrent clip types from streamers streaming content or just
irl streams or yt content n so on"
His decisions (2026-10-12): types first = Just Chatting/reaction, YouTube videos/vlogs, podcasts (2+), IRL — plus gaming+facecam
(fix1). Detection = AUTO on every clip + his override in the review player, and the override teaches that channel.
Reaction layout = CAM TOP, content bottom, 50/50 (same as gaming split).

Today: layoutsel knows 2 modes (cam|content via facecam inset) and round-robins layouts per channel — so IRL, reaction, podcast,
YouTube all land in one of two buckets and the format looks random. And live.py renders through a different path than
edit-run (the zoom bug). Both end here.

## Build (engine/clipengine/, additive; keep fix1 behaviour for gaming_cam)
1. Types (ids fixed): gaming_cam, gaming_nocam, just_chatting, reaction, irl, podcast, yt_talking, yt_edited, other.
2. Recipes as DATA (one table, e.g. recipes.py dict or recipes.json), per type: layout, crop tracker, zoom policy, caption zone,
   hook policy, b-roll allowed, length range. Starting values:
   - gaming_cam → split cam top 50/50 (fix1). No zooms. Captions on the seam/game half.
   - gaming_nocam → full-height crop following the action (centre-weighted, avoid HUD/minimap/widgets) or blur-fit if the
     action is wide. No zooms.
   - just_chatting → fullcam 9:16 face-tracked crop; punch-in only on the streamer's own face, only while THEY speak, ≤1 per 6 s.
   - reaction → split CAM TOP, watched content bottom 50/50 (content crop = the player/browser region, not the whole desktop).
   - irl → full-frame 9:16 crop following the main person (smooth tracker, light stabilise), NO zooms (camera already moves),
     captions lower-middle above the platform UI safe zone.
   - podcast → speaker-follow crop switching on diarised turns (switch at turn boundaries, never mid-word); punch-ins on the
     speaking face OK; when both react at once allow a stacked two-face split.
   - yt_talking → face-tracked crop, emphasis punch-ins on the face only.
   - yt_edited → keep their edit: fit 9:16 (blur-fill or card), no added zooms/b-roll; captions OFF when burned-in text exists.
   - other → current safe default (blur-fit, no zooms).
   EVERY zoom anywhere = aimed at a face box of the person speaking; never a centre-crop punch. Slur mask/mute on every type.
3. Classifier `cliptype.classify(source, moment)` → {type, confidence, signals, why}. Rule-first from MEASURED signals:
   platform + live category (Twitch/Kick "Just Chatting", "IRL", game name), YouTube metadata (category, title, chapters),
   facecam inset (facecam.py), face count + face-area ratio over sampled frames, global camera motion (frame-diff/flow → irl),
   shot-cut rate per minute (→ yt_edited), diarised speaker count (→ podcast), video-player/browser region in frame
   (→ reaction), burned-in caption band. Ambiguous (top-2 within a margin) → Jev `choice` with a no-match option; state = the
   raw signals only, never your guess. Classify PER MOMENT (streamers switch mid-stream), cache per source time-range.
   Channel prior: his override adds a prior for that channel (+ weight), never a hard lock; log every override.
4. ONE path: live._render, edit-run, render_moment, finder-run and VOD all go through classify → recipe → render. Test: same
   moment → identical recipe from the live path and the edit path.
5. CLI: `clip-type <moment> [--set TYPE] --json` (signals, type, confidence, why; --set = override + channel prior + marks the
   clip for re-render) and `clip-types --json` (types + recipes for the UI picker). Contract in docs/clip-types.md for the
   Swift "Format" picker in the review player (later pass).

## Batch reformat — every face-cam + content clip (Yahia, verbatim: "we need to get all the camera clips with conteent to be
## sorted so the face cam is rescaled to fit top half and have cotnetn reszied with logic to fit under")
6. Facecam detector regressions FIRST (Claude ran `facecam` on every real source, 2026-10-12 16:0x; frames checked by eye):
   - FALSE POSITIVES: src_7b43e588b5 (solved--rKZe8TEOik) and src_fda8b8256f (solved-UDO8FWVDR5g) = Mark Manson "Solved",
     ONE talking head on a plain wall + on-screen text cards → detector said content, conf 1.0, rect = the man himself. These are
     yt_edited/yt_talking, never a split. Rule to add: a face-cam inset is small (≲25% of frame), touches a corner/edge, has a
     stable border over time, and the area OUTSIDE it is different content (game/screen/video) — not one continuous scene.
   - MISS: src_bae6151f36 (Malik "JUMPSCARE", Dead by Daylight) — face cam bottom-left, small + dark + headphones → "no_face".
     Fix with corner-candidate search (stable rectangular inset across sampled frames) + a lower face threshold inside it.
   - Errors: src_2860e28c3e (live recording) → TypeError path None (live sources keep media in chunks — read those);
     s1 = pytest junk row (skip it, report it, never delete).
   These 9 real sources = permanent labelled regression cases (labels: Malik sources + live = gaming_cam; solved-* = podcast/
   yt_talking/yt_edited by your eye — write labels before running).
7. Content panel "resized with logic" (bottom half under the cam): per SHOT choose
   - crop-to-action: centre on where motion/saliency is (crosshair, character, the thing that changes), excluding the cam inset
     and widgets (Spotify/now-playing, alerts) — when the action fits a 1080×960 window;
   - fit-with-blur-fill: scale the whole content to the panel width over a blurred copy — when important content spans the
     width (scoreboard, menu, text, two players far apart, a video being reacted to).
   Never crop through on-screen text. Smooth (no jitter) and switch only at shot changes.
8. `reformat --types gaming_cam,reaction [--source ID] [--apply]`: lists every moment/clip whose source classifies as those
   types, renders each in the recipe into the sandbox, and writes ONE contact grid docs/proof/types/reformat-grid.png (old vs new
   per clip). Without --apply it never touches the real library. With --apply (only after Yahia says yes — NOT in this build):
   back up the real library first, write NEW edits/clips, keep the old ones, never post.
   In this build: run it (no --apply) on the fresh read-only copy; today's set = Malik's 7 moments across src_5cbf5b5f26,
   src_863fe4f081, src_a6e2576a71, src_bae6151f36, src_2860e28c3e (+ any new live moments). READ the grid.

## Proof (honest, on unseen data)
- Build a labelled set BEFORE running the classifier: ≥3 moments per type. Use real library sources (copy the real library
  read-only into <wt>/.sbx-types: Malik = gaming_cam, Mark Manson / PB Blake = podcast) and download short public samples with
  yt-dlp into the sandbox for missing types (an IRL stream VOD, a reaction stream, a Just Chatting stream, a YouTube vlog, an
  edited YouTube video). Write labels to docs/proof/types/labels.json first, then classify; report the confusion matrix and
  every miss, no tuning on the test set after seeing it (if you tune, add a fresh held-out set and report that too).
- Render 1 clip per type with its recipe → docs/proof/types/<type>.mp4 + 4-still contact sheet + measures (zoom count, face in
  frame %, captions over a face = 0). READ every sheet; fix and re-render anything that looks wrong.
- Downloads are test material in the sandbox only; never post, never write the real library.

## Gates
Full pytest green (file by file fine) + new tests: recipe lookup, classifier rules on fixture signals, Jev only on ambiguity
(stubbed), override → channel prior, live vs edit path parity, no centre-crop zoom anywhere. Commit; no push/merge; never quit or
relaunch ClipStudio.app; never touch the live recorder (pid 83292) or its files.
