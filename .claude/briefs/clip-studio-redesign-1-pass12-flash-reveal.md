# Clip Studio pass 12: reveal zoom (off-crop source text) + on-demand 10s flash edit

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. You are resuming in YOUR worktree
(~/Projects/clip-studio.builders/clip-studio-redesign-1-20261012-132440, branch builder/clip-studio-redesign-1-20261012-132440).
The branch was cleaned since your last run: pass-11 MP4s were removed from history (commits are now 81ec3f6, 0e36913, f66e21b) and
`docs/proof/**/*.mp4` is gitignored. Proof MP4s stay on disk, NEVER committed; commit stills/JSON/README only.
Engine venv only in main checkout: from the worktree's engine/ run `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q`.
Native binaries (gitignored) are present in the worktree: engine/native/personmask/personmask and engine/native/framescan/framescan
(`framescan <video> [--fps 10] [--out scan.jsonl]`, Apple Vision OCR + person share). No push, no merge, never relaunch ClipStudio.app,
real library read-only (`sqlite3 "file:...?mode=ro"`, tests use fixtures/tmp copies), never post/queue/submit anything. Jev only, no paid LLM.
Write result.md EARLY and extend it as you go. Tests green != right: LOOK at stills from the real MP4s and say plainly what looks off.

## Yahia's two asks (2026-10-13)
A. "this clip shows a text on the side that we are clipping off — we want that to show and have motion so it zooms out and reveals that text"
B. "a short 10s edit with flash and big flashes like the kumar edit" — DECIDED: on demand only, flashes land on spoken hits.

## A. reveal_zoom — applies to every edit (30s and 10s), on by default, switchable per campaign edit_style
Real case (verified with framescan @2fps): src_7b43e588b5 (Solved, 1920x1080), moment mom_a8562319dc 1357.91-1388.39 = your pass-11
close_talking render. Speaker says "cognitive reframing" ending ~1370; a title card "Cognitive / Reframing" (black + yellow highlight)
animates in at 1370.0 (absent at 1369.5) on the RIGHT: boxes x 0.58-0.87, y 0.22-0.45, line height 0.11-0.13, and stays on through
the camera cuts until at least 1377.5. Speaker sits x ~0.05-0.45. Our square crop shows only "Co / Re". Noise in the same scan that must
NOT trigger: "02 HEAVEN LUCK" (h 0.02, whole window), "Solved." (h 0.05, whole window), citation footer at y 0.94 (h 0.02, OCR text
churns frame to frame).
1. Detect (engine, deterministic): framescan the moment window (fps 2-4; cache the jsonl per source window). A reveal candidate = text
   that (a) is big: line height >= ~0.07 of source height; (b) has an ONSET inside the clip (absent in the first samples / before onset)
   and persists >= 1.0 s (match boxes across samples by IoU, not by string - OCR text churns); (c) lies >= 40% outside the current
   picture crop; (d) is not covered by the person (framescan `cov`); and (e) matches speech: fuzzy token overlap with words spoken in
   onset-4 s..onset+1 s. If (e) fails but a-d pass, ask Jev (noul: "is this a title/topic card the speaker is referring to, rather than
   a watermark, citation, lower-third name tag or sponsor?") with a floor you calibrate on a few hand cases; log the probability.
   Max 2 reveals per clip, >= 6 s apart.
2. Motion: crop + picture rect animate together. Speaker + text do not fit a square crop (union ~0.82 of source width), so the picture
   OPENS OUT: from the current picture rect/crop to a rect that holds face box + text box + margin (for this source that is the full
   16:9 shot fitted to 1080 wide), eased (cubic in-out) ~0.5 s starting ~0.15 s before text onset so the card animates in on screen;
   hold while the text is up (min 1.6 s, max 3.5 s); ease back ~0.5 s. Never start/end an ease within 0.2 s of a source camera cut; if
   the source cuts during the hold, keep the open framing on the new shot only if the text box is still detected there, else close.
   Zooming out is a downscale, never an upscale: assert it in the run record (scale factor <= 1.0 during hold).
   Must look right in BOTH edit_style.frame square and wide (proof stills in both).
3. Captions during a reveal: drop front captions whose words repeat the revealed text (the card already says it); any other caption
   in the window must sit outside the text box; no depth cards during the open hold (person is small). punch_in/push_in never overlap
   a reveal (reveal wins, punch is dropped and logged).
4. Run record: reveals fired (text, onset, box, speech-match score or Jev p, hold, scale) + candidates skipped with the reason.
5. Tests: detector on fixture jsonl (title kept; watermark, citation, inside-crop text, short-lived text, person-covered text all
   rejected; IoU tracking across churned OCR strings); motion expression shape + ease timing; caption suppression; reveal-off and
   no-candidate clips = byte-identical output to before (regression).
Proof: re-render close_talking (mom_a8562319dc) with reveal on -> docs/proof/pass12/reveal/: stills at ease start, mid-ease, hold,
ease back, plus the same moment in the wide frame. Then run ONLY the detector (no renders) over the moments of 5 other library sources
(mix of Solved, PB Blake, others) and report every reveal it would fire, with a still of each: false positives are the main risk.

## B. 10s flash edit — ON DEMAND ONLY
- Entry: a "Make 10s flash" action on an existing clip in the Mac app (Review / clip detail, next to the existing re-edit actions) and
  the matching engine op/CLI. It creates a sibling edit of the same moment; the 30s clip is untouched. Autopilot, the slot routine and
  the finder NEVER create these (test it). Finder stays 20-58 s.
- Window: 8-12 s inside the parent moment, starting at a sentence start on the hook (or the strongest line) and ending on a sentence
  end. Build <= 5 candidate windows, Jev (choice) picks; titles stay spoken-sentence-only.
- Edit grammar = the Kumar effects pack at 10 s pace (effects.py; reuse, do not re-implement): build_line hook on the opening words,
  2-3 word slams behind the head (depth, existing 70% gate + front fallback), punchline captions for the rest, punch-ins on spoken
  hits; no b-roll montage unless the window has a >= 1.5 s speech gap. reveal_zoom (part A) still applies. Pass-11 depth option B
  (per-card caption relocation) is OFF in this mode; slams keep depth.
- Flashes on SPOKEN HITS (no music in the render; it stays postable, NOT "needs your sound"):
  * small flash: white overlay ~40% peak, 2 frames, fade ~0.12 s, on each slam onset;
  * big flash: full white 1-frame peak + fade from white (fade length from the pack's measured `transitions.fades`, else 0.4 s) on
    the hook landing (first cut after the build line) and on the payoff line (last sentence's stressed word);
  * HARD SAFETY CAP (test it on the per-frame luma of the real output): never > 3 flashes in any 1 s window (WCAG 2.3.1), big flashes
    >= 2 s apart, <= 2 big per clip. Flash params live in the style pack (new `flash` block; Kumar pack gets values), not hard-coded.
  * effects.py today allows only 1 flash at montage start; keep that behaviour for 30 s clips (regression) and add the 10s profile.
- Same HD bar as every render (12-16 Mbps master, upscale guard, QC on decoded frames).
Proof -> docs/proof/pass12/flash/: 10s flash versions of close_talking (mom_a8562319dc) and the pbblake stand-in (src_72d04eaf17
74.35-104.35); per-frame mean-luma JSON + a still at every flash peak frame (prove peak = 1 frame for big, 2 for small) and at each slam.

## Done =
- Whole engine pytest + `swift test` green, re-run by you at the end (report real counts).
- You LOOKED at every proof still. result.md: files changed, detector numbers on the 5-source sweep (fired / false positives), flash
  luma check, what looks off, questions for Yahia. App UI change: one light + one dark screenshot of the "Make 10s flash" action.
