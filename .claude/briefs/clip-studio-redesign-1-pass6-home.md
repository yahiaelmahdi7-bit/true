PASS 6 — HOME NEVER EMPTY + MY CHANNELS (same worktree/branch as pass 5).

Yahia (verbatim, today): "yhe home screen should not be empty ity needs content in there"
Earlier (verbatim): "for home and trending tab and live need work they look like the free yt recommend ones whioch is a bunch
of slop we dont wnat or watch" → he picked MY CHANNELS + NICHE TRENDS. No generic trending anywhere by default.

Problem in your own pass-5 render (docs/screens/redesign/home-light.png): Home = a dry-run line, ONE "Needs you" card, then a
wall of blank space, then "Ready to post". No channels, nothing above the fold. One "Ready to post" card is a SMPTE colour-bars
test clip — find which source/moment it is in the library copy and REPORT it (do not delete or hide real rows by guess).

## Step 0 — bring in the channels engine
Merge branch `builder/clip-studio-channels-1-20261012-144301` into this branch (engine-only, commit abdd2bd). Read
engine/docs/channels.md first — it has the exact JSON contracts + screen notes. Use ITS CLI (`--json`) for everything:
`my-channels [--live] [--refresh]`, `niches [pin|unpin <name>]`, `discover --niche` (default when niches exist; `--all` =
old global feed). No Python logic re-implemented in Swift.

## Build
1. Home, top to bottom (every section from real data; a section with no rows is hidden, never a blank band):
   a. Stat strip: moments waiting, ready to post, posted this week, live channels — real counts only.
   b. "Your channels": wide cards (avatar, name, platform, why = rights/campaign + pay note). LIVE → stream thumbnail, red LIVE
      pill, viewers, category, "live since"; `recording` → a recording badge. Offline → last moment date + library counts.
      Actions: Record (existing live-record path if the app has one; else hide), Open channel.
   c. "Needs you" and "Ready to post" in ONE row (two columns or one horizontal scroller that fills the width) — no lone card
      followed by empty space. Up to 6 each + "See all" → Moments filtered.
   d. "Trending in your niches": `discover --niche`, ≤8 items, niche chips on top (pinned niches first).
   e. "Your campaigns": joined campaigns (campaign tile from pass 5), rate + deadline.
   f. "Recent moments": newest 12 moment tiles (154 exist) so Home always has content.
   Whole-Home empty state ONLY when every section is empty: "Add a channel you can clip" → channel-rights add flow.
   Loading = skeleton tiles, not blank. Errors = the engine's status text inline in that section.
2. Discover (Trending tab): channels-first — "Your channels" row, then niche sections with chips; old global feed only
   behind an "All trending" toggle, off by default.
3. Live tab: grid of HIS channels (my-channels), live first with thumbnails + viewers; offline ones dimmed below.
4. Taste: ~/.claude/skills/taste/SKILL.md, pass-5 bordered cards + ActivityRing, money green accents, light + dark. Fill
   1440 wide without dead space; check at 1280 and 1728 too.

## Gates
swift build, swift build --build-tests, swift test (grep "Executed") + tests: Home section hiding when empty, stat counts,
my-channels JSON decode (fixture from docs/channels.md), live-first ordering. Engine pytest for the merged channels files.
Renders into docs/screens/redesign/: home-light/dark (real library copy), home-empty-light (empty sandbox), discover-light/dark,
live-light/dark. Read your renders and fix dead space before you finish. Commit; no push/merge to main; do NOT quit or
relaunch any running ClipStudio.app; CLIPSTUDIO_HOME sandbox only (render.sh read-only copy is fine).
