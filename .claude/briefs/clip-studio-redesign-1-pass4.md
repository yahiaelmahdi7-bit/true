PASS 4 — same worktree/branch. Saved light mode + Campaigns tiles rebuilt simple + the broken dropdown replaced.

Yahia (verbatim, with 2 screenshots of Campaigns in LIGHT mode): "make light mode a saved setting but also the campaines drop
down on the tiels is broken and renders broken the white also is too much i cant see the tiles its too much text lets simpolfy
with the rate per 1k views so just show $ and the budget left with a activty ring shopwing progress and the titel of the
campagine on the tiles screen"

What he saw: light mode = cream page and tiles with no surface, so tiles don't read as tiles. Each tile is a wall of text
(marketplace, Watching, "TikTok $1.50 / 1K views" in mono, POSTS TODAY, DEADLINE, "$x left", "checked 1 h ago", Join). The
chevron dropdown expands INSIDE the grid cell: the row grows, the panel content is unstyled ("Rules and requirements stay hidden
until you join.", "Contracts we can fulfil", and a system-BLUE "Banned / Allowed" segmented control). The source status line
("Content Rewards: 51 found • Vyro: 9 found • Whop: blocked, no public campaign list: whop.com/discover is search-driven and
robots.txt disallows /discover/search") is a sentence of noise.

## Build
1. Saved appearance: Settings → Appearance = Light / Dark / System, stored in UserDefaults (standard domain, key
   "appearance", values light|dark|system), applied live (no relaunch). Precedence: --appearance arg > CLIPSTUDIO_APPEARANCE
   env > saved > default dark. (AppModel.swift:756 today.) Brand-styled segmented control, not system blue.
2. Campaign tile = ONLY: title (bold, max 2 lines) · rate "$1.50 / 1K views" (platform as a small glyph, not a word) · budget
   left as the big number "$7,923 left" · an Apple-style activity ring (~44 pt, money green #2BD46A on a muted track) showing
   budget progress = spent / budget_total, with the % in or beside it. Unknown budget_total → no ring (a thin dashed track),
   never a fake number. Joined campaigns get one small green dot by the title; nothing else. Remove from the tile:
   marketplace name, Watching/NEW pills, POSTS TODAY, DEADLINE, "checked … ago", Join/Read rules button, the chevron.
3. Tile surfaces in light AND dark: tiles are cards that read on the page — light: page a touch darker than the card
   (e.g. page #F1F0ED, card #FFFFFF, 1 px hairline rgba(0,0,0,.07), very soft shadow); dark: card one step above the page.
   Hover = slight lift. Same grid rhythm (5 columns at 1900 px wide, fewer when narrower), equal tile heights.
4. Dropdown → detail panel: clicking a tile opens that campaign in a right-side inspector (same pattern as Moments' details
   panel), never inline in the grid. Everything removed from the tile lives there: marketplace, status, Join / Read rules,
   posts today, deadline, checked time, rules / "hidden until you join", Contracts we can fulfil, background music
   Banned/Allowed (brand-styled control). Esc or clicking the tile again closes it. Grid reflows narrower while it is open.
5. Source status line → one compact chip per marketplace (green dot = ok, amber = blocked) with the long reason in a tooltip.
6. Taste: ~/.claude/skills/taste/SKILL.md applies. Money green only for the ring, the joined dot and primary actions.

## Gates
swift build, swift build --build-tests, swift test (grep "Executed"). Re-render campaigns-light, campaigns-dark, a
campaigns-light still with the inspector open, and settings (appearance) light/dark into docs/screens/redesign/. Read your own
renders before reporting. Commit; no push/merge; no engine/ changes; do NOT quit or relaunch the running ClipStudio.app.
