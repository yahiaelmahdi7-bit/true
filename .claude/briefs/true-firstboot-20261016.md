# True v1.1.3 — boot into Claude on any Mac (Yahia's call: fully automatic)

Repo: /Users/y/Projects/true. Do NOT push, tag, merge to main or open True.app. Commit on your branch only.
Existing: `PaneStartup.claudeCommand` (`command -v claude >/dev/null && claude --dangerously-skip-permissions --settings …;
exec $SHELL -l`), autostart on fresh boot + ⌘T gated by setting whose default comes from Info.plist
`TrueClaudeAutostartDefault` (public `scripts/public/scripts/package.sh` writes `<false/>`).

1. Public default ON: change the public package.sh key to `<true/>` (Yahia decided; his friend should boot into Claude).
2. First boot installs Claude Code when missing:
   - Resolve claude like a login shell would (`zsh -lic 'command -v claude'`, then ~/.local/bin/claude,
     /opt/homebrew/bin/claude, /usr/local/bin/claude); once per launch, off the main thread.
   - Missing → the FIRST pane that would start Claude runs visibly: a 2-line note ("True is installing Claude Code with
     Anthropic's official installer. Ctrl-C to skip."), a 5 s countdown, `curl -fsSL https://claude.ai/install.sh | bash`,
     `export PATH="$HOME/.local/bin:$PATH"`, then the normal Claude startup (Claude's own first run does browser sign-in).
     On failure: print the error + the manual command, then `exec $SHELL -l`.
   - Once per Mac (UserDefaults flag); a failed run retries on the next launch. Only one pane runs it per launch; other
     new panes that launch get a plain shell until it finishes.
   - No Swift-side download: the installer runs only in the user's visible shell.
3. Tests: exact generated setup command (shell-quoted), once-only + retry-after-failure, single-pane guard, installed
   claude skips setup, public plist default true.
Gates (show output): `swift build`, full `swift test` (known: `raceBrainStartsAtT0WhileReflexIsSlow` fails only under
full-suite load, also on main), `scripts/export-public.sh <tmp>` + `swift build --build-tests` there.
