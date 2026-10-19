# Timbre: Home cleanup — "admin" label + ghost layer behind shelves

Work in a NEW git worktree branched from `release/20261012` (~/Projects/timbre.builders/release-20261012). Commit on your branch. Don't touch ~/Projects/timbre main checkout.

1. Playlists shelf on Home shows "2015 · admin" under every playlist — "admin" is the Navidrome owner. Replace with something useful: "Playlist · N songs" (no year for playlists). Check every surface that shows playlist owner.
2. Ghost layer: screenshot /Users/y/Library/Application Support/True/ScreenshotTray/shots/20261012-172040-137d.png (READ IT). Behind the On repeat / Newly added / Playlists shelves, faded duplicate covers and titles (e.g. "MTG NA ONDA DO LANÇ…", "Germán Valdés TIN-TAN…", "Mr. Lucky + Mr. Lucky G…") are drawn offset behind the real cards, plus the sidebar library list shows faded art behind it. Find the cause (likely the RiverLayerView / crate / ArtWorld background layer rendering album cards behind the content, or a duplicate shelf under a blur/opacity) and fix so only the intended background remains. Render Home offscreen via ImageRenderer before/after into proofs/home-ghost-{before,after}.png and LOOK at them.
3. Never blur a large scaledToFill image (froze app before); Home idle ≤5% CPU.
Gate: `swift build -c release` 0 warnings, `swift test` passes (PerfTests.scrubberTicks, LikedScroll, ArtWorld blur timing flaky under load — rerun alone). Package with ./scripts/package.sh assets/timbre-red.icns. Don't install or launch on screen. Report cause, fix, proofs.
