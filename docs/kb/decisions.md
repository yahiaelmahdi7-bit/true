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

## 2026-09-30 — Screen stays awake while True is open (superseded by Run 9 below)
- Superseded earlier rules ("no idle sleep while frontmost" → "only while an agent works" → "for as long as True is open", commit 8c09715). [source: git log]. Status: Latest wins.

## 2026-09-30 — Colour lives only in agent avatars (Run 8)
- Decision: True is black & white; the single colour is the agent avatar's vivid gradient disc = identity (hue from name via FNV-1a unless chosen). Tier = brightness; status = monochrome. Supersedes the teal/blue/purple/gold tier colours. [source: SPEC.md Run 8]. Status: Accepted.

## 2026-09-30 — KeepAwake is work-gated (Run 9)
- Decision: hold the display-sleep assertion only while a live busy session, running builder, or fresh `.working` seat exists; release after 120 s continuous idle. Plain shell commands never count. Supersedes "for as long as True is open". [source: SPEC.md Run 9]. Status: Accepted.

## 2026-10-06 — Terminal output keeps its colours
- Decision: the black & white doctrine covers True's chrome, not what programs print. Terminals show program colours by default (Terminal.app 16-colour palette, no desaturation filter); Settings ▸ "Colour in terminals" off restores the monochrome look. Why: with Claude Code's orange spinner greyed out, Yahia could not tell working from done. Amends the Run 8 entry. [source: SPEC.md Run 8 amendment]. Status: Accepted.

## 2026-10-07 — Watcher fix builders keep full command access (Run 15)
- Decision: builders the Watcher launches run with full access (`builder` default `bypassPermissions`); no allow-list profile. The deny-list (`Sources/True/Duty/DenyList.swift`) is the guard: a planted risky command sends the item to handOff. Yahia chose this over an allow-list (`dontAsk` + build/test/git only, as Investigation uses). Known deny-list gaps from the final security check, accepted: git send-pack / http-push / svn dcommit; `GIT_CONFIG_COUNT/KEY/VALUE` env aliases; quoted `-c` values longer than the 120-char gap; very long `rm -f` chains before `-r ~`; exfil via scp / nc / rsync / ssh / python; `gh auth token`; `git credential fill`; `~/.netrc`; `login.keychain-db`; `curl > a.sh; sh a.sh`; `find ~ -delete`. Revisit if a builder ever runs one. [source: Run 15 security spot check, merge 2c07d48]. Status: Accepted.

## 2026-10-07 — A cap is a checkpoint, not a stop (Run 16)
- Decision: work must finish; token saving comes second. A builder or investigation that hits its spend cap with progress is resumed in the same session with a higher ceiling (ladder $1.50 → $3.50 → $8 → $20 → $40, then the max-total), one model step up if a pickup makes no progress. $60 is the absolute backstop per build (largest build so far cost $37); a build with under $0.50 of headroom left pauses (resumable) instead of failing. The Watcher continues capped investigations within its $2/day budget, then parks them with their session for later. Fix builders get `--max-total` = fixMaxUSD ($10). The first chunk is a constant "small" ($3.50): predicting size from the brief (Jev, held-out n=40) scored 38% exact vs 60% for always-small, so the budget grows by measured progress, not by prediction. Why: Yahia ranks a finished task above a cheaper unfinished one. [source: Run 16, merge c478664; jev-tools evals/sizing/REPORT.md]. Status: Accepted.

## 2026-10-08 — Screenshot panel: own copies, non-activating floating panel (Run 17)
- Decision: the screenshot tray is an always-on floating `NSPanel` (non-activating, `.floating`, all Spaces, top-right of the screen under the mouse), not a tab-bar popover. True keeps its own copies of the last 24 shots in `~/Library/Application Support/True/ScreenshotTray/` (`shots/`, `index.json`, `outbox.jsonl`) so the tray survives Desktop cleanup, app restart and reset; originals are never touched. Non-activating so clicking the panel never steals focus from the Claude Code session you are typing in; it becomes key only for the markup text tool. Markup saves as a new `kind:"markup"` entry (parent = original); the original copy is never modified. The file contract is verbatim in SPEC.md "Screenshot panel" because a Claude Code mod reads it. Known limit: a rebuilt (corrupt) index loses kind/parent, all become `original`. [source: SPEC.md Run 17; Model/TrayStore.swift]. Status: Accepted.

## 2026-10-08 — Downloads strip in the screenshot panel (Run 17b)
- Decision: the panel lists the newest 8 entries of `~/Downloads` (points at files in place, never copies into the tray); the filter mirrors the mod's `/dl` exactly. Send to session reuses `TerminalDrop.pastePath`, which may copy a protected-folder file into the drops folder so the child can read it — existing behaviour, not the strip's. [source: SPEC.md Run 17b; Model/DownloadsList.swift]. Status: Accepted.

## 2026-10-08 — Full-screen Shots overlay beside the floating panel (Run 18)
- Decision: Yahia asked for "a full screen tile like a real mac app"; the floating panel stays as the quick glance and gains an expand button. The overlay is a second *view* over the same stores (one watcher, one copy of the data), summoned by ⌃⌥⌘S (Carbon hotkey — no Accessibility prompt), the panel button, or Shell ▸ Show Shots. Non-activating panel so summoning from another app does not raise True's windows; Send explicitly brings True forward. Viewer navigation stops at the ends (no wrap). Arrival sound/bounce was explicitly not chosen and is not built. Known limit: arrow-key slides detach the image from its grid slot, so only open/close morph; the hotkey fails silently if another app already owns the combo (change `ShotsHotKey`). [source: SPEC.md Run 18; Views/ShotsOverlay.swift]. Status: Accepted.

## 2026-10-08 — Screenshot chip drags and snaps to corners (Run 19)
- Decision: the top-right-pinned chip covered the tab-bar "Restart to update" pill; Yahia chose Picture-in-Picture behaviour (drag, snap to nearest of 4 corners, remembered per corner in `screenshotTray.corner`) over moving it elsewhere. Drag is a single SwiftUI `DragGesture` on the collapsed chip (not a Button) so < 4 pt stays a click; expanded views keep tile drag-out and anchor to the chosen corner. [source: SPEC.md Run 19; Model/TrayPanelFrame.swift]. Status: Accepted.

## 2026-10-10 — Nova lives inside True (Run 26)
- Decision: voice control ships in True.app (overrides SPEC v1 "No Nova"). Brain = Jev reflex (fast, typed) + Claude Haiku 5.5 over raw SSE (no Swift SDK). Reach = apps/system, True agents/panes via the Command bar pipeline and `PaneDelivery`, shell and files. Autonomy = Nova's gate (park consequential actions for a spoken "go ahead"). Speculative race, honestly: the brain request is held up to 0.9 s for the reflex verdict so it can carry it as a prior; if the reflex wins, the brain task is cancelled. Screen hands and the computer toolset were deferred to the next run. [source: SPEC.md Run 26; Sources/True/Nova/]. Status: Accepted.
