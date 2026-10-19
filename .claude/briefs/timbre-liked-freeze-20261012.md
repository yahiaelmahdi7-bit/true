# Timbre: Liked Songs locks up after scrolling ~14 rows (live repro, not offscreen)
Repo: ~/Projects/timbre. Work in your worktree, based on branch live/scroll-photos-20261012 (installed build). Do NOT touch ~/Projects/timbre main checkout (DJ engine builder has uncommitted work there). Never launch/kill Yahia's Timbre in ~/Applications or steal focus; build a separately named copy to test.
## Symptom (Yahia, live, 1919x1080 window on 2nd display)
Open Liked Songs (358 songs), scroll down: around row 14-15 (bottom of first screen) it stops scrolling AND the whole app ignores all clicks/scroll. Same before and after commit 27c0b94 (lazy rows, ScrollState). Screenshot: hero gone, top shows a blank dark blurred strip (mini header bar without title/play).
## Evidence
- `sample` for 30 s while stuck: main thread 100% idle in nextEventMatchingMask (NSDefaultRunLoopMode-ish), never handling any event. CPU ~0. No crash report. Only one Timbre window; nothing occludes it.
- So: not a CPU hang. Suspects: events never reach the app (window lost key/mouse? an AppKit tracking/drag session, ignoresMouseEvents, a CA commit stalled in WindowServer), or SwiftUI stopped re-rendering (giant layer: ArtWorld frame geo.height+300 with feather 360 + Reveal clipShape; softTopFade; stagger; pointerOccluder; miniHeader).
## Task
1. Reproduce for real: run a test copy on screen (own bundle id / name), drive scrolling with CGEvent scroll-wheel events posted to its window, and detect the freeze (e.g. app stops logging scroll offset / window stops updating, check `CGWindowListCreateImage` of its window, check NSApp.keyWindow, isIgnoringMouseEvents). If screen capture is denied, use in-app os_log instrumentation.
2. Bisect the cause (try disabling ArtWorld parallax, Reveal clip, softTopFade, miniHeader, stagger one at a time).
3. Fix root cause; add a regression test if feasible. Gate: `swift build -c release` 0 warnings + `swift test` green (PerfTests.scrubberTicks... currently fails when display is asleep: environmental, note it).
4. Commit on your branch. Report: root cause with evidence, the diff, how you proved the freeze is gone with the live repro.
## Update 15:4x
- A prior attempt's on-screen copy /private/tmp/tfreeze/TimbreFreeze.app DID reproduce the lock (it froze and trapped Yahia's input). Yahia is AWAY now: you may drive the screen freely. Quit your test copy when done; never leave it running.
- During a freeze WindowServer sat ~45-52% CPU while Timbre sat at 0% idle in nextEventMatchingMask. Strong suspect: a layer WindowServer can't composite cheaply (blur/feather/material/huge offscreen frame) or a CA commit stall. Measure WindowServer CPU per bisect step.
- Base your work on branch live/scroll-photos-20261012 (git checkout it in your worktree).
- Do not run the main checkout's tests.
