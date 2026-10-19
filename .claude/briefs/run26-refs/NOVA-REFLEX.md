# Nova's reflex, and her hands

*Landed 2026-09-21/22. Code: `Sources/Axon/Nova/JevClient.swift`, `NovaReflex.swift`,
`ComputerUse.swift`; the voice seam in `Voice/VoiceEngine.swift` (`readReflex`,
`handleAmbientUtterance`), the spotter in `Voice/WakeWord.swift`, the routing closure in
`Chrome/RootView.swift` (`voice.routeSpokenCommand`, `executeDirective` → `executeAct`).
Tests: `Tests/AxonTests/NovaReflexTests.swift`, `ComputerUseTests.swift`.*

## In one paragraph

Every sentence Nova hears is now read ONCE, in about 350 ms, by TypeSafe's **Jev** — a model
that answers typed questions with probabilities and never writes prose. That read says whether
the sentence was a desk command, work for an agent, a question for her, dictation, or not for
her at all; which desk verb; which seat; whether the speaker was even talking to the computer;
whether the sentence was finished; and whether it was "stop". Code then acts on the answer
through the desk's existing execution path, or falls through to the older chain (deterministic
parsers → Haiku dispatcher → dictation) exactly as before. The same model, given a numbered
table of what's on screen, picks the next click / keystroke / field — that is the computer-use
loop. Jev decides; code lifts names, values and geometry; the slow brains (Haiku, Hermes) only
ever write words.

## What Jev is here, and isn't

- **Is:** the judgment on the hot path. One `POST /v1/systemone` with the utterance (or the
  screen table) as `state` and several questions asked at once (fan-out). Each `choice` answer
  comes with a probability per option and a confidence; each `noul` is P(yes).
- **Isn't:** a writer. It never composes the prompt a seat receives, never answers a question,
  never fixes a misheard word, never produces a coordinate or a selector. Where free text is
  needed (a reply body for a screen errand, the crew digest, a relay brief) the slow brain
  writes it and Jev only ever *selects* among candidates code found.
- **Jagged edges designed around** (docs.typesafe.ai/model-jaggedness/jev-1.13): literal
  reading (every question states its exact condition and has examples); no counting (nothing
  numeric is asked); accuracy falls with irrelevant state (the reflex sees the roster, the
  last three turns and where you're looking — never the canvas brief; the screen table is
  capped at 140 rows, enabled/visible first); state is trusted (screen text is data — the
  loop only ever acts on rows this code observed).

## The reflex spec (`NovaReflex.request`)

State: `utterance`, a note that it's ASR output, `crew` (name, 140-char skills, window open,
backend), `user_is_looking_at`, `recent_conversation` (≤ 6 lines).

| question | type | answers |
|---|---|---|
| `kind` | choice | desk_control · agent_task · question_for_nova · dictation · not_for_nova |
| `addressed` | noul | talking TO Nova/the computer? |
| `verb` | choice | the fixed desk vocabulary (below) or none |
| `seat` | choice | roster names · everyone · none — "the seat ADDRESSED, not one merely mentioned" |
| `tier` | choice | haiku · sonnet · opus · fable (the dispatcher's rubric) |
| `complete` | noul | a finished sentence? (mid-thought hold) |
| `interrupt` | noul | "stop / shut up / never mind"? |
| `needs_code` | noul | would carrying it out change code? |

Verbs. *Direct* (no free text): open, close, launch_crew, clear_desk, status, recenter,
show_office, hide_office, submit, read, run_tests, build, git_status, push, restart_seat,
focus_seat, screenshot_full, debrief, relaunch_self. *Query* (code lifts the noun phrase):
open_app, quit_app, relaunch_app, open_site, play_video, open_project, **do_on_screen**,
**relay**, **poll_crew**.

## Every threshold, and why

All thresholds are floors on ACTING, never on thinking: below a floor the chain continues as it
did before the reflex existed, so the worst the reflex can do is nothing.

| rule | floor | why that number |
|---|---|---|
| `isPlainDictation` | kind ≥ 0.6, interrupt < 0.5 | replaces the dispatcher's "nil → dictation" minus the 3–20 s wait; a wrong "dictation" costs one sentence typed where the cursor is, the same as before |
| `isDirectDeskControl` | kind ≥ 0.5, addressed ≥ 0.5, verb ≥ 0.6 | a desk verb is reversible or observed; the executor's own nil ("no such app") keeps the chain going |
| `isQuestion` | kind ≥ 0.65, addressed ≥ 0.5 | skips a dispatcher round-trip whose only output was "that's a question" |
| `isConfidentSeatTask` | kind ≥ 0.7, addressed ≥ 0.7, **seat ≥ 0.8** | the highest floor in the type: a task in the wrong agent's terminal is the one voice mistake nothing undoes; below it the Haiku dispatcher gets the sentence with the reflex read as a prior |
| `isCrossKindVerb` | verb ≥ 0.8, addressed ≥ 0.6, verb ∈ {relay, poll_crew, do_on_screen}; relay only receiver-first | "tell Jeff what Ben found" scores as a task for Jeff AND a relay — the verb is what was meant; "cruz review what ben did" also scores relay but is a verbatim route, so a relay must open with tell/give/pass/hand/send |
| `isMidThought` | complete < 0.25 | only ever HOLDS the take and reopens the mic; a wrong "unfinished" costs a beat, a wrong "finished" truncates you |
| `isInterrupt` | interrupt ≥ 0.85 | halts her voice and the screen loop; the words are dropped, never typed |
| `isSureDeskControl` | kind ≥ 0.8, addressed ≥ 0.8 | when nothing could run a sentence this sure was a desk command, she SAYS so instead of dictating it into a pane |
| `isAmbientCommand` | kind ≥ 0.7, addressed ≥ 0.8, verb ≥ 0.8, verb ∈ `ambientSafeVerbs` | words with no wake word: two independent strong judgments AND a verb whose false positive is a window opening |

### The ambient safety gate

The always-on spotter (`WakeListener.onUtterance`, `UtteranceSplitter`: 1.1 s quiet gap,
≥ 2 words) hands every sentence in the room to the reflex. From there only `isAmbientCommand`
may act. `ambientSafeVerbs` (widened on the user's order): open/quit/relaunch apps, open sites,
play media, open projects and seats, focus/read seats, status, screenshots, debrief, and
`do_on_screen` — the last only when the goal has no consequential word (send/pay/delete/sign
in/install…). Still absent from ambient: anything that lands words in a live pane (route,
broadcast, relay, submit), git commit/push, clear_desk, restarts. While Nova is speaking, the
only ambient verdict honoured is `isInterrupt` (her own voice must never become a command).

### Talking to sessions

- **Verbatim routing.** A confident addressed task goes to the named seat as spoken, minus the
  address and the leading name (`taskWithoutSeat`): "ben can you refactor the uploader" →
  Ben's pane gets "can you refactor the uploader". One-edit mishears count ("been", "jef").
  A *different* member's name leading the sentence is a conflict → nil → dispatcher.
- **Setting up.** "open Ben in prism" / "set up a claude session in the trading repo" /
  "launch Ben and Cruz" compose to `[open_project, open|launch_some]` (`actions(for:seats:)`);
  the project is opened FIRST and the seat spawns into that zone explicitly; a project miss
  (unknown, ambiguous) skips the seat — Ben in the wrong repo is the outcome this prevents.
- **Read + follow-up.** `read` speaks a seat's tail and remembers it (`SeatReadMemory`, 10
  min) so "what did he mean?" is answered from the same screen.
- **Relay** ("tell Jeff what Ben found", "pass Ben's result to Cruz") → the existing relay
  executor (distilled brief → handoff prompt in the source's zone).
- **Poll** ("ask everyone if their tests pass and tell me who said what") → broadcast, 25 s,
  read every live tail, one-line-per-seat digest by the one-shot brain.

## Computer use (`ComputerUse`)

**Look.** Frontmost app → focused window → AX walk (≤ 2,000 nodes / 0.6 s, tables by visible
rows) → `prune` keeps actionable roles, labels each row (title → labelling element →
description → placeholder), marks password fields unreadable, drops < 4 pt rectangles → the
whole menu tree as off-screen rows (depth 4, ≤ 150). If the tree is thin (< 3 rows: Electron,
Spotify, games) a capture of *that window* (right display) is OCR'd with Vision and merged
under the AX rows as clickable "seen by camera" text; the capture is deleted on every return
path.

**Decide.** ONE request: `operation` (click · type_text · press_keys · open_app · press_enter ·
scroll_down/up · wait · done · blocked) plus speculative heads `click_target`, `type_target`,
`keys_target` (a fixed shortcut table), `app_target` (apps the goal names, found by code),
`type_value` (which user-given value), and on the first look `scope` (this_window · other_app
· multi_step). Only the head matching the chosen operation is read; an index the table doesn't
hold, a shortcut id not in the table, an app not offered — all nil, never trusted.

**Act.** AXPress on the live element after re-reading its geometry (moved > 40 pt = stale, no
press); fallback click at the centre; typing through `TextInjector`; shortcuts as CGEvents.

**Plan.** `scope = multi_step` (≥ 0.5) → the one-shot brain writes 2–6 lines (`Plan`), the ONE
place free text is generated; each line runs through the loop with the plan in state and its
`text` as the value to type. `done` on a line advances; `done` on the last line ends.

**Gates.** ≤ 40 steps · operation confidence ≥ 0.4 · target ≥ 0.4 · stop after 2 unchanged
tables following an action · consequential labels (send, submit, pay, buy, delete, remove,
confirm, sign in, install, allow, checkout, discard, publish, post…) and ⌘↩ park the press for
one spoken "go ahead" (30 s; answered ahead of every parser via `NovaTools.confirmationPolarity`)
· password fields never typed · "stop" (take or ambient) cancels between steps.

**Record.** Unified log category `computer-use` (operation, target, confidence, ms) and a JSON
per run in `~/Library/Application Support/Axon/ComputerUse/` (table, answers, action, note).

## Latency and cost, honestly

Model time is ~100 ms, but from this Mac the TCP connect to api.typesafe.ai alone is ~270 ms:
a warm call measures **320–600 ms** (calibration p50 372 ms, p90 427 ms; screen steps p50
352 ms). Fine on the take path (whisper is slower) and the reflex is bounded at 0.9 s, screen
steps at 2 s — a miss returns nil and the older chain runs. `JevClient.prewarm()` opens the
TLS connection at voice start-up. Cost: $0.042 per million input tokens; a reflex read is
~600 tokens (≈ $0.000025), a screen step ~1–2k (≈ $0.0001); a 12-step errand ≈ $0.001.

## Running the calibration

```
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
TYPESAFE_API_KEY="$(security find-generic-password -a typesafe -s net.prismlens.axon -w)" \
  swift test --filter "NovaReflexTests|ComputerUseTests" \
  -Xswiftc -F$FW -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
```

Without the key the live cases skip and only the pure tests run. Last run (2026-09-22): 39
tests green; reflex kind 32/36 (misses: "stop talking" — caught by the interrupt head at 94%;
"the onboarding copy needs a warmer tone" at 63% agent_task, below every acting floor; two
sentences whose *verb* is right and runs via `isCrossKindVerb`), verb 18/19, seat 9/9;
computer use operation 13/14, target 11/11.

Watching it live:

```
/usr/bin/log stream --level info --style compact --predicate 'subsystem == "net.prismlens.axon"'
```

Use the full path: in zsh `log` is a builtin (it lists logged-in users) and fails silently
with "too many arguments" — which is exactly why the first look at these logs came back empty.
Categories: `reflex` (one line per read), `wake` (spotter state + every flushed utterance),
`computer-use` (one line per step).

## Adding a verb

1. Add it to `NovaReflex.directVerbs` (no free text) or `queryVerbs` (code lifts a phrase) with
   a one-line description and two spoken examples — the description IS the criterion Jev reads.
2. If it needs a phrase, teach `query(for:in:)` (or a dedicated lifter like `projectPhrase`)
   to extract it deterministically; add the verb to `ambientSafeVerbs` only if a false positive
   is a window opening, never work landing in a pane.
3. Give the executor a branch (`executeAct` in RootView, or `directive(for:)` when it maps to
   an existing `DeskDirective`).
4. Add a pure test for the lifting and a labelled utterance to the calibration set; run it and
   read the table before trusting the threshold.

## Verified live vs pending

See the session report; the running bundle must include this build for the ambient path and
the screen loop to be observed (`./scripts/package.sh debug`, then "ship yourself" when the
crew is idle).
