# Clip Studio — framing modes: content clips get templates (split, card); full-cam clips keep the normal system (engine)

GOAL (one sentence): every clip is classified as a content clip (game/screen with a webcam inset) or a cam clip (the camera
is the whole frame); content clips render in a template — "split" (cam top / content bottom, hook box on the seam) or "card"
(NipseyRed style) — with spoken captions placed by the v3 + depth logic, cam clips render exactly as today, and slurs never
show in captions or play in audio.

Yahia (verbatim): "we want it in this format to fit like this rather tahn what u did" + "and the cpations are in the middle of
the clip u need to use the same logic we used to add depth and capture the audicne" + "we need diffrent modes so when there is
content it has templets so the half and half i showed u then the other one by nipseyred and then when its a full cam clip just
use the norma system we have for it".

## Names (one per thing — use exactly these in code, CLI, EDL, docs)
mode = "content" | "cam" (what the source is). template = "split" | "card" (how a content clip is framed).
cam panel / content panel = the two picture regions of a template. seam = the boundary between them.
facecam rect = the webcam inset's rectangle in source pixels. hook box = split's white box on the seam. name badge = card's
Twitch glyph + streamer name. slur = a word on the slur list (separate from ordinary profanity).

## The two templates (from Yahia's reference screenshots — 1080x1920 output)
split (his TikTok ref, "What kind of Job makes $3 million EVERY year"):
  - cam panel on top: the facecam rect cropped (trim the overlay's own border a few px) and scaled to the full 1080 width;
    height = 1080*h/w clamped to 38–50% of 1920; if the clamp bites, crop the cam rect's sides keeping the face centred.
    Never letterbox, never black bars.
  - content panel below: the rest of the height, full width, cropped from the source area that EXCLUDES the facecam rect,
    window chosen by saliency over sampled frames (motion + edges + OCR boxes the engine has), static per shot.
  - seam: hard cut, no gradient.
  - hook box: white #FFFFFF rounded rect (radius ~18 px), heavy black sans (the engine's title font), 2–3 balanced lines,
    centred, vertically centred ON the seam, up for the whole clip, inside SAFE (right rail ~140 px, bottom UI ~300 px).
card (NipseyRed CapCut-style ref, "lights on and people watching"):
  - top band (~0–42% of height): the cam feed zoomed to fill the width and heavily blurred (gaussian, slightly darkened)
    as the backdrop.
  - cam card: the facecam rect, sharp, ~64% of frame width, centred horizontally, top at ~9% of height, near-square
    (crop the cam rect's sides to ~1.15:1 keeping the face centred), soft drop shadow, small corner radius (~6 px).
  - name badge overlapping the card's bottom-left edge: Twitch-purple (#9146FF) circle with a white Twitch glitch glyph
    (draw it as vector shapes, no downloaded asset) + the streamer's channel name in heavy condensed caps, #9146FF fill with
    a thick black outline. Channel name from sources.channel / the Twitch URL; no name → no badge, recorded.
  - content panel: from the bottom of the blurred band to the bottom of the frame, full-bleed, same crop rules as split.
  - hook text: white, medium-bold sans, dark soft shadow, 1–2 centred lines, just below the card (~48% of height), up for
    the whole clip.

## Captions (v3 rules stay: shown==spoken, on-time, one spot per clip, in-picture, money-green accent #2BD46A)
- split: spoken captions live in the cam panel — never in the content panel's middle, never across the face box, clear of
  the hook box. Use the depth logic on the cam panel picture (words behind the speaker's head/shoulders when the
  readability gate passes; front fallback in the cam panel clear of the face otherwise). depth_captions default "all".
- card: spoken captions sit in the content panel, one spot directly under the hook text, never over the cam card; depth off
  (no speaker in the content) unless the matte finds a person there.
- cam mode: unchanged — whatever the campaign's normal frame/caption settings produce today.

## Mode + template selection
- mode: run facecam detect; inset found with conf ≥ floor on a landscape source → "content"; face fills the frame / no
  inset → "cam". Measure the floor on real sources and report it.
- template: config `template:<channel>` (per streamer) → else campaign style `edit_style:<campaign_id>`.template → else
  default "split". CLI flag `edit-run ... --template split|card` overrides for one run. Explicit style.frame on a campaign
  still wins for cam mode only.
- Record mode, template, facecam rect + conf and why in the EDL and the render record.

## HARD SAFETY RULE — the real library is off limits (a builder wiped it today)
- Real library: ~/Library/Application Support/ClipStudio. NEVER open, write, sqlite3, migrate or run the engine against it.
  The engine reads CLIPSTUDIO_HOME (clipengine/common.py:4); `db()` migrates schema on open.
- Step 0, before anything else: sandbox home inside your worktree `SBX=$PWD/.sbx` (gitignored), made with
  `sqlite3 "<real>/library.sqlite" ".backup '$SBX/library.sqlite'"` (the ONE allowed touch) and `<real>/media` symlinked in.
  Write a wrapper `engine/sbx` that exports CLIPSTUDIO_HOME=$SBX, refuses to run if the resolved APP_SUPPORT is not under the
  worktree, and execs the engine. Every engine command and throwaway script goes through `sbx`.
- Tests use their own tmp homes. Report the real library's mtime before and after your run and state "real library untouched".

## Context (do not re-derive)
- Engine ~/Projects/clip-studio/engine/clipengine (Python); you are in a git worktree of clip-studio. Tests:
  `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the worktree's engine/ (run slow files one
  at a time; test_flow / test_interrupts / test_render_guard take 1–2 min each).
- Edit pipeline: `edit-run --campaign <c> --moment <id>` (editrun.cmd_edit_run) → editroom.py. Frames today "square" | "wide":
  editroom.py:239 (per-campaign style from config `edit_style:<campaign_id>`), :339 (EDL defaults), :365 (card placement),
  :401, :442-444 (picture-rect filter — ONE definition for render, depth and b-roll: extend it, don't fork it), :451-489 (depth
  cards; depthlook.place at :474), :535 (picture height), :622 (render record). Captions v3: capv3.py.
- Depth: depth.py (Apple Vision matte via native helper engine/native/personmask/personmask — built + executable in main; your
  worktree may need native/personmask/build.sh or a path to main's binary) + depthlook.place + readability gate + fallback.
- Face tracking exists in render.py (track/faces, face_out_box :158, plan :284-287) — reuse it.
- Test sources in the library: Malik src_863fe4f081 ("i wanted to loot him", 60 s, 1920x1080, GTA scoreboard + cam inset at
  about x0-496 y480-795 → content mode), moment mom_c75439d1e6 (29.9–57.5 s); campaign label "malik" (not a campaign row;
  edits.campaign_id="malik"; his edits are free — nothing billing-related). For cam mode use any full-frame podcast source in
  the library (Solved / PB Blake) and prove it renders byte-for-byte-equivalent settings to today (same frame, same caption
  placement) — cam mode must not change.
- Other builders run in their own worktrees (redesign: Sources/ Swift; vibes: style packs). Keep changes additive, new modules
  where possible (e.g. clipengine/facecam.py, clipengine/templates.py). Do NOT touch Sources/.

## Layout library, cycling, capture (Yahia, verbatim: "setup a few diffrent layouts to be able to choose from and cycle thru
## so get research done on the types of layouts and how we can cpature them like that aswell so we have it built into the system")
R. RESEARCH FIRST (≤ 30 min, write docs/layouts-research.md): the layout types top stream-clip / gaming / reaction channels use
   on TikTok, Shorts and Reels in 2025–26 (e.g. split cam-top, split cam-bottom, card over blurred band, floating cam bubble /
   PiP over full content, content-only with face-zoom inserts, side-by-side duo cams, blurred-background letterbox done well,
   full-cam). Per type: what it looks like, when it is used (content kind, cam size, talking vs gameplay), panel geometry in
   % of 1080x1920, text slots, badges, safe areas, real example channels/links. Pick the 5–7 that matter; split and card are
   two of them.
L. Layouts are DATA, not code: a layout = a JSON spec in engine/layouts/<id>.json validated strictly (panels: [{role:
   cam|content|blur_band|cam_card, rect in % of frame, fit rules, crop source, blur, radius, shadow}], text slots: [{role: hook|
   captions, rect/anchor, style ref}], badges: [{kind: twitch_name, anchor}], allowed modes). One renderer reads any spec
   (templates.py). Ship split, card + the other researched layouts as specs; table or config listing them with
   enabled/disabled. "template" in this brief = a layout id.
C1. Choose + cycle: `layout-list`, `--layout <id>` on edit-run; config `layouts:<channel>` = {"pick":"fixed"|"cycle", "set":
   [ids], "fixed": id}; cycle = round-robin across that channel's renders (deterministic, recorded per edit, skips layouts whose
   allowed modes don't fit the clip). Default for a new channel: cycle over the enabled content layouts. `layout-preview
   <source> --all` renders one still per layout (one contact sheet) so Yahia can pick by eye.
C2. Capture: `layout-capture <image-or-video> [--name]` — from a reference screenshot or video (take 3 stills), Claude vision
   (claude-sonnet-5-5, the engine's existing Claude client pattern) proposes a layout spec JSON; the engine validates it,
   renders it on a test source, and saves it disabled until Yahia enables it (`layout-enable <id>`). Prove it by capturing
   his two references and showing the captured spec's still next to the hand-built one. Refs (look at them FIRST, before
   building split/card): /Users/y/Projects/true/.claude/briefs/clip-studio-stack-1-refs/ref-split.png (TikTok split),
   ref-card.png (NipseyRed card), ref-fullcam.png (a full-cam Malik stream = cam mode; note the Spotify-style "now playing"
   widget bottom-left — the cam-mode crop must not include such widgets; record if the stream has background music).

## Build
A. facecam.py: `detect(source_path) -> {rect, conf, frames, reason}`; ~12 sampled frames; face via render.py tracking; the
   static inset rectangle that contains it (straight edges + low temporal variance on its border vs changing content around
   it); no inset → rect None, reason "no_overlay". Cache in sources.signals JSON key `facecam` (additive). Override config
   `facecam:<channel>` = [x,y,w,h]; CLI `facecam <source> [--set x,y,w,h] [--channel]`. On Malik: within ±12 px of the true
   inset (measure the truth from frames yourself; report both).
B. templates.py: split and card geometry + the filtergraph pieces, wired into editroom via the one picture-rect definition.
C. Captions placement per template (above). D. Mode + template selection (above).
E. Slurs: slur list (n-word + spelling variants incl. -a/-er/-az/-uh endings, plus other common slurs) separate from profanity.
   Captions ALWAYS mask slurs as first letter + asterisks ("n****") regardless of campaign profanity policy. Audio: mute the
   slur word span (word timings ±40 ms, short fades) by default; config `slur_audio` = "mute" | "keep" (default mute). EDL
   records profanity.found, slurs.found, slurs.masked, slurs.audio. Fix detection so this clip's profanity.found is real
   (today it lists only fuck/fucking and the n-word showed raw).
F. Re-render Malik in the sandbox, both clips:
   - clip 1 src_863fe4f081 / mom_c75439d1e6 (GTA, cam inset left-middle) in split AND card.
   - clip 2 src_5cbf5b5f26 / mom_d6cd6a485d (Dead by Daylight, 37 s, cam inset bottom-left at about x0-344 y594-860 of
     1920x1080; teammate "nipseyred" is in-game) in split AND card.
   - one `layout-preview --all` contact sheet per clip (every enabled layout).
   - one cam-mode render of a podcast moment to prove no change.
   `sbx edit-run --campaign malik --moment <id> --rounds 1 --layout <id>`.

## Proof (in the report, with paths; copy stills to docs/proof/modes/ in your worktree)
- Per template: 4 stills (0.5 s, the slur moment, mid-clip, last second) + contact sheet; the final.mp4 paths in $SBX.
- Measured, pass/fail with the number: no black bars (mean luma of the 40 px edge rows of every panel > 12 on every sampled
  frame — card's top band counts as a panel); face detected in the cam panel/card on ≥ 90% of sampled frames; every spoken
  caption bbox inside its allowed region and ≤ 15% overlap with the face box (depth cards excepted — report depth vs fallback
  counts and why); split hook box centre y within ±10 px of the seam; card name badge present with the right channel name;
  slur masked in every caption box; audio RMS over the slur span ≥ 30 dB below the 1 s around it; mode detection correct on
  Malik (content) and on the podcast source (cam).
- Gates: unit tests for facecam detect (synthetic inset frame + full-frame face), split/card geometry (panel math, clamps,
  no bars), selection precedence, slur masking + audio mute; full pytest green (per-file ok); `git diff --stat main -- Sources`
  empty; commits on your branch; NO push, NO merge, NO launchctl, NO writes outside your worktree.
- State plainly anything not done or not proven.
