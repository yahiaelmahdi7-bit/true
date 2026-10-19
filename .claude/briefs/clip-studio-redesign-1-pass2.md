PASS 2 — same worktree/branch, same brief (/Users/y/Projects/true/.claude/briefs/clip-studio-redesign-1.md) and DISCIPLINE.
Orchestrator reviewed home/moments/sources/campaigns dark renders. Fix, re-render ALL screens (dark+light), READ them, report.
1. Library/Sources tiles render as empty black boxes. Every source needs a poster: local media -> first non-black frame
   extracted once with ffmpeg (cache next to the media / PosterCache), remote thumbnail only as fallback; placeholder = bg2
   with the film glyph centered, never pure black. Same for Live/Discover/Series/Queue thumbs.
2. Home is one row + empty space. Build the rows from the brief: Needs you (only if any) · Ready to post (9:16) · Campaigns
   (joined first; cards with posts today/cap + deadline countdown mono) · Trending (Discover) · Recent sources (16:9).
   Section rhythm 48 between rows; rows scroll horizontally. Home must look full on the copy library.
3. Accent discipline: ONE accent-filled button per screen ("New clip" in the bar counts as the screen's one). Campaign "Join",
   "Read rules", "Add campaign", sheet buttons etc. = secondary style (bg2 fill, text0, radius 9; hover bg3). "New" badges stay
   accent-soft pills but only on items new since last view; Watching/Joined = neutral status chips (ok dot for Joined).
4. Finish what you listed: Sounds/Live/Discover/Series full tile grammar; Inspector slide-over without grouped Form (plain
   sections: label 11 caps text3 + values text1, actions as a button row); Campaign cards add posts today/cap + deadline
   countdown; light-mode pill backgrounds; Moments score label TOP-LEFT on a top-down soft scrim; remove the extra Home row
   you flagged; Funnel: seed fixture numbers in snapshot mode so the stat-tile layout renders (snapshot only, never real data paths).
5. The Campaigns render shows "Engine not set up. Run scripts/bootstrap-engine.sh" — confirm it is a snapshot-environment
   artifact (engine root not found under CLIPSTUDIO_HOME runs) and make snapshot mode point at the worktree engine so the
   banner does not appear; do not change real-app detection.
6. Render at 1440x900 points if feasible (window content size), @2x if the backing scale allows; otherwise say why.
Gates again (swift build, build-tests, swift test grep Executed). Leave docs/proof/submit/* alone.
