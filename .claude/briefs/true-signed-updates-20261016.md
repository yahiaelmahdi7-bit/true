# True — signed updates, install-on-quit, steady checks (v1.1.3 updater hardening)

Repo: ~/Projects/true (private; public tree is generated from scripts/public/). Work in your worktree, commit there, do NOT push anywhere, do NOT touch ~/Projects/true-public.
Existing code: Sources/True/Model/Updater.swift (download, checksum, bundle-id/version/minOS/codesign checks, atomic swap + restore),
Model/UpdateLogic.swift (pure logic, `interval`), Views/RestartPill.swift, Settings/TerminalSettings.swift + Views/SettingsView.swift,
scripts/public/scripts/package.sh (writes TrueUpdateRepo into Info.plist), scripts/public/.github/workflows/release.yml
(uncommitted local change = one-click workflow_dispatch + checks + `verify` job; commit it first as-is, then build on it).
Auto-update runs only when Info.plist has TrueUpdateRepo (public builds). Keep that.

## 1. Ed25519-signed updates (key never on GitHub)
- Use CryptoKit `Curve25519.Signing`. Signature covers the exact bytes of True-macOS.zip. Asset: `True-macOS.zip.sig` (base64, single line).
- Public key embedded in Info.plist as `TrueUpdatePublicKey` (base64 raw 32 bytes) by package.sh from env `TRUE_UPDATE_PUBKEY`
  (stored as a non-secret GitHub Actions *variable*, `vars.TRUE_UPDATE_PUBKEY`). Release build MUST fail if it is empty.
- Updater: if TrueUpdatePublicKey present -> require .sig, verify before ANY unpack/swap; missing/invalid sig = refuse, log, no pill.
  Keep the existing checksum + bundle/version/minOS/codesign checks too. Pure verify function in UpdateLogic with tests
  (valid sig, tampered zip, wrong key, missing sig, malformed base64) using throwaway keys generated in the test.
- scripts/gen-update-key.sh: generates keypair (small swift script or `swift -e`/CryptoKit), stores private key in login Keychain
  (`security add-generic-password -s true-update-signing -a release`), refuses if one exists, prints the public key + the exact
  `gh variable set TRUE_UPDATE_PUBKEY --repo yahiaelmahdi7-bit/true-terminal --body ...` command. Never write the private key to disk or stdout.
- scripts/sign-release.sh <version>: waits for/locates the DRAFT release vX, downloads zip + .sha256, verifies checksum and that the
  app's Info.plist TrueUpdatePublicKey matches the Keychain key's public half, signs, uploads .sig, then `gh release edit --draft=false --latest`.
  Then re-downloads the published zip + sig and verifies the signature. Put both scripts under scripts/public/scripts/ so they ship in public repo.
- release.yml: publish job creates the release as `--draft` (still all checks). Replace the `verify` job (it can't see drafts' Latest)
  with a separate workflow `verify-release.yml` on `release: [published]` that downloads zip+sig, verifies the Ed25519 sig with the
  embedded public key (small swift script), checksum, plist, codesign, and that it is Latest.
- Transition: v1.1.2 clients don't know sigs; they still update via checksum path, so the zip/sha256 asset names must not change.

## 2. Install on quit, silently
- When an update is downloaded + verified, stage it (already exists). New setting "Install updates automatically" (default ON in public).
  ON: install during app termination (applicationShouldTerminate / willTerminate path): run the existing atomic swap + restore; never block
  quit more than a few seconds; if it fails, keep old app and retry next quit. The next launch is the new version, no relaunch forced.
  Keep the restart pill as an optional "restart now" for the impatient (subtle). OFF: current behaviour (pill only).
- Never install while a pane has a running foreground process if termination is a crash/forced; only on normal quit.

## 3. Steady check rhythm
- Check at launch (after ~30 s delay) and every 24 h while running (`UpdateLogic.interval`), with jitter; persist last-check date so
  relaunches don't re-hit GitHub within 1 h. Respect GitHub rate limits (ETag / If-None-Match on the releases/latest call).
- On the SECOND launch of a fresh install, show a one-time small prompt: "Keep True up to date automatically?" Yes (default) / No ->
  writes the setting; never asks again. Settings has the toggle + "Check now" + last-checked time.

## Done =
`swift build` clean, full `swift test --no-parallel` green except the known flaky Nova race test (note it), new tests for sig verify +
check scheduling + first-run prompt logic. A local end-to-end: build a fake v9.9.9 zip, sign with a throwaway key, point a debug
build at a local file/mock and show it refuses a tampered zip and accepts the signed one. Write RESULT with: files changed, test
output tail, exact steps Yahia runs once (gen-update-key.sh, gh variable set) and per release (Run workflow, sign-release.sh).
