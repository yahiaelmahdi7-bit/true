# Timbre: run on macOS 15 (Sequoia) + an install kit for another Mac

Work in a NEW git worktree branched from `release/20261012` (~/Projects/timbre.builders/release-20261012 — the full current build). Commit on your branch. Don't touch ~/Projects/timbre main checkout.

## Yahia: "we need it to set it up for macos15 so make a kit working for it"
Today Package.swift is `.macOS(.v26)` and package.sh writes LSMinimumSystemVersion from MIN_OS. Zero #available guards exist.

## Do
1. Lower deployment target to macOS 15.0 (Package.swift `.v15`, MIN_OS=15.0 in package.sh).
2. Build; for every API that is macOS 26-only (Liquid Glass `glassEffect`/GlassEffectContainer, new toolbar/tab APIs, Observation/SwiftUI additions, AVFoundation/AudioUnit additions, Foundation Models, etc.) add `if #available(macOS 26, *)` with a macOS 15 fallback that looks close (e.g. `.ultraThinMaterial` instead of glass). Prefer one small helper modifier per pattern (e.g. `.timbreGlass()`) over scattered checks. Keep macOS 26 behaviour identical.
3. Check runtime-only risks: Info.plist keys, entitlements, Keychain, ElevenLabs/DJ audio graph (AVAudioUnitTimePitch etc.), Swift Testing availability. Grep for `@available(macOS 26` in any dependency.
4. Kit: `scripts/make-kit.sh` → `dist/Timbre-macOS15-kit/` containing Timbre.app (universal arm64+x86_64 if the build supports it; say which), a `Install Timbre.command` double-click script (copies to ~/Applications, removes quarantine with `xattr -dr com.apple.quarantine`, opens it), and `READ ME.txt` (plain English: requirements macOS 15+, how to install, first-launch Gatekeeper note since it is signed with a local "Deck Signing" cert not notarised, where the library/settings live). Zip it as `dist/Timbre-macOS15-kit.zip`. No secrets in the kit (grep for keys; ElevenLabs key stays in Keychain, user enters on the other Mac).
5. Verify: `swift build -c release` 0 warnings; `swift test` passes (PerfTests.scrubberTicks flaky when display asleep); `vtool -show-build` / `otool -l` shows minos 15.0 on the binary; `codesign -v`; LSMinimumSystemVersion=15.0 in Info.plist; list every symbol the binary weak-links from 26-only frameworks if any. We have no macOS 15 machine — say clearly what is proven (compile/link/minos) vs unproven (actual run on 15).
Report: files changed, each 26-only API found + its fallback, kit path, what's proven/unproven. Don't install or launch on screen.
