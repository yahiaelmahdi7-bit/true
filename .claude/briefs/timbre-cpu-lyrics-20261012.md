# Timbre: CPU fix, then lyrics (subtitle line + live fill + Jev matching for every song)

Repo: ~/Projects/timbre (SwiftPM macOS app, Swift 6, branch `main`, LOCAL ONLY). HEAD 92bd4de.
Yahia is a non-coder who directs; he picked every decision below. Do the phases IN ORDER, one commit
per phase (or per logical step inside a phase). Report at the end with the gate output pasted.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY in ~/Projects/timbre (Sources/, Tests/, scripts/). No other sessions edit it, but
  never touch other repos.
- Commits: atomic, one logical change per commit, message says what+why, end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. NEVER push (this repo has no remote by design),
  NEVER merge, NEVER 'ship'.
- Gates: run them in the FOREGROUND and wait. NO background shells, NO watch modes, NO until-loops.
- Claims: 'done' means you ran the gate and pasted the passing output. Never report a state you didn't
  verify this session.
- Decisions: the lyrics-candidate match (Phase C) is a Jev call through vendored jev-kit: code owns the
  flow, Jev answers a narrow typed question, route on confidence, log the decision. No keyword lists,
  no LLM prompt-and-parse.
- If blocked: say BLOCKED + one line why. Do not invent extra scope.

HARD LINES (Yahia's, settled): no acquisition layer (lyrics TEXT from LRCLIB is approved; never fetch
audio or anything else); never write into the music folder (`/Users/y/Music/Timbre Library`), caches only
in ~/Library/Application Support/Timbre; no Spotify name/logo/green; hover = Pointer system only; never
print secrets (Navidrome password lives in Keychain `timbre.navidrome`; Jev key below).
Do NOT launch GUI instances of Timbre (they steal focus and Yahia's copy is playing audio), do NOT kill
or signal his running Timbre, no osascript/activate. `sample <pid>` / `ps` on his running instance is
fine (read-only): `pgrep -f 'Timbre'`.
Swift 6 gotchas: GeometryProxy closures -> nonisolated static funcs; NotificationCenter closures must
not capture `note`.

GATE (every phase): `swift build -c release` with 0 warnings AND `swift test` all passing (today:
73 Swift Testing + 36 XCTest, 1 skip). Paste the tail of both. Render proofs: the repo already renders
views to PNG in tests (see RiverRowRenderTests / SpaceRenderTests and the LyricsLines render proof) —
add render proofs for every new visual and list their PNG paths in your report.

## Phase A — CPU (Yahia: "fix CPU first")
Measured on HEAD's release build, window visible: median 34%, p90 79% CPU (budget 15%; the build
before the ArtWorld merge was 20-27%). Immersive view with the lyrics page open, playing: steady 26-27%.
`sample` of that state: main thread time is SwiftUI graph churn (AG::Graph::propagate_dirty,
UpdateStack::update, Subgraph::update) plus AppKit layout every pass
(_updateConstraintsForSubtreeIfNeeded, _findAnySubviewNeedingAutoLayoutEngine) — i.e. something ticking
fast invalidates big SwiftUI bodies / NSHostingView layout, not GPU compositing.
Suspects to check first (prove with evidence, don't guess): CADisplayLink ticks in SpaceField.swift:391,
VibeView.swift:103, RiverLayerView.swift:189 — do their tick()s write @Observable/@State or call into
SwiftUI? Playback position observed by large views (Scrubber, LyricsPage index, NowPlayingBar
TimelineView 0.25s at NowPlayingBar.swift:167, AlbumDetailView TimelineView 20 fps at :345); hosting views
re-running constraints; ArtWorld (Views/ArtWorld.swift) layer updates triggered from SwiftUI.
Fix pattern: per-frame work lives in Core Animation / layer-hosting views with ZERO SwiftUI writes per
frame; fast values (position) are read only by the smallest leaf view that needs them; nothing ticks when
paused or when the window is hidden/occluded.
Measure before/after without a GUI launch: add a DEBUG-only counter (env `TIMBRE_PERF=1`) that logs body
evaluations/sec for the top-level views, and a test that hosts the immersive+lyrics and Home stacks
off-screen with a fake player ticking for ~2 s and asserts a ceiling on body evaluations (pick the
ceiling from your fixed numbers, with headroom). Target for the live check (done by the orchestrator
after you finish): visible+playing median <= 15%, paused+visible ~0-2%.

## Phase B — lyrics on screen
1. **Smooth the dark lyrics backdrop** (Yahia: "smoothen the blend but keep that dark background").
   LyricsPage.swift:63-71 draws a dark gradient behind the lyrics that shows a hard LEFT and TOP edge in
   the immersive view (ImmersiveView.swift:68-78) and the Now Playing panel. Keep the darkness, feather it
   on every side where it ends: one MULTIPLICATIVE mask (horizontal smootherstep x vertical smootherstep),
   the same technique as commit 92bd4de in NowPlayingPanel.swift (`eased` Gradient). Rule: no box may show
   an edge.
2. **Live fill on the current line** (Yahia: "real time tracking of the song needs fluid colouring and
   fill animation"). Today the current line just snaps from grey to white (LyricsLines opacity,
   `.animation(.easeOut(0.35), value: index)`). Make the current line FILL left-to-right as it is sung:
   sung part full white, unsung ~45% white, a soft feathered wipe edge (~2 words wide) faintly tinted with
   the album's hue from the existing palette (headings already take the hue of the album on screen).
   Timing: line start -> next line start; if the LRC has enhanced word timestamps (`<mm:ss.xx>`), fill
   per word instead (extend LRC.swift parsing, with tests). Lines that finish ease back to the past style
   (no snap); seek/pause/resume re-sync instantly. Multi-line wrapped lines fill line by line in reading
   order. The fill must be cheap: drive it with Core Animation (a mask layer animation with the line's
   duration, restarted on seek/pause) or a TimelineView scoped ONLY to the one current-line view — never
   re-render the whole lyrics list per frame. Phase A's perf test must still pass with lyrics open.
3. **Film-style subtitle line** (Yahia picked this). When synced lyrics exist and the full lyrics page is
   OFF, show the current line (with the same live fill) and a dim next line, centred, low over the album
   art in the Now Playing panel and the immersive view, like film subtitles; legible on any cover via a
   soft feathered dark scrim (no box edge). Crossfade line to line. The quote-bubble button still opens
   the full page (page on = subtitles hidden). Settings: "Show subtitles" toggle, default ON. Plain
   (unsynced) lyrics: no subtitle line.

## Phase C — lyrics for every song, matched by Jev (Yahia: "every song, Jev picks")
Existing chain (keep it): Lyrics/LyricsResolver.swift sidecar .lrc -> embedded -> Navidrome -> cache ->
LRCLIB. LRCLIBClient.lookup does /api/get, then on 404 /api/search and takes the FIRST result within 2 s
of the track length — that is the weak step (misses "feat.", "Remastered 2011", "[Explicit]", live/edit
cuts, artist aliases). Today only 5 songs have cached lyrics because lookups only run on play.
1. Query normalisation in plain code (tested): retry /api/search with a cleaned title/artist when the raw
   one returns nothing (strip feat./remaster/explicit/version suffixes, first artist only).
2. **Jev picks the candidate**: vendor `~/Projects/jev-kit/swift/JevKit.swift` (read its README; it is
   vendored, not a dependency). Hard gate first in code: only candidates within +/-2 s of the track length
   (a different cut drifts out of sync) — length is NOT Jev's job. Then one Jev `choice` over the
   survivors plus a "none of these is this recording" option; state = the track {title, artist, album,
   duration} and candidates {trackName, artistName, albumName, duration, hasSynced}. Route on confidence:
   >= act floor accept; below = treat as a miss (wrong lyrics are worse than none). Start the floor
   conservative (0.8) and calibrate it on a small held-out labelled set you build from the library (exact
   /api/get hits = known-correct positives; deliberately wrong pairings = negatives); report the
   calibration numbers. Log every decision to
   ~/Library/Application Support/Timbre/Lyrics/decisions.jsonl (track, candidates, choice, confidence,
   accepted). No key or Jev error -> fall back to today's first-within-2s rule; never crash, never block.
   Jev key: Timbre's own Keychain item service `timbre.jev`, account `typesafe`. Add
   `scripts/jev-key.sh` that seeds it from the existing item (`security find-generic-password -s
   net.prismlens.jev-cli -a typesafe -w`) with `-T` for dist/Timbre.app and ~/Applications/Timbre.app,
   never echoing it. Do not run that script yourself; tell the orchestrator.
3. **Library sweep**: a background, resumable, low-priority (utility QoS, sequential, ~1 LRCLIB request/s,
   existing User-Agent) pass that resolves lyrics for every track in the library, skipping tracks already
   cached; runs only while "Fetch lyrics online" is on; remembers misses with a retry-after (30 days) so it
   does not re-ask daily. Must not disturb playback or blow the CPU budget. Settings shows coverage:
   "Lyrics: N of M songs" and a quiet progress line while sweeping.

## Report back
Per phase: what you changed (files), the evidence for the CPU cause and the before/after body-eval
numbers, Jev calibration numbers, render-proof PNG paths, the gate tails, commit hashes. Anything
skipped or uncertain, say so plainly.
