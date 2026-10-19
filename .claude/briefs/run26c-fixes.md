# Run 26c — Nova security fixes (same branch, before merge)

`true-security` blocked the merge. Fix EVERY finding in `.claude/briefs/run26c-security-findings.md` (C1, C2, H1–H3,
M1–M4, all Lows except "mic on from launch by default", which stays). Each finding gets its regression test from that
file, which must fail on the old code and pass on the new one. Keep the instant lane instant: none of these fixes may add
latency to the instant lane's local verbs.

## Yahia's policy decisions (2026-10-10). These fill in the "POLICY" gaps in the findings file.
- **C1, approval:** a parked action is approved ONLY by an *addressed* yes: "Nova, go ahead" / "Nova, approve" (the wake
  name in the same utterance), a yes said while the push-to-talk hotkey is held, or a click on Approve in the HUD. A bare
  "go ahead" in the room NEVER counts, so ambient speech can't approve. Also: ignore all mic input while Nova is speaking,
  plus a ~400 ms tail after it stops (only "stop" can barge in, and only at the interrupt threshold). Turn on echo
  cancellation (`AVAudioEngine` input node `setVoiceProcessingEnabled(true)`, or the equivalent the recognizer path
  allows; document it if it isn't possible). Matching is whole-phrase on an addressed utterance, and a negation ("don't",
  "do not", "no", "cancel", "stop") anywhere in it means NO. No beats yes (fixes H1).
- **C2, agent sends:** EVERY Haiku-initiated `send_to_pane`, `relay`, `spawn_agent` and `open_url` parks for approval,
  whatever the turn has read. The card shows the exact target and the full text or URL. The instant lane's fixed
  known-site table stays instant, because those are the user's own words matched locally.
- **M2:** each approval is bound to ONE parked action id. The card shows the exact command, text or URL, never a summary
  like "shell command". A stale or second yes never approves a different action.

## Non-negotiables from the findings
- **H2:** `run_shell` never goes through a shell. The allowlisted binaries run via `Process` with an argv array (absolute
  path from a fixed table, no PATH lookup). Use a strict tokenizer: any shell metacharacter, `=(`, glob qualifier, `$`,
  backtick, redirect, `;`, `&`, `|`, or a newline means not read-only, so park. Per-command flag denylist (`find
  -exec/-execdir/-delete/-ok/-fprint*`, `git -c/--output/--exec-path/-C` plus any subcommand outside status/log/diff/
  branch/show, `rg --pre`, and so on). Anything that is not provably read-only parks. DenyList is still checked first.
- **H3:** one shared path guard for `read_file`, `find_files` results AND every path argument the shell allowlist
  passes: `realpath` (resolve symlinks), compare case-insensitively against the refused set, refuse on any doubt.
- **M1:** eager end-of-turn may START reflex+brain, but no hand that changes anything runs until the end of the turn is
  final and the transcript still matches what the brain was given. Read-only tools may run early. On a mismatch, discard.
  No repeated action.
- **M4:** Nova can't quit, hide-then-quit or terminate True itself (its own bundle id).

Update `docs/kb/security.md` so it claims only what the code now enforces (the reviewer flagged the current text as
overclaiming). Gate: the three commands from docs/kb/conventions.md, with the tails pasted. Commit on this branch only;
never main; never launch True.app; never weaken an existing test. Report: each finding ID with its fix and test name,
gate tails, and what is still unverified live.
