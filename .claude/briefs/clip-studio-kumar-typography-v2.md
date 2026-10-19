# Kumar effects — STEER: depth caption typography v2 (Yahia, 2026-10-12 ~10:58) — this overrides the slam spec where they differ

You were stopped mid-run on purpose; keep everything you built (effects.py, quality.py, tests). Yahia watched the current
depth-caption render and rejected it: "look like shit, aren't centered, just flash for a second, no cool fonts or different
sizes or effects — just a text box". He then picked from mockups. Mockup still + the exact compositing code (fonts, sizes,
shadow, hollow stroke, gradient, two-tier layout):
- ~/Projects/clip-studio-refs/research/depth-looks-v1.png   (A, B, C chosen; D not chosen)
- /private/tmp/claude-501/-Users-y-Projects-true/7e508698-e3fd-44df-8744-f21a27711f56/scratchpad/mock_depth.py
Fonts are in ~/Projects/clip-studio-refs/ref-style-1/fonts-candidates/ (Google Fonts, OFL): bundle the ones you use with
their OFL licence text under engine/clipengine/data/fonts/ — never the ref video/frames.

## Scope: EVERY depth card (depth mode hook|all, with OR without a style pack), plus word_slam / cover_end_card.
Depth stays per-campaign, default OFF, critic/onboarding cannot enable it. A style pack overrides colours/sizes with measured
values; without a pack these defaults apply. Arial Bold (`depth.SANS`) is retired for depth cards.

## Looks (Yahia picked A + B + C; rotate them by ROLE, deterministic — same input = same render)
- A "ref slam": carrying word in a condensed Didone (Abril Fatface; Bodoni Moda 900 as alt), fill = pack `slam.fill` else
  #FB0103, width ~0.91 of frame; lead-in word(s) above in Montserrat 900, white, tracked ~+18 px@1080, ~65-70 px tall.
- B "scale": carrying word in Anton, white, width ~0.94; lead-in Montserrat 800, tracked ~+30 px, ~60-64 px. Soft drop shadow
  (blur ~18 px, ~55-60% black, offset ~(6,10)).
- C "solid + hollow": lead-in word in solid white Anton (~0.42 width), carrying word in Anton as a HOLLOW outline (stroke
  ~5 px@1080 white, transparent fill), light shadow.
- Role rotation: the hook card = A (or the pack's slam); punch/carrying words alternate B and C; never the same look on two
  consecutive cards. Two-tier layout on every card: small lead-in tier + giant carrying-word tier (1-word cards = giant tier
  only). Carrying word = the content word that carries the line (reuse your slam word picker); the other 0-2 words are the
  lead-in tier.
- Legibility: shadow on every look; the existing contrast check still runs; if A's red fails contrast on the background, use B.

## Centering (hard rule — the old placer slid cards sideways to pass the readability gate; that is why they were off-centre)
- The card's ink box is centred on the picture rect's vertical centre line (|ink_cx - pic_cx| <= 1% of frame width). NO x search.
- Search only y (and size, down to ~0.75 of target width): raise the card until the readability gate passes — the head clips
  the bottom of the middle letters, it does not swallow them. In frame=wide the card may extend above the picture into the
  black band. Keep the gate (GLYPH_MIN_VIS 0.70, WORD_MIN_VIS 0.80, top-half rule).
- No centred y/size passes → render the SAME look centred IN FRONT of the head (log `fallback_front`). Never off-centre, never
  silently dropped.

## Timing (Yahia: "every chunk, min 1.2 s")
- Every 1-3 word chunk still gets a card, but every card is on screen >= 1.2 s.
- Card t0 = its first word's spoken onset (or the previous card's t1 if later); t1 = max(t0 + 1.2, last word's t1, next
  card's onset if within 0.3 s — hold until the next card instead of a blink of empty frame).
- A card's text may never appear more than 0.5 s after its first word is spoken: if holding the previous card would push it
  past that, merge the chunk into the previous card (lead-in tier, still <= 3 words / 2 tiers) instead of delaying it.
- No two cards overlap. The front-caption split rules from r3.1 stay: no front caption on screen while a card shows.

## Entrance: slam in
- Scale 1.15 -> 1.00 about the card centre over 4 frames (ease-out), alpha 0 -> 1 over the first 2 frames, then a 1-frame
  micro-shake (+-6 px x, +-3 px y) on the landing frame, then still. Exit: hard cut at t1 (or 2-frame fade if the next frame
  is a cut anyway — pick one and say which).
- The person matte is applied per frame during the scale-in (the head stays in front on every frame); the readability gate
  is evaluated at the final 100% size.

## Tests (add to the suite)
- Centring: every accepted depth card's ink centre within 1% of pic centre x, both frames (square, wide).
- Timing: every card >= 1.2 s; no card text later than 0.5 s after its spoken onset; no overlaps; no front chunk under a card.
- Look rotation deterministic + no same look twice in a row; hook = A; fallback_front keeps the look and the centre.
- Entrance graph: 4 scale frames + shake frame present; matte applied on those frames.

## Proof (local, tmp library copy, never the real library)
Render PB Blake mom_bab1b6992f with depth=all, frame=wide AND frame=square → docs/proof/typography/. Stills (from the real
MP4s): each card's landing frame (onset + 4 frames) for the first 6 cards, one mid-card frame, and a 6-frame strip of one
slam-in. Contact sheet of all of them. LOOK at them before reporting: centred, behind the head, readable, the three looks
visibly different, no card shorter than 1.2 s (print the card table: t0, t1, dur, look, words, depth|front). Report the
measured output bitrate of these renders (the HD bar applies).

Then continue the rest of the original Kumar brief (build line, montage, flash, punchline, end card, proof) on top of this.
