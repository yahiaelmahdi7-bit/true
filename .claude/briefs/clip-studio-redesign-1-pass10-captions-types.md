# Pass 10 — one clean caption system + type-driven finding & editing

Yahia (2026-10-13): captions = look/readability bad, too many modes in the code, depth effect flickers.
Finding: **clip TYPE decides the edit** (detect type → that type's moment rules + its edit style automatically).
Theme = **vibe / style packs** (look layer on top of the type's edit).

## 0. First: merge the types branch
`git merge builder/clip-studio-layouts-1-20261012-140934` into this branch (podcast detection 12/15, speakers.py,
playerregion.py, needs_review/tested flags, docs/clip-types.md). Resolve conflicts; gates green before step 1.

## 1. Captions: ONE system
- Audit every caption path (v3 captions, depth captions/depthlook, trendedits styles, any per-style renderers) and
  collapse into one module: `captions` = layout engine + a style table (data, not code branches). Delete dead paths.
- Settled rules (do not change): spoken-only words, on-time (word timing), ONE spot per clip, inside the picture,
  money-green accent. Never cover a face, facecam or the gameplay focus (use bounds/deadzones that exist).
- Readability: size scales with frame, min contrast via stroke/shadow, max 2 lines, max ~3–4 words per card,
  never a dangling single word, safe-zones for TikTok/Shorts UI.
- **Depth effect: no flicker.** Decide depth ON/OFF per clip (or per stable shot), never card-by-card. If a shot
  can't hold depth for its whole length, that shot uses normal captions. Prove on the 4 depth samples
  (close_talking had 27 depth / 41 fallback cards → report switches per clip before/after; target ≤1 per shot).
- Proof: before/after stills + contact sheets for each clip type, light on mobile-UI safe-zone overlay.

## 2. Type-driven finding + edit
- A per-type profile table (data): for each type in docs/clip-types.md → moment rules (window length, what Jev
  scores for: podcast = a complete exchange/claim+payoff; gaming_cam = action spike + reaction; just_chatting/
  yt_talking = complete thought; reaction = reaction beat after the stimulus …), layout/reformat (existing grid),
  zoom rules (zoom only on a speaking face, NONE on gaming/IRL/content layouts — settled), caption placement, pacing.
- Jev scoring prompts become type-specific (still Jev, Claude off). Untested/needs_review types → profile marked
  "untested", cards say "needs your eye".
- Fix pass 9 issues while here: titles must be complete sentences (offer Jev only complete sentences); the clarity
  gate is too strict on single-speaker/vlog motivational content — loosen per type.

## 3. Vibe packs on top
- A vibe pack = look layer only (caption style row, colour accent, transitions, in-app sound slot — NO music).
  Type sets structure; pack sets look. Build the pack format + 2–3 starter packs clearly marked DRAFT;
  Yahia picks the real ones from the vibes shortlist sheets
  (~/Projects/clip-studio.builders/clip-studio-vibes-1-20261012-131238/docs/proof/vibes/) — don't decide for him.

## Validation
- Per type: render one real clip in a CLIPSTUDIO_HOME sandbox, contact sheet + stills in docs/proof/pass10/.
- Moment finding per type vs pass 9 on the held-out split (do not refit on it). Honest numbers; say if worse.

## Rules
Real library read-only; sandbox writes only. Don't quit/relaunch ClipStudio, no package.sh, no LaunchAgent,
never push, never merge to main. Commit on this branch. Gates: swift build, --build-tests, swift test, engine
pytest (test_facecam clamp failure is pre-existing — fix it if trivial). Report: plain English, verdict first.
