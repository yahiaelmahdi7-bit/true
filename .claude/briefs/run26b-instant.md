# Run 26b — Instant Nova (speed pass on this same branch, before merge)

Yahia, 2026-10-10: "If I can drag my mouse and do the same action faster, that's useless… mid speech, it happens and
then follows what to do next." Decided: **act mid-sentence; undo on "no"**. The bar: a common command's hand STARTS
≤ 30 ms (in-process) after the partial transcript that completes it — live that is ~0.3–0.5 s after the spoken word.

## Where the time goes today (read from the code — fix every one)
1. `NovaEngine.take()` waits a fixed 1.0 s of quiet; `DynamicEndpointing` was lifted but is unused.
2. On wake, `WakeListener.standDown()` releases the mic and a separate `AudioRecorder` starts → a handoff gap; words
   said in the same breath as "Nova" can be lost.
3. The whole clip is transcribed in batch after recording ends (`SpeechAnalyzerTranscriber`, finals only, new per take).
4. `NovaSpeculative.race`: the brain task awaits `reflexTask.value` → sequential, not parallel (`headStart` unused).
5. `end()` speaks up to 8 words after every direct act.
6. `AnthropicClient` uses an unwarmed `URLSession.shared`; nothing prewarms Jev or Anthropic at wake.

## Build (one name per thing — add these to docs/kb/glossary.md)
- **Live stream** — keep the on-device `SFSpeechRecognizer` stream (`WakeListener`) running THROUGH a take: no
  stand-down/recorder handoff for commands. Wake word or held hotkey marks the stream *addressed*; the words after
  "Nova" in the same partial are the command. Partials drive the HUD live (closes the "live partial transcript" gap).
  Bias the recognizer: `contextualStrings` += installed/running app names (cap ~60, recent first) + True roster/pane
  names. Keep `AudioRecorder` + `SpeechAnalyzer` only if a payload needs a better final (send_to_pane / spawn_agent
  bodies) — or drop it if the stream's final is good enough; your call, write it in the ADR. Keep the existing incident
  comments and behaviours (engine rebuild after take, watchdog, recognition-task restart).
- **Instant lane** — new pure, testable `Nova/NovaInstant.swift`: a local matcher run on every addressed partial. No
  network. Verbs: open/launch/switch to/show `<app>`; hide `<app>`; quit `<app>` (graceful `terminate()` only, never
  force — the app's own save prompt protects work); focus/show `<True pane or agent>`; volume up/down/mute/set;
  play/pause/next/previous; scroll up/down (frontmost); screenshot; open `<known site>` (small fixed table). App index
  from /Applications, /System/Applications, ~/Applications + running apps, with aliases (chrome, code/vs code,
  settings → System Settings, …). Full-name matches only; if the match is a strict prefix of another candidate
  ("Music" vs "Music Memos"), wait for the next partial or 250 ms. Running app → `NSRunningApplication.activate()`.
  Every act still goes through `NovaHands` + `NovaGate` — the lane decides, the gate still guards.
  **Addressed only**: ambient speech never fires the lane (a TV saying "open Safari" does nothing), and partials heard
  while Nova itself is speaking are ignored (only "stop" barges in).
- **Clause** — split the addressed partial on "and then", "then", "and", "after that", ",". Dispatch each clause the
  moment it is complete, while later words are still arriving. Clause N+1 dispatches only after clause N's hand has
  started. A dispatched clause never dispatches again as partials revise (key: clause index + normalized text); if its
  text later changes materially, treat it as a correction (undo, then redo).
- **Undo record** — each instant act pushes one (depth 3, 8 s TTL): open/switch → re-activate the previous frontmost app
  and, if Nova launched the app, terminate it gracefully; focus pane → refocus previous; volume → restore; play/pause →
  toggle back; quit → relaunch. A clause that STARTS with "no", "nope", "not that", "undo", "actually", "I mean",
  "wait no" while a record is live → undo the last act, then run the rest as a new clause ("open Safari — no, Chrome"
  → Safari undone, Chrome opened). "No" anywhere else is ordinary words.
- **Rest of the sentence: parallel and early.** Clauses the lane can't match go to the reflex AND the brain at the same
  instant — fix `race` so the brain starts at t0 and never awaits the reflex; drop the prior (it can't be injected into
  an in-flight request). Reflex clears its acting floor → cancel the brain. **Eager end-of-turn:** when the addressed
  partial has been unchanged ~250 ms, start reflex+brain on the unhandled text, telling the brain what the lane already
  did ("Already done: opened Safari"); new words → cancel and restart (cap 3 restarts per turn). The final end-of-turn
  uses `DynamicEndpointing`, not the fixed 1.0 s. Hotkey release = end of turn immediately.
- **Feedback never waits.** Instant-lane and reflex direct acts: a soft act earcon (not "Tink" — that is wake) + the
  HUD line ticked; NO spoken confirmation unless the act returns information (status, read_pane) or fails. Brain
  speech unchanged (streamed sentence by sentence).
- **Warm wires.** One shared `URLSession` (HTTP/2 keep-alive) for Jev and Anthropic; on wake / first addressed word,
  prewarm both TLS connections (for Anthropic a keyless request such as `HEAD https://api.anthropic.com`). Key never logged.
- **Measure.** Per act: `clause_to_act_ms` (completing partial → hand started) and, where `SFTranscriptionSegment`
  timestamps allow, `word_to_act_ms` (spoken word end → hand started); reflex/brain ms per path. Settings → Nova
  "Show timings" prints the ms on each HUD line. The runs JSON gets the same fields (still no transcript text).

## Tests (pure, no mic)
App index + aliases + prefix-wait · clause splitter over a recorded partial sequence with revisions · no double
dispatch · "open Safari no Chrome" undo sequence · ambient never fires the lane · partials during Nova speech ignored ·
race starts the brain at t0 (fake reflex 400 ms → brain started < 20 ms) · eager end-of-turn cancel/restart cap ·
dispatch latency: 50 partials through the lane with fake hands, assert hand started ≤ 30 ms after the completing
partial — report the measured p50/p95.

## Gate, docs, report
Same three gate commands from docs/kb/conventions.md; paste the tails. Update SPEC "Run 26" (instant lane, clauses,
undo), docs/kb/decisions.md (supersede the "brain waits up to 0.9 s" ADR), glossary, docs/kb/security.md threat
model (mic-only lane, addressed-only, self-speech ignored, quit is graceful). NOT in this pass: screen hands
(`do_on_screen` etc.) — keep them on the roadmap. Commit on this branch only; never main; never launch True.app; never
weaken an existing test. Report: files, commits, gate tails, in-process latency p50/p95, what is unverified live.
