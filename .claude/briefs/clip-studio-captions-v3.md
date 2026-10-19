# Clip Studio — quality-fix1 pass 2: live proof + captions v3 (Yahia's review of the Kumar depth render)

You are resuming in the SAME worktree/branch as quality-fix1. Your fix1 code stays; this pass (A) runs the live proof you
skipped and (B) implements Yahia's caption review. Rules unchanged: tmp library/home only (NEVER the real library at
~/Library/Application Support/ClipStudio), never relaunch ClipStudio/True.app, never push, commit on your branch only.
Tests: `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the worktree's engine/.

## What Yahia saw (render /private/tmp/kumar-home/pack-wide.mp4, plan pack-wide.json + .mp4.meta.json)
"Nice, I like the quality" — but:
1. **Invented text.** Card 0.00–2.12 shows "THE CAPITAL / EXCUSE" (from the AI hook "The capital excuse is dead in 2026.")
   while he says "But again, with prop firms, you do not need thousands". "capital" is first spoken at ~14.7 s.
   Cards also split phrases into fragments that read invented: "BEING SAID, AFTER", "KILL THIS / FIRST", "IS NOT / ONE".
2. **Late text.** Cards sit on a fixed 1.2 s grid (t0 = 8.48, 9.68, 10.88, 18.08, 19.28 …), not on words. Measured:
   THOUSANDS OF DOLLARS starts 0.69 s after "thousands"; $3,000 starts 0.43 s after "$3,000" (said 9.25); others drift EARLY
   (-0.61, -0.65). One card (YOU, EVERY SINGLE) is 2.3 s off.
3. **Jumping.** Front boxes alternate y≈763 (top of picture) and y≈1167 (bottom) every 1–3 words ("with" top, "an account"
   top, "and get" bottom), pop words (SMART, EXCUSE) at y≈672, depth cards higher again.
4. **Sizing.** Some cards spill out of the picture (wide picture = 1080x608 band, pic_h 608) into the black bars ($3,000,
   DOLLARS, THE CAPITAL lead), others fit inside. No consistent rule.
5. **Money should be GREEN** "for more emotion".
Repro script for 1–3: /Users/y/Projects/true/.claude/briefs/caption_vs_speech.py
(`python3 caption_vs_speech.py <plan.json> [until_s]`). Copy it into docs/proof/ if useful.

## Yahia's decisions (settled — implement exactly)
B1. **Spoken words only in captions.** Every caption (depth card, front caption, pop word) shows only words he is saying, in
    spoken order, each word exactly once, on screen during a window that overlaps its spoken time. Break cards at sentence /
    clause boundaries (punctuation, pause >= 0.25 s); never cross a sentence end; never leave a dangling fragment. Prefer
    breaks that make the card END on its strongest content word (emphasis list / stress) so the giant word is meaningful;
    never reorder or invent words to achieve it.
B2. **Hook title = separate title, looks different.** The AI-written hook stays (PB Blake style requires hook text) but is a
    TITLE, not a caption: static (no per-word timing), distinct from captions by typeface, weight, tracking and position (title
    typography from the campaign style pack if it defines one, else clean tracked sans), and it lives in the BLACK BAR above
    the picture — the only element allowed there. Spoken captions run inside the picture from t=0 at the same time. Full-bleed
    frames with no bar: title sits in the top safe area on a plate so it still reads as a title.
B3. **On time.** Card start = onset of its first spoken word (up to 2 frames early, never late). Lead tier shows at card start;
    the emphasis word appears (fade) at ITS word onset (same tolerance). Card ends at the next card's start or phrase end + <= 0.4 s
    hold. "Min 1.2 s" is met by grouping more words into the card, never by shifting a start. Delete the fixed 1.2 s grid and
    any retime() that delays starts.
B4. **One home spot.** Per clip, ALL captions share one home position in the TOP part of the picture: drawn behind the head
    when the depth matte allows, otherwise the same text, same position, same size, in front. No top/bottom band switching,
    no separate pop-word position, b-roll segments use the same home. If an in-front card would cover eyes/mouth, shrink
    (>= 0.75) in place — never relocate.
B5. **Always inside the picture.** The whole caption ink (lead + big word + stroke + shadow) stays inside the picture rect
    with margins >= 4% of picture width (sides) and >= 3% of picture height (top). One fixed size per role per clip (lead
    tier; big word cap height chosen once per clip from picture height + head top). Long words width-fit down to 0.6, else
    split to the next card. Number cards keep the fix1 rule (no digit or separator hidden behind the head; "$2,000" keeps its
    comma visible).
B6. **Money green.** Currency amounts ($100, $2,000, 3k, 3 grand, and "dollars/bucks" when part of an amount phrase) render
    in a saturated money green (~#2BD46A) in every look and in front captions, with the same contrast gate/stroke fallback
    look A uses. Default on for all campaigns; a campaign style pack may override the colour.

B7. **QUIET depth (Yahia 12:0x: "too loud… flashy text behind the content, like an ad").** Depth stays on EVERY line, but
    quiet. This is the DEFAULT instead of the A/B/C look rotation (which stays selectable per pack, see B8) (red Didone slam / giant Anton / hollow outline):
    - one font, plain white (money green per B6 is the only colour), subtle soft shadow for legibility, no stroke/outline;
    - much smaller: the big word is a calm subtitle-plus size, not a poster word (start ~40% of the old cap height; must
      still clear B5 margins); lead tier and big word may merge into one line/two lines at a single size if that reads calmer;
    - entrance = soft opacity fade ~150–200 ms, no scale, no slam, no flash; exit = short fade, not a hard cut;
    - same treatment for in-front fallbacks at the home spot, so depth vs front differs only in the head passing in front.
    Show a before/after still pair (old loud vs new quiet, same frame) in the proof.

B8. **Every caption knob lives in the STYLE PACK, not in code (Yahia 12:1x: many vibes coming — Tate-style hype,
    looksmaxing, wellbeing, …).** B7 "quiet" is the DEFAULT caption style, not the only one. Do NOT delete looks A/B/C, slam,
    hollow outline or red Didone: move them behind style-pack fields, e.g. `captions: {style: quiet|loud, font, case,
    size_role, colour, money_colour, entrance: fade|slam|none, entrance_ms, exit, depth: off|hook|all, home: top|low,
    lead_tier: bool, look_rotation: [..]}` with quiet defaults. Packs without a captions block get the quiet defaults.
    B1/B3/B4/B5 (spoken-only, on time, one home spot, inside picture) are ENGINE RULES every pack obeys — a pack can change how
    text looks, never invent words, delay them, jump them around or spill them. Tests: a loud pack and the quiet default
    both pass the B1/B3/B4/B5 tests; pack schema validation rejects unknown caption fields.

## Tests (must fail on the old render behaviour)
- shown-vs-spoken: concatenated caption words (excluding the hook title) == transcript words in order, each exactly once.
- timing: every card |t0 - first-word onset| <= 2 frames and t0 <= onset + 0; big word visible within 2 frames of its onset.
- home: every caption box centre-y within ±40 px of the clip's home line.
- bounds: every caption ink bbox inside the picture rect minus margins on every frame; only the hook title may be outside.
- money: amount tokens get the green style; non-money numbers do not.
- title: hook title is static and outside the picture on bar frames; never counted as a caption.

## Live proof (the part fix1 skipped — required this pass)
1. Re-render Kumar mom_bab1b6992f wide + square in a tmp home (copy /private/tmp/kumar-home's setup; library.sqlite there is a
   tmp copy). Contact sheet = one still per card at its BIG-WORD onset frame + the title frame. Write a timeline table
   (card t0, first-word onset, big-word onset, delta, home-y, inside-picture yes/no) and the shown-vs-spoken diff (must be
   empty) to docs/proof/captions-v3/. Bitrate stays 12–16 Mbps.
2. PB Blake onboarding from scratch in a tmp home: 6 drafts, one contact sheet + state per draft (fix1 item 6 + the b-roll
   relevance gate visible in the decision log). Nothing posts.
3. LOOK at every still yourself before writing result.md; list anything that still looks wrong rather than calling it done.
Report in result.md under "Pass 2 — captions v3": what changed, proof paths, the timeline table summary, what's not done.
