# True — inline autocomplete + Claude on fresh boot / new tab

Repo: /Users/y/Projects/true (Swift, macOS 14+). Another builder is working in parallel on auto-update + peer jobs (it bumps
the version to 1.1.2 and edits `Peers/`, `Model/Update*`, package scripts) — do NOT bump the version or touch those areas.
Do NOT push, tag, merge to main or open True.app. Commit on your branch only.

## 1. Inline autocomplete (fish/Warp-style ghost text)
True already injects zsh integration via a ZDOTDIR shim (`Terminal/ShellIntegration.swift`: True's `.zshenv` restores the
user's ZDOTDIR, sources their files, and runs a one-shot `precmd` hook `_true_history`). Extend that pattern:
- Vendor zsh-autosuggestions v0.7.1 (MIT; github.com/zsh-users/zsh-autosuggestions, single file `zsh-autosuggestions.zsh`)
  as a Swift string resource or bundled file written next to the shim (same "written by True; overwritten when it changes"
  rule). Keep its LICENSE text alongside and add an attribution line to README + `scripts/public/README.md`.
- Load it from the one-shot first-prompt hook (after all user rc files), ONLY if the user hasn't already loaded it
  (`(( $+functions[_zsh_autosuggest_start] ))` → skip). Strategy `(history completion)`, highlight a dim grey that reads on
  True's theme (`Theme`), → / End accepts, ⌥→ accepts one word. Also enable menu-select tab completion
  (`zstyle ':completion:*' menu select`, case-insensitive matcher) only if the user has no completion zstyles and
  compinit is loaded (don't run compinit twice; if not loaded, `autoload -Uz compinit && compinit -C`).
- Setting "Inline suggestions" (default ON). OFF → the shim doesn't load it (env var read by the shim). Takes effect in new panes.
- Non-zsh shells untouched. Tests: the generated shim text contains the guarded load + respects the off switch.

## 2. Claude on a fresh boot and new tab
Cmd+O already boots Claude on Enter (`Projects/ProjectPalette.swift` `open(_:withClaude:)` → `PaneStartup.claudeCommand`,
which is `claude --dangerously-skip-permissions --settings …; exec $SHELL -l`). Add the same startup for:
- a fresh launch where nothing was restored (first pane of an empty workspace), and
- a new tab (`WorkspaceModel.newTab`, ⌘T). Splits stay a plain shell. Restored panes keep their existing resume logic.
- Use `PaneStartup.shared.set(..., for:)` like openProjectBeside. Guard the command: if `claude` isn't on PATH, just the
  shell (e.g. `command -v claude >/dev/null && claude …; exec …`) — apply the same guard to `claudeCommand` itself.
- Setting "Start Claude in new tabs (skip permissions)": default ON when Info.plist lacks `TrueClaudeAutostartDefault`
  or it is true; the PUBLIC `scripts/public/scripts/package.sh` writes `TrueClaudeAutostartDefault=false` (strangers must
  not get skip-permissions by default). Private `scripts/package.sh` unchanged.
- Tests: newTab registers the startup when ON and not when OFF; fresh-boot only when nothing restored; default resolution.

## Gates (show output)
`swift build`, full `swift test` (known flaky: `tellLatencyWithin10PercentOf26e`, `overlappingChecksAreSkipped` — report,
don't chase), `scripts/export-public.sh <tmpdir>` then `swift build --build-tests` there. Smoke the shim: run
`zsh -i` with True's ZDOTDIR shim in a temp HOME and confirm `_zsh_autosuggest_start` is defined after the first prompt
(and not when the off switch is set). Result: what changed, gate output, what only a real pane can prove.
