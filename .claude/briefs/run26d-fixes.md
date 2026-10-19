# Run 26d — Nova security re-review fixes (same branch, before merge)

The `true-security` re-review of `0b3c9bc` says BLOCK. It confirmed most findings closed (H2 escapes, H3 path tricks,
C2, H1, M1–M4, L-items). Fix what is left below. **Write each test FIRST, run it against the current code, and paste
the failing output. Then fix it and paste the passing output.** The last round didn't prove "fails before", so this
time it is required for P1 and P2a at least. Instant-lane latency must not change.

## Must fix
- **P1 · self-approval via transcript residue** (`NovaEngine.swift:102-106`, `NovaLiveTurn.swift:24-31`). While the
  mic is gated (Nova speaking + 400 ms tail), `partial()` returns early but never consumes those words, so after the tail
  `command(in:)` finds a "nova" that Nova itself said. Exploit, reproduced: "…On it, Nova. Go ahead?" turns into an
  approval. Fix: in the gated branch, consume the gated words (e.g. `live.endTurn(wordCount: lastTokenCount)`). Also,
  defence in depth: an addressed approval counts only if its "nova" token arrived AFTER the gate opened. Use segment
  timestamps if available, otherwise word counts.
- **P2a · NUL / control characters crash True** (`NovaShell.swift:78,103`, `NovaHands.swift:217-220`). `cat x\0…` plans
  `.run`, then `Process.run` raises an NSException that `try?` can't catch, and the app aborts. Fix: add U+0000–U+001F
  and U+007F to `forbidden`, and validate every string that reaches `Process`/`FileManager` in all hands.
- **P2b · the approval card hides the cwd.** The park text must show the exact command AND the absolute cwd it will run
  in (`NovaShell.swift:101`, `NovaHands.swift:209-211`).
- **P2c · free `git` in a hostile repo runs code** (`core.fsmonitor`, clean/smudge filters, textconv,
  `log.showSignature` + `gpg.program`). Fix: `git` is free ONLY when the resolved cwd is inside a known True project
  folder (the roster's working directories, or the folders True already tracks). Anywhere else it parks. In known
  folders, also pass `-c core.fsmonitor= -c log.showSignature=false -c diff.external= -c core.pager=cat` and run
  with `--no-textconv` where the subcommand accepts it.

## Also fix (P3)
- **Spoken yes is bound to a card.** The approval resolves only the card id that was showing when the utterance
  STARTED. If a new card replaces it mid-sentence, the yes doesn't carry over.
- **Approval is decided on the final utterance, not a partial.** "Nova, go ahead… no, wait" means no. Approvals aren't
  on the instant lane, so this costs nothing that matters.
- **Git content reads skip the path guard.** Free `git` refuses `-p`/`--patch`, `<rev>:<path>` and textual diffs; only
  `status`, `log` (no patch), `branch`, `diff --stat`/`--name-only` and `show --stat` stay free. Run every pathspec
  through `NovaPaths`. Anything else parks.
- **Recursive grep/rg skips name-based secret checks.** Recursive search is free only with the secret globs excluded
  (`--exclude`/`-g '!…'` from the `NovaPaths` set). Otherwise it parks.
- **Hard links:** `read_file` and free shell reads of a file with `st_nlink > 1` park.
- **Hidden files instead of a secret list:** anything under the home folder whose path has a component starting with
  "." parks for approval (in `read_file`, `find_files` results, and shell path args), except True project `.claude`
  docs. The explicit secret set (`~/.ssh`, keychains, `.env*`, `~/.true` secrets) stays hard-refused.
- **The de-dup message is misleading.** A repeated action that was refused or denied reports its real outcome, never
  "already done" (`NovaHands.swift:65`).

Update `docs/kb/security.md` to match. Gate: the three commands from docs/kb/conventions.md, with the tails pasted.
Commit on this branch only; never main; never launch True.app; never weaken an existing test. Report: each ID with its
fix, its test name, and the fail-before/pass-after evidence; the gate tails; and what is unverified live.
