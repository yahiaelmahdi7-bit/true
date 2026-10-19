# True: run on macOS 15 (Sequoia) + install kit for another Mac

Repo ~/Projects/true (the True app, NOT Timbre). Work in a git worktree (other sessions edit this repo); commit on your branch, don't push, don't touch main.

## Yahia: "make one for true kit not the timber app" (a macOS 15 kit)
Package.swift is `.macOS("26.0")`; ~15 files in Sources use glassEffect / macOS-26 APIs. Deps: swift-argument-parser, SwiftTerm (check their min OS). Packaging: scripts/package.sh.

## Do
1. Lower deployment target to macOS 15.0 (Package.swift + LSMinimumSystemVersion in package.sh).
2. Build; every macOS 26-only API (Liquid Glass glassEffect/GlassEffectContainer/.glass button style, new toolbar/window/tab APIs, Foundation Models, Speech/SpeechAnalyzer, new AVFoundation etc.) gets `if #available(macOS 26, *)` with a close macOS 15 fallback (`.ultraThinMaterial` + hairline for glass). Use a few shared helper modifiers, not scattered checks. macOS 26 behaviour must stay identical. If a whole feature can't exist on 15 (e.g. on-device model / SpeechAnalyzer for Nova), degrade gracefully with a clear in-app message, never crash.
3. Runtime risks: entitlements, Info.plist usage strings, Keychain, LaunchAgents/helpers, embedded CLIs, accessibility/screen-recording permissions, hard-coded paths to Yahia's machine (~/.claude, /Users/y …) — list them; make missing paths non-fatal.
4. Kit: `scripts/make-kit.sh` → `dist/True-macOS15-kit/` with True.app (universal arm64+x86_64 if possible; say which), `Install True.command` (copy to ~/Applications, `xattr -dr com.apple.quarantine`, open), `READ ME.txt` (plain English: macOS 15+, install steps, Gatekeeper note — locally signed not notarised, which permissions it will ask for and why, what needs setting up on the other Mac e.g. API keys, Claude Code install). Zip → `dist/True-macOS15-kit.zip`. NO secrets in the kit: grep the bundle for keys/tokens/emails.
5. Verify: `swift build -c release` 0 warnings; tests pass (note known flaky ones); `vtool -show-build` minos 15.0 for each arch; `codesign -v --strict`; Info.plist min 15.0; list weak-linked 26-only symbols and confirm each is guarded. No macOS 15 machine exists — state proven (compile/link/minos) vs unproven (actual run).
Report: branch+commit, files changed, each 26-only API + fallback, features degraded on 15, kit path, proven/unproven. Don't install or launch on screen.
