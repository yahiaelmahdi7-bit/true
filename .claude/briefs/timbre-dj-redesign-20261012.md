# Timbre: redesign the DJ NATORE Home UI (Yahia: "the graphics n design for his ui is ugly") + live Recents

Work in a NEW git worktree branched from `release/20261012` (base worktree ~/Projects/timbre.builders/release-20261012 = DJ main + scroll/photos/wash; this is what is installed). Commit on your branch. Do NOT touch ~/Projects/timbre main checkout. Sibling builders (cover-art, song-actions) edit ArtworkViews/TrackRow; keep out of those files.

## What is wrong now (screenshot /Users/y/Library/Application Support/True/ScreenshotTray/shots/20261012-172431-908d.png — READ IT)
- "DJ" heading is a giant orange word cropped at the window edge; "Tell me…" prompt + "Where…" text field are cramped and clipped at top-right.
- Presence = a blurry orange smudge, reads as a rendering glitch, not a character.
- "DJ picks" header is a lone orange label floating; first card is a grey gradient with a faint glyph (broken/empty look); collage cards = 4 hard-cut squares with no breathing room; "Genre set" subtitle is meaningless.
- Huge dead vertical gap between picks and the next shelf; next shelf's tilted 3D cards bleed under the content.
- Overall: no hierarchy, orange accent fights the album art.

## Do
1. Load and follow `~/.claude/skills/taste/SKILL.md` and the House grammar `/Users/y/.claude/design/DESIGN-SYSTEM.md` (+ apple-hig for macOS feel). Study refs: Spotify DJ (the "DJ" card + voice line), Apple Music "Listen Now" hero, Arc/Linear calm surfaces.
2. Redesign the DJ spot as ONE composed hero card at top of Home, full content width, nothing clipped at any window width ≥ 900pt:
   - Left: DJ NATORE identity — a refined animated presence (soft orb/waveform that reacts to the DJ's voice level & music, crisp edges, not a smudge), name, one-line status ("Picking easy ones for you…" / what's playing next + why).
   - Primary Play DJ button, plus a clean prompt field ("Ask NATORE for a vibe…") with send affordance, always fully visible.
   - Right/below: picks as a horizontal row of uniform cards: real art (single cover or a well-gapped 2×2 with rounded inner corners), clear title, subtitle that says WHY ("Because you liked Tyler, The Creator" / "Late-night R&B"), never "Genre set". No empty/grey placeholder cards — skip picks with no art.
   - Colour: derive accent from the current/next pick art (reuse NowPlayingWash/WashColors) instead of flat orange; keep text legible.
3. Tighten Home vertical rhythm: consistent section spacing; kill the dead gap; shelf headers one style.
4. **Recents doesn't update live** (Library sidebar sorted by Recents): playing/adding an album must reorder the sidebar immediately (observe the play history / lastPlayed store), no relaunch. Add a test.
5. Perf rules: Home idle ≤5% CPU; never blur a large scaledToFill image (froze app before); animate only small layers.

## Gate
Self-check against /taste before reporting. Render proof PNGs of the full Home (window 1440×900 and 1000×800) offscreen via ImageRenderer into proofs/dj-redesign-*.png and LOOK at them; iterate until they pass. `swift build -c release` 0 warnings, `swift test` passes (PerfTests.scrubberTicks / LikedScroll timing flaky under load — rerun alone). Package with ./scripts/package.sh assets/timbre-red.icns into dist/. Don't install or launch on screen.
