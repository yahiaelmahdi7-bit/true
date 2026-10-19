# Depth captions r2 — readability fixes, then the PB Blake proof

Same rules as before (dispatch-brief, worktree, no push/merge, real library read-only, never post, result.md early).
I (reviewer) looked at your stills. The depth effect itself is good (clean edges, head really in front). Word
placement is not shippable yet:

## Defects seen in the real stills
- Whole letters hidden: "A PART··ULARLY", "ABOU·· UCK?", "FUC·ING", "D·D." — each passed the 70% gate. A word-level
  pixel share is the wrong measure: losing 2 whole letters keeps ~80% of the pixels but kills reading.
- Cards leave the picture: "SHOULD" and "AS LUCK," are cut by the top edge of the picture area.
- Front highlight text collides with the depth word ("Ovarian Lottery" over "LOTTERY").

## Fixes
1. **Per-letter gate.** For every glyph in the card, over EVERY frame of the card (not 3 samples — sample at least every
   2nd frame, use the cached mask): visible share of that glyph >= 0.6 AND its top half >= 0.85 visible (people read the
   tops of letters). Word-level >= 0.8. Constants named and tunable. Unit-test with synthetic masks: one fully hidden
   letter must fail even if the word share is 90%.
2. **Placement search like the reference grammar.** Candidates should put the head over the LOWER part of the letters
   (word baseline sits at/below the crown of the head, letters rise above it), sliding x and y, at a few sizes; pick the
   one with the best min-glyph visibility that also overlaps the person (else it is not a depth card). Fall back to a
   front caption if none passes.
3. **Stay inside the picture.** Card box (with a safe margin, ~4% of picture height) must lie fully inside the visible
   picture rect (respect letterbox / layout_square bands), never across its edge. Test it.
4. **No collisions.** While a depth card is on screen, front highlight/emphasis text that overlaps its box is hidden
   (or moved); the hook band stays. Test it.
5. **Wide shots.** If the mask's head region is smaller than ~6% of picture height, use front captions for that card
   (the "behind" effect is invisible there). Log the reason.

## Proof
Re-render the 3 proof clips (overwrite docs/proof/depth/). THEN render PB Blake moment mom_bab1b6992f (src_c9b497e0d2
195.95-242.25) through the Edit Room with the same EDL/preset as the r3 render
(~/Projects/clip-studio.builders/clip-studio-editroom-20261012-000015/docs/proof/editroom/r3.mp4, preset D) plus
`--depth-captions all` → `docs/proof/depth/pbblake/depth.mp4` (local only, never queued). For every proof: stills at
4 word onsets from the real MP4 + per-card min-glyph visibility table + fallbacks with reasons. LOOK at every still;
if any letter is unreadable, fix and re-render before finishing. result.md: append an "r2" section.

## Done =
Whole engine pytest green incl. the new tests; stills checked by you; r2 section says plainly anything still off.
