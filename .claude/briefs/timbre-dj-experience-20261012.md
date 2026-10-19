# Timbre: DJ NATORE experience — Home spot, drifting picks carousel, prompt-to-queue chat, DJ brain, voice

Repo: ~/Projects/timbre (SwiftPM macOS app, Swift 6, `main`, LOCAL ONLY). Builds ON TOP of the DJ engine
(brief timbre-dj-engine-20261012.md): use `DJSession`, `BeatGrid`, `MixPlan` as they exist — read them first.
Yahia is a non-coder who directs; every decision below is his. Phases in order, atomic commits.

DISCIPLINE, HARD LINES, GATE: identical to timbre-dj-engine-20261012.md (copy them mentally: lane = timbre only,
never push/merge, gates in foreground, never launch GUI Timbre or touch his running copy, never print secrets,
no acquisition — the DJ uses ONLY tracks already in the library; ~/Projects/timbre-feed is off-limits; caches
only in ~/Library/Application Support/Timbre; hover = Pointer system only; no Spotify name/logo/green).
The time-to-sound test from the engine build must stay green. Render proofs (PNG) for every new visual.

PERSONA — **DJ NATORE**: smooth jazz-lounge voice, laid-back joint/stoner vibe. Unhurried, warm, low, few
words, dry mellow humour, never hype, never explains. Max ~2 short sentences per line. Sounds like a normal
chill guy: casual and generic, NEVER breathy, intimate, seductive or "late-night companion" (Yahia: creepy).
Example register: "Hey, it's DJ Natore. Got some easy ones lined up for you... just sit back, I got this."
No explicit drug references in lines (the vibe carries it: "easy", "slow it down", "drift", "smoke-blue light").

## Phase 1 — DJ brain (code + Jev, no LLM prompt-and-parse)
- Candidate pool, all from the library: liked/favourites; rarely or never played ("discovery"); "might like" =
  similar to liked by artist/album/genre co-occurrence + BPM/energy proximity (BeatGrid + Envelope).
- `nextProvider` for DJSession: code shortlists by BPM fit (<=6% or half/double), energy arc of the set, artist
  spacing (reuse PlayQueue.suggestion rules), then Jev (vendored jev-kit, same pattern as the lyrics matcher:
  narrow typed question, route on confidence, log to decisions.jsonl) picks among the top 5 for the set's
  mood/prompt. Below the confidence floor -> code's top pick. Calibrate the floor on held-out cases you label
  from the library; report the numbers.

## Phase 2 — prompt-to-queue chat
- A single text field in the DJ spot: "watching the sunset by the golf course" -> a set.
- Flow: code pre-filters the pool to <=150 candidates; Jev scores each candidate's fit to the prompt from its
  metadata (title, artist, album, genre, year, bpm, energy summary) in batched calls; code takes the top ~25 and
  ORDERS them for flow (energy arc + BPM-compatible neighbours) -> DJSession.start.
- Mix the pool on purpose: roughly half liked, a third discovery, the rest might-like (tunable constants).
- The DJ answers with one persona line (Phase 4) and the queue appears. Empty/garbage prompt -> a calm reply,
  no crash, no empty set.

## Phase 3 — Home: the DJ's living spot + drifting picks carousel
- Top of HomeView, above the shelves. The spot: DJ NATORE's name, a living presence that breathes with the
  music (reuse the Envelope/Vibe energy; Core Animation driven, NOT SwiftUI per-frame state), a status line
  ("easing from X into Y"), the chat field. Idle when nothing plays: slow breathing.
- Carousel row of DJ picks = MIXED mood sets ("Late-night Marley", "Sunday slow burn", "Deep cuts you skipped")
  AND artist seeds. 8-12 cards, reshuffled every Home visit, built from the library by code (mood names from a
  handwritten template bank filled with real artists/genres — no LLM). Cards = cover collage + title.
- Motion: continuous slow drift (CA layer animation, ~20-30 px/s), pauses on hover (Pointer system) and when
  the window/row is not visible or the app is inactive (same pattern as VibeHostView.refresh). Seamless loop.
- Click a card -> DJSession.start(set, introVoice:) with an intro that names the set.
- One borderless HD black window aesthetic; headings in album hue; UI lines black/white; no box may show an
  edge (use Feather). CPU: Home idle with the carousel drifting must cost <= 5% CPU; measure + state method.

- Discover Weekly shelf (added 2026-10-12): timbre-feed now writes a weekly `Playlists/Discover Weekly.m3u8` of NEW music
  (tracks under `<library>/Discovery/`). Show it on Home as its own shelf right under the DJ spot, each card tagged "New";
  if the playlist is missing or empty, the shelf is hidden (never an empty state). Starring a track there works as usual.

## Phase 4 — voice (ElevenLabs)
- Voice id: cjVigY5qzO86Huf0OWal ("Eric", ElevenLabs premade; Yahia's pick 2026-10-12). Model eleven_multilingual_v2, stability 0.5, similarity_boost 0.75, style 0.0, speed 0.95 — EXACTLY the settings of the sample he approved. Do not raise style or drop stability: that is what made earlier rounds sound breathy/creepy.
- Key: Timbre gets its own Keychain item `timbre.elevenlabs` seeded by a new scripts/elevenlabs-key.sh copied
  from scripts/jev-key.sh (find the existing ElevenLabs Keychain item True/Nova uses; never print the key).
- Line bank: ~40 handwritten persona lines with slots (intro per set, "next up" bridges, prompt replies),
  code fills slots. Lines are spoken over the incoming song's intro with the music ducked (engine API).
- Pre-generate the next line while the current song plays; cache clips in App Support by text hash.
  Offline/no key -> the line shows as a caption only, music never waits.

## Report back
Per phase: files, Jev calibration numbers, render-proof PNG paths, CPU numbers + method, a 60 s offline-rendered
WAV of an intro + first transition for Yahia to listen to, gate tails, commit hashes. Uncertain = say so.
