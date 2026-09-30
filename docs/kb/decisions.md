# Decisions (ADR log)
Owner: cto · Last verified: 2026-09-30

## 2026-09-29 — Build True as a lean successor to Axon
- Context: Axon was 68k lines, 20+ subsystems, fans spinning; it did not replace Warp. [source: SPEC.md:5-8]
- Decision: New repo keeping only proven terminal + agent plumbing; Axon frozen at tag `axon-parked-2026-09-29`.
- Alternatives: keep trimming Axon (rejected implicitly). [assumption]
- Status: Accepted.

## 2026-09-29 — Copy from Axon, never import it; separate identity
- Context: avoid state collisions while both exist.
- Decision: bundle id `net.prismlens.true`, state `~/.true/`, own socket, per-agent `--settings` only. [source: SPEC.md Hard rules]
- Alternatives: share `~/.axon`. Rejected.
- Status: Accepted.

## 2026-09-29 — Idle ≈ 0% CPU, event-driven only
- Context: fan noise killed Axon. Decision: no timers/polling at launch; screenshots via kqueue folder watch, saves debounced by event. [source: SPEC.md; git log "kqueue folder watch"]
- Status: Accepted (KeepAwake, tickers only while Hub visible follow the same rule).

## 2026-09-29 — SwiftPM, no Xcode; tests need CLT framework flags
- Decision: `swift build`/`swift test` with explicit `-F` flags. [source: SPEC.md:29-38]
- Status: Accepted.

## 2026-09-30 — Tabs in the title bar; history saves per command
- Decision: hidden-title-bar window with tabs in it. [source: git log "Tabs live in the title bar"]. Status: Accepted.

## 2026-09-30 — Sign with a stable self-signed certificate, not ad-hoc
- Context: ad-hoc signing changed identity each rebuild so macOS privacy popups returned. Decision: sign with "Deck Signing" identity; fall back to ad-hoc with a warning if absent. [source: scripts/package.sh:49-65; commit "Sign True with a stable certificate"]
- Status: Accepted.

## 2026-09-30 — Agents are global; control via `truectl` socket
- Decision: agents can summon each other through a control socket; `truectl` written at launch. [source: git log "Global agents + truectl"]. Status: Accepted.

## 2026-09-30 — Restore exactly where he left off (Run 4)
- Decision: per-pane resume records in workspace.json (optional field, no version bump); plain shells replay coloured scrollback; awake agents re-wake with `--resume`. [source: SPEC.md Run 4]. Status: Accepted.

## 2026-09-30 — Jev decides, code owns the flow (Run 6)
- Decision: Jev for cleaner fact-check, ordering, AI-fill picks; any failure falls through to old behaviour; key from env then Keychain. [source: SPEC.md Run 6]. Status: Accepted.

## 2026-09-30 — Hub replaces Agents panel; deterministic, no Jev (Run 7)
- Decision: one panel for seats, background builders and other sessions; background work via `truectl spawn` → `builder start --parent`. Additive `builder --parent` edit with backup. [source: SPEC.md Run 7]. Status: Accepted.

## 2026-09-30 — True is THE cockpit; Axon forgotten
- Context: Yahia: "forget axon we work on true only now". [source: ~/.claude/projects/-Users-y/memory/project_true.md]. Status: Accepted.

## 2026-09-30 — Screen stays awake while True is open
- Superseded earlier rules ("no idle sleep while frontmost" → "only while an agent works" → "for as long as True is open", commit 8c09715). [source: git log]. Status: Latest wins.
