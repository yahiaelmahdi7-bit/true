# Timbre: DJ NATORE engine — guard instant playback, beat grid, two-deck beat-matched mixing

Repo: ~/Projects/timbre (SwiftPM macOS app, Swift 6, branch `main`, LOCAL ONLY). HEAD 4a8b02f.
Yahia is a non-coder who directs; he picked every decision below. Do the phases IN ORDER, one commit
per logical step. Report at the end with the gate output pasted.

WHAT WE ARE BUILDING (whole feature; YOU build only the audio core, phases 0-2):
A DJ called **DJ NATORE**. Click a DJ pick on Home -> DJ NATORE says a short intro (ElevenLabs voice) ->
a set plays where every song blends into the next, beats locked, bass handed over cleanly. A later
builder adds the Home carousel, prompt-to-queue chat, the DJ brain and the voice; it codes against the
API you define in Phase 2, so keep that API exactly as specified (extend, don't rename).

DISCIPLINE (non-negotiable):
- Lane: ONLY ~/Projects/timbre (Sources/, Tests/, scripts/). Never touch other repos (esp. ~/Projects/timbre-feed).
- Commits: atomic, message says what+why, end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  NEVER push (no remote by design), NEVER merge, NEVER 'ship'.
- Gates in the FOREGROUND. No background shells, watch modes or until-loops.
- 'done' = you ran the gate and pasted passing output. Never report a state you didn't verify.
- If blocked: say BLOCKED + one line why. No extra scope.

HARD LINES: no acquisition (never fetch audio; the DJ uses ONLY tracks already in the library); never
write into `/Users/y/Music/Timbre Library` (read-only); caches only in ~/Library/Application Support/Timbre;
no Spotify name/logo/green; never print secrets. Do NOT launch GUI Timbre, do NOT kill/signal Yahia's
running copy (`~/Applications/Timbre.app`), no osascript. `sample`/`ps` on it is fine.
Swift 6: GeometryProxy closures -> nonisolated static funcs; NotificationCenter closures must not capture `note`.

GATE (every phase): `swift build -c release` 0 warnings AND `swift test` all passing (today 97 Swift
Testing + 36 XCTest, 1 skip). Paste both tails.

## Phase 0 — protect instant playback FIRST (it is Timbre's strongest feature)
Today: one AVAudioEngine + one AVAudioPlayerNode in Sources/Timbre/Audio/AudioPlayer.swift.
- Add a time-to-sound test: from `AudioPlayer.play(_:in:)` to the first rendered NON-SILENT buffer
  (tap/manual render; fixture audio generated in-test, never Yahia's files). Measure the current baseline
  (median of 10), then set the budget at baseline x 1.25 and record both numbers in the test comment.
- This test must stay green through every later phase. The normal (non-DJ) play path must remain
  behaviourally identical: the DJ is a separate path, not a rewrite of play().

## Phase 1 — beat grid for every song (offline analysis, cached)
- `BeatGrid { bpm, firstDownbeat (s), beatsPerBar = 4, beats: [Double], downbeats: [Double],
  phrases: [Double] (8-bar starts), introEnd, outroStart, confidence 0-1 }`. Codable, cached per file
  hash in App Support (follow EnvelopeAnalyzer's cache pattern; extend it, don't duplicate decoding).
- Method: onset strength (spectral flux, ~100 Hz hop) -> tempo by autocorrelation in 70-180 BPM with
  octave correction -> beat phase by dynamic programming (Ellis 2007) -> downbeat by low-band accent per
  bar position -> phrases every 8 bars from the strongest downbeat. introEnd/outroStart = edges of the
  steady-energy body (use the existing Envelope).
- Scheduling: analyse the current queue first, then a background library sweep like LyricsSweeper
  (utility QoS, resumable, pauses while a song is starting — never compete with time-to-sound).
- VALIDATE ON UNSEEN DATA: read BPM tags (ID3 TBPM / Vorbis BPM) from library files READ-ONLY. Tune on
  at most half of the tagged tracks; report on the other half: % within 2% of tag, octave-error %, count.
  Also deterministic synthetic fixtures (click/kick tracks at 96/120/124/128/174 BPM, known phase) in tests:
  beat positions within 10 ms. If fewer than 20 tagged tracks exist, say so and rely on fixtures.

## Phase 2 — two-deck DJ mixing (separate path)
Yahia's decision: **stretch only in the mix.** Outside a transition every song plays at its true speed,
untouched lossless.
- Same engine, new nodes: deckA/deckB AVAudioPlayerNode -> AVAudioUnitTimePitch -> AVAudioUnitEQ (low
  shelf for bass swap) -> mainMixer; plus a voice node with ducking. Normal node untouched.
- Transition plan (pure, testable struct `MixPlan` from two BeatGrids): exit on an outgoing phrase start
  (16 bars before outroStart, fallback 8) ; incoming enters at its phrase/intro downbeat, scheduled
  sample-accurately (AVAudioTime) so its downbeats land on the outgoing downbeats; overlap 8-16 bars;
  incoming rate = bpmOut/bpmIn clamped to ±6%; after the outgoing fades, glide incoming back to 1.0 over
  8 bars. Equal-power volume curve; bass swap on the middle downbeat (incoming bass off before, outgoing
  bass off after). If tempos differ >6% or either grid confidence < 0.5: no stretch, cut on a downbeat
  with a 1-bar fade (log why).
- API (MainActor, @Observable), exactly:
  ```swift
  final class DJSession {
      enum Phase { case idle, intro, playing, mixing }
      private(set) var phase: Phase
      private(set) var current: Track?; private(set) var upNext: Track?
      var nextProvider: ((_ current: Track, _ history: [Track]) async -> Track?)?  // DJ brain plugs in here later
      func start(_ tracks: [Track], introVoice: URL?) async  // plays voice ducked over first song's intro
      func enqueue(_ tracks: [Track]); func skip(); func stop()  // stop returns to the normal player
  }
  ```
  While a set plays, the existing Now Playing UI, scrubber, lyrics sync and play/pause must keep working
  (drive AudioPlayer's observable state or make them read the active source — your call, explain it).
- PROOFS: offline-render (manual rendering mode) transitions to WAV in /tmp/timbre-dj/:
  (a) synthetic 120->124 BPM pair: measure max beat offset across the overlap by onset cross-correlation,
  must be <= 10 ms; (b) 3 real library pairs chosen by you (different tempos) rendered for Yahia to
  LISTEN to — list paths + the MixPlan for each (exit/entry times, rate, swap bar).
- CPU: one DJ set must not add more than ~5% CPU over normal playback (measure with a render-time or
  `ps` proxy; state the method).

## Report back
Per phase: files changed, time-to-sound baseline + budget, beat-grid held-out accuracy table, MixPlan
for each listening proof + WAV paths, measured beat offset, CPU method + number, gate tails, commit
hashes. Anything skipped or uncertain, say so plainly.
