# clipping-site: hero tape river + rail show the REAL clips, not the same 3 samples

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clipping-site (Next.js). No deploy,
no push, no edits to the Clip Studio library (open it read-only only). Write result.md EARLY and extend it.

## The ask (Yahia, verbatim)
"for the tape river background i need it to actually display the different clips its making and showing the real clip
instead of just looping the same 3 over n over"

## Why it loops 3 today
`components/Hero.tsx`: the hero uses only `posted` clips; none are posted, so it falls back to the 3 CC BY sample pairs
(`public/clips/pairs.json`) and the river is built only from those pairs' frames (`lib/riverFrames.ts`,
`public/clips/river/index.json`). `public/clips/manifest.json` already holds 6 REAL Clip Studio cuts (CC BY, credited,
unposted) that Trending shows as "New cut". `allClips` is passed to Hero and ignored.

## Do
1. **Hero pool = the real clips first.** All manifest clips (posted or not), newest first. Label exactly like Trending:
   real views when posted, "New cut" when not. The 3 sample pairs only join AFTER the real clips (still labelled
   "Sample cut"), and only while there are fewer than 6 real clips. Never invent a view count, campaign or clip.
2. **River frames from every pool clip.** Extend `scripts/extract-river-frames.mjs` to emit rows per real clip
   (key `clip: <file id>`, alongside the existing `pair` rows). Source of frames:
   - if the manifest entry has a source window (see 4), frames from the source video at that window;
   - else 4-6 frames sampled across the cut mp4 itself, cropped to the landscape tile from the picture area (no black
     bands, no burned-in caption in the crop if avoidable).
   The bracket label must never invent a timestamp: show the real source window when known, otherwise
   "NEW CUT · <channel>". Each bracket must cover frames of the card that lands (keep round-7 invariant).
3. **Rail cycles the whole pool.** Check HeroStage / `lib/riverEngine.ts` for anything capped at 3; every card plays its
   own mp4. Keep the round-7 perf rules (one playing card decoding, lazy load, band-only canvas).
4. **Export must never wipe the site.** `scripts/export-clips.mjs:50` deletes every `mom_*` file before writing. The
   library now has 0 CC clips (its CC sources are gone), so a rerun today would empty the site. Change it to MERGE:
   keep existing on-disk clips that are still valid, add new ones, keep the newest MAX, and delete only files no longer in
   the new manifest. Going forward write `source: { video_id, t0, t1 }` into each entry. Raise MAX to 12 (keep the
   4 MB per-clip cap). Make the merge a pure function and test it (incl. "library returns 0 -> manifest unchanged").
5. **Campaign clips stay off the site by default.** Add a per-campaign showcase allowlist for the export (a small
   `site-showcase.json`, default `[]` = CC BY only). Do NOT enable any campaign; Yahia decides per campaign.

## Done means
- `npm run lint`, `npm run build`, `npm test` green (report counts).
- Proof (reuse the round-7 proof scripts): desktop + 390 px phone screenshots of the hero at 4+ rotation steps
  showing at least 4 DIFFERENT cards, and the river showing frames from different clips with honest bracket labels.
  Save under docs/proof/hero-real/. Look at them yourself before claiming.
- result.md: what changed, test counts, proof list, anything unverified, stated plainly.
