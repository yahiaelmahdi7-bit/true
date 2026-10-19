# Clip Studio — two-speaker podcast layout ("stack") + depth on

Repo: ~/Projects/clip-studio (engine = Python in engine/, venv engine/.venv). Work in your worktree branch only. Do NOT merge, push, or touch the installed ClipStudio.app. Do NOT change config post.golive or autopilot.pause in the real library.

## Goal
Podcast clips (campaign cmp_6fe50dcdb4, "Solved w/ Mark Manson", 1080x1920) must be able to show BOTH participants when the conversation is between two people, instead of only the face-tracked crop of one.

## Build
0. CRITICAL GAP FIRST: autopilot renders via autopilot.cut_one -> agent._render -> render.render_moment, which NEVER applies depth captions; depth exists only in the edit-room path (editroom.py / editrun edit-render, captions.prepare + decide_depth_b). So config edit_style:<cid>.depth_captions has no effect on autopilot clips. Wire it: render_moment (the autopilot path) must honour editroom.edit_style(c, cid)['depth_captions'] for the moment's campaign and run the same depth caption decision (option B). Default "off" behaviour must stay byte-identical. Test it.
1. New podcast layout `stack`: 9:16 frame split into two panels (top/bottom, ~50/50, thin seam). Each panel is a face-tracked crop of one person from the wide/two-shot source. Reuse existing face detection (render.face_path / face_anchor / group_box, depth personmask helper) — don't add new deps.
2. Selection per shot (where render picks crop/fit/punch): use `stack` when the shot shows 2 people side by side AND both speak inside the clip window (back-and-forth). Single speaker close-up stays `crop`. Active speaker panel may get a subtle emphasis (optional, keep tasteful). Record the decision + reason in clip features like other layouts.
3. Captions: home on the seam between panels. Depth captions (captions.py decide_depth_b, Pass 11 option B) should run per panel where possible; when a card can't pass, fall back front at the same spot (existing behaviour). Never cover a face.
4. Campaign overlay (render.overlay_graph) must still work with `stack` (credit under captions; move it if it collides with the seam).
5. Tests in engine/tests for selection logic + filter graph; full engine suite must stay green (baseline 1071 pass / 1 skip).

## Proof (required)
- Sandbox only: set CLIPSTUDIO_HOME to a dir with a `sqlite3 .backup` copy of ~/Library/Application Support/ClipStudio/library.sqlite and symlinks to its cache, models, fingerprints, media/downloads (NOT media/clips). In the copy set config edit_style:cmp_6fe50dcdb4 = {"depth_captions":"all"}.
- Render 4 Solved moments: mom_8f399fa883, mom_6ef3c64af7, mom_9358c25556, mom_4dc7ab17af through the AUTOPILOT path (agent._render / render.render_moment as cut_one calls it), e.g. `python -m clipengine render --moments <id> --out-dir <dir> --name <x>.mp4` once render_moment honours edit_style. Confirm each clip's features contain a depth record with depth share %.
- Put renders + a contact sheet of stills (several timestamps each, incl. a two-person moment) in docs/proof/two-speaker/ with a README: verdict first, per clip: layouts used, depth share %, any fallback reasons. Look at your own stills before claiming done.

## Done =
tests green, proof README + stills, short summary of files changed. Commit on your branch.
