# ClipStudio redesign 1 — media-first shell, every screen (Higgsfield-grade feel, our identity)

GOAL (one sentence): replace the sidebar/settings-page look of the ClipStudio macOS app with a dark, media-first
interface — top tab bar, video tiles as the UI, one green accent — across EVERY screen, without changing any logic.

## Context (do not re-derive)
- Repo ~/Projects/clip-studio (you are in a worktree of it). SwiftPM, macOS 26, SwiftUI. UI target Sources/ClipStudio
  (~5.3k lines), Core Sources/ClipStudioCore. Build: `swift build`; app bundle: scripts/package.sh (do NOT run it).
- Shell today: ClipStudioApp.swift:49 NavigationSplitView + sidebar List (:161-176) + DetailRouter switch (:184-199) over
  `SidebarItem` (AppModel.swift:5-16): Sources, Live, Moments, Campaigns, Series | Queue, Published, Insights, Funnel, Sounds.
  `.inspector` for Moments + Queue (:54). Settings scene :33 (SettingsView.swift, TabView Accounts/Advanced).
- Screens: LibraryViews (Sources/folders :4/:43/:84, Live :175), MomentsView, QueueView, PublishViews (Published :4,
  Insights :45), FunnelView, CampaignsView (530 lines), SeriesView, SoundsView, DiscoverView (inside Sources),
  InspectorView, AccountKitView, SheetsAndSettings, LiveFeeds.
- Tokens today: Brand.swift (:6-118: palette map, fonts, brandCard/brandPill, button styles) mapping hex ints in
  ClipStudioCore/CampaignPresentation.swift:4 (has a luminance() for contrast tests). Most screens use raw system
  fonts/colors. Color(hex:) lives in SeriesView.swift:190.
- Media: Players.swift:5-17 hover-loop tiles, :38-60 PosterCache/MomentPreview; Moment.poster, Clip.thumb/path,
  Source.thumbnail (remote URL), DiscoverStream.thumbnail, SeriesPart.cover(s) (Models.swift:137/148/163, Series.swift:9).
- Hooks: CLIPSTUDIO_HOME (Paths.swift:6 + engine common.py:4) relocates the library; CLIPSTUDIO_SCREEN / --qa-screen /
  `snap` (AppModel.swift:735-750) deep-link a screen; CLIPSTUDIO_APPEARANCE=dark|light.
- Screenshots: docs/screens/README.md — screencapture is BLOCKED for you (no Screen Recording), and ImageRenderer could not
  render NavigationSplitView. The new shell has no split view, so offscreen rendering should work (see PROOF).

## Settled by Yahia — do not reopen
1. Navigation = TOP TAB BAR, no sidebar. 2. Accent = our caption "money green" #2BD46A (capv3.py MONEY = 43,212,106),
NOT Higgsfield lime. 3. All screens in one build.

## Reference (measured from higgsfield.ai live; borrow structure/feel, never copy)
Near-black ground #0F1113, ink #F7F7F8, inactive nav #A8A8A8, cards #1C1E21/#23262A with no borders; nav links Inter
14/500 tracking .1px, pill hover, active = accent text; ONE accent used only for active tab, the single primary button,
and tiny badges (accent text on ~20% accent wash, 10-11px bold); video tiles autoplay muted loop, no controls, radius 8,
gap 20, title BELOW tile in Space Grotesk bold UPPERCASE 16 tracking -4%, subtitle 14 grey; horizontal rows that scroll
with hidden scrollbars; press = brightness dim, no scale bounce. Stills: ~/Downloads/higgsfield.ai zip (images only).

## Design spec (House grammar ~/.claude/design/DESIGN-SYSTEM.md wins over the reference)
Skin "clipstudio": DARK default (video tool = dark product) + a working LIGHT mode (house rule: both modes, follow system,
CLIPSTUDIO_APPEARANCE override keeps working).
Tokens — hex ints in Core (new ClipStudioCore/Tokens.swift; keep CampaignPresentation's names working or migrate callers),
Brand.swift maps to Color by colorScheme. NO raw hex / Color literals / .font(.system) in views.
- Dark: bg0 0x0F1113 · bg1 0x17191C · bg2 0x1E2124 · bg3 0x0A0B0C · text0 0xF7F7F8 · text1 0xDCDDDF · text2 0xA8A8A8 ·
  text3 0x6E7175 · line = text0@8% · lineStrong = text0@16% · accent 0x2BD46A · accentInk 0x2BD46A · accentSoft accent@18% ·
  onAccent 0x0B0D0E · ok = accent · warn 0xF5B83D · danger 0xF26B5B.
- Light (warm paper, never #fff ground): bg0 0xF4F3EF · bg1 0xFAF9F6 · bg2 0xFFFEFB · bg3 0xE9E7E2 · text0 0x141516 ·
  text1 0x2A2C2E · text2 0x5E6166 · text3 0x8C8F94 · accent 0x2BD46A (fills) · accentInk 0x167F41 (text on paper) ·
  onAccent 0x0B0D0E · warn 0xB7791F · danger 0xC2412D.
- Type, 3 families max: sans Inter (copy /Users/y/Projects/axon/Fonts/Inter.ttf, OFL), display Space Grotesk (download the
  OFL variable TTF from github.com/google/fonts ofl/spacegrotesk + OFL.txt), mono = SF Mono (system). Put in
  Assets/Fonts/, add a copy step to scripts/package.sh (Contents/Resources/Fonts), register at launch with
  CTFontManagerRegisterFontsForURL; also find fonts from the SwiftPM resource/dev path so `swift run`/snapshots get them;
  missing font = system fallback, never a crash. Fixed scale only: 11 · 12.5 · 14 · 16 · 19 · 25 · 33. Tabs 14/500.
  Tile titles display 16 bold UPPERCASE tracking -0.02em, 2-line clamp. Labels/badges 11 bold UPPERCASE tracking 0.07em.
  Numbers, times, scores, money = mono.
- Shape: radius 9 (tiles, buttons, tab pills) · 14 (cards, panels) · 20 (sheets) · pill (badges). Space on the 4-grid only:
  4 8 12 16 24 32 48 64 96. Two shadows max. Motion: ease (.16,1,.3,1) entrances, (.4,0,.2,1) state; 120/220/420 ms;
  poster→video crossfade 220 on hover; tab switch crossfade 220; press dims to 0.6 brightness. No bounce, no parallax.

## Shell
- No NavigationSplitView, no sidebar List. Hidden title bar; a 48pt top bar in the titlebar row (inset for traffic
  lights), bg0, hairline bottom. Left: app mark. Tabs: Home · Library · Moments · Campaigns · Publish (⌘1-⌘5).
  Inactive text2; hover text0 on bg2 pill; active accentInk. Count/NEW badges on tabs only when something needs Yahia.
- Right: ONE primary button "New clip" (accent fill, onAccent, 14/600, h32, radius 9) → the existing add-source/YouTube
  sheet; engine status dot (ok/warn/danger + tooltip); gear → Settings (⌘,).
- Sub-tab row (40pt, text-only, same active treatment): Library = Sources · Live · Discover · Sounds; Moments = Moments ·
  Series; Publish = Queue · Published · Insights · Funnel. Home, Campaigns: none.
- Old names still deep-link: CLIPSTUDIO_SCREEN=<any old SidebarItem raw value> → tab+subtab. Menu commands keep working.
- Inspector → right slide-over panel 380 wide, bg1, Esc closes; every existing action stays.

## Screens — visual/IA rewrite ONLY: keep every action, binding, engine call and sheet. Don't invent engine calls.
- Home (new): strip "Next slot HH:MM · dry run|live" (only if AppModel knows it) · "Needs you" row (needs_your_sound,
  needs your edit, failed submit) only when non-empty · "Ready to post" 9:16 tile row · Campaign cards row · Trending
  (Discover) row. Rows = horizontal scroll, hidden scrollbars. A row with no data is omitted, not faked.
- Library/Sources: 16:9 tile grid (adaptive min 300, gap 16); poster = thumbnail (AsyncImage, bg2 placeholder);
  under tile: title + text2 line (campaign badge · duration mono · N moments). Folders = filter chips above the grid.
- Moments: 9:16 tiles (adaptive min 200); hover plays muted loop (Players.swift); score mono top-left on a soft bottom-to-
  top scrim (the ONLY overlay allowed on any tile); status badge under. Click → inspector. Series: cover tiles.
- Campaigns: card grid (bg1, radius 14, no border): name display caps, platform chips, status badge, posts today/cap,
  rate, deadline countdown mono. Detail: header with key numbers, then plain sections — no Form/GroupBox look.
- Publish/Queue: horizontal cards (small 9:16 thumb · caption · platform chips · time mono · state badge).
  Published/Insights/Funnel: stat tiles (big mono number + 11 caps label) and simple bars.
- Live, Discover, Sounds: same tile grammar. Settings window, AccountKit, sheets: re-skinned with tokens (may stay
  settings-shaped).
- Every grid/row has an empty state: one line text1, one line text2, one primary action. No illustration, no emoji.
- Hard rejects: Form/GroupBox/inset-grouped look outside Settings · box-in-box-in-box · purple anything · 4th font ·
  off-grid spacing · centered-everything · raw hex/Color/.system font in views (add a test that greps Sources/ClipStudio
  for `Color(red`, `Color(hex`, `.font(.system` outside Brand.swift/Tokens and fails).

## PROOF (this decides done)
- Data = a COPY of the real library, never the real dir (the engine migrates schema on open):
  `T=$(mktemp -d); sqlite3 "$HOME/Library/Application Support/ClipStudio/library.sqlite" ".backup $T/library.sqlite"`
  then CLIPSTUDIO_HOME=$T for every run. Image paths that point into the real Application Support may be READ only.
- Add/extend the snapshot mode (the `snap` hook) to render each tab+subtab root and the Settings panes offscreen at
  1440×900 @2x, dark AND light, into docs/screens/redesign/<screen>-<mode>.png, then exit. Try ImageRenderer first; if
  ScrollView/grids/AsyncImage come out blank, use an offscreen NSWindow + NSHostingView + bitmapImageRepForCachingDisplay
  and wait for posters to load. Video tiles may show posters. Also render Home with an EMPTY CLIPSTUDIO_HOME (empty states).
- Run the built binary from .build with CLIPSTUDIO_HOME set. NEVER launch/open ClipStudio.app, never scripts/run.sh —
  Yahia's copy is running.
- READ every PNG yourself. Self-critique against ~/.claude/skills/taste/SKILL.md and the hard rejects, fix, re-render.
  Run `bash ~/.claude/design/design-lint.sh Sources/ClipStudio` if it handles Swift; fix hits. Write
  docs/screens/redesign/README.md: one line per screen + what you would still change.
- Gates (foreground, paste output): `swift build`, `swift build --build-tests`, `swift test` (grep "Executed" for XCTest
  counts; all pass). New tests: token contrast ≥4.5 for text0/1/2 and accentInk on bg0/bg1, onAccent on accent, both
  modes (text3 ≥3); old-screen-name → tab mapping; ⌘1-5 mapping; the no-raw-colour grep test. engine/ untouched.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY on Sources/, Tests/, Assets/Fonts/, scripts/package.sh, docs/screens/ in your worktree branch.
  Do not touch engine/ or anything else — other agents have work in flight on engine/.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge, NEVER 'ship'.
- Gates: run build/tests in the FOREGROUND and wait. NO background shells, NO watch modes, NO until-loops. Kill anything
  you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output, and looked at the PNGs. Never report a state you
  didn't verify this session.
- Decisions: if your change adds a classify / route / gate / rank step, make it a Jev call (jev skill). Unlikely here.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.

## Report
Files changed · screenshot list · gate outputs · what's NOT done / what you'd still change.
