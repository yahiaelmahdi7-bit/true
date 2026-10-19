# Kumar typography v2 — fix1 (reviewer: looked at docs/proof/typography/ contact sheets + cards.txt)

Run-2 work is good: centred (cx 539.5–540.5), >= 1.2 s, 15 Mbps, wide cards behind the head. Fix these 5, then re-render
BOTH proofs (tmp library only, never the real one) and regenerate the same stills/contact sheets/cards.txt.

1. READING ORDER BROKEN. wide-card5 / square-card5 read "TELLING THAT. / YOURSELF" for spoken "telling yourself that.".
   Invariant: reading the small label then the big word must equal spoken order. Pick the carrying word so no words follow it
   in the card (prefer the LAST content word of the chunk; trailing stopwords like "that/it/you/to" move to the next card or the
   label). Test: for every card, " ".join(lead) + " " + carry == spoken chunk text (case/punct-insensitive).
2. PUNCTUATION ON THE BIG WORD. "SAID," "DOLLARS." "ACTION." "$3,000." -> strip trailing , . ; : from the carrying word
   (keep internal $3,000 comma, keep ? and !). Labels may keep their punctuation. Test it.
3. HOOK MUST BE A (Yahia settled hook = A). On wide, A's red failed contrast -> B. Before falling back to B, try A with its
   shadow + a thin dark/light stroke and/or a brighter red that passes MIN_CONTRAST; only if all A variants fail use B, and log
   the measured contrast for each attempt in the card table. Show the wide hook still.
4. SQUARE fallback_front DRAWS ON THE FACE (square-card3/5/mid: hollow "SAID," "YOURSELF" across the forehead/hair).
   Rule: a fallback_front card's box must not overlap the face box (eyes-to-chin; use the person mask / framescan face box).
   Order: (a) allow it to rise into the black band above the picture; (b) scale down to >= 0.6; (c) if it still overlaps the
   face, skip the depth card for that chunk and let the normal front caption carry it (record reason "face_overlap").
   Also say in result.md WHY behind-head fails on every square card (gmin values) and whether a smaller card size would pass.
5. LAG EDGE CASE. retime(): after a slam/hook card (or a non-"word" previous card) the next card is pushed to p.t1 with no
   0.5 s check. Enforce the 0.5 s rule there too (shorten the slam/hook hold to the next onset + 0.5 if it is >= 1.2 s, else
   merge/skip). Add a test, and add a per-card "lag" column (t0 - first word onset) to cards.txt; max lag must be <= 0.5.

Proof (LOOK before claiming): first 6 landing stills + mid in both frames, the wide hook still, cards.txt with lag column.
Full pytest from engine/ (PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q). Commit on the builder
branch only; never push, never touch the real library or ClipStudio.app.
