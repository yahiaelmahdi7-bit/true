# True — Run 6: Jev in the backend (decisions only)

Read SPEC.md, `.builder/run5-context-cleaner.md` and the current code first. This run adds Jev (TypeSafe's
System One model: typed judgments with probabilities in ~0.5 s, never prose) to three places where a step
is a DECISION. Code keeps the workflow; Jev only supplies judgments. Jev being slow, down, or keyless must
never break anything: every Jev path falls through to today's behaviour.

Evidence behind every threshold below: a 24-file probe on 2026-09-30 (real cleaner runs vs Jev answers;
12 files in-sample + 12 unseen). Do not change question wording or thresholds.

## 1. `JevClient` (Sources/True/Agents/JevClient.swift)
Port `~/Projects/axon/Sources/Axon/Nova/JevClient.swift` (READ ONLY — never edit Axon). Changes:
- Endpoint `POST https://api.typesafe.ai/v1/systemone`, `Authorization: Bearer <key>`, JSON body
  `{"model":"jev-latest","state":<json>,"questions":{<id>:{...}}}`. Reply: `answers.<id>` with `type`,
  and `noul` (P(yes)) or `choice`+`confidence`+`probabilities` or `score`+`confidence`+`probabilities`.
- Key: env `TYPESAFE_API_KEY` first; else run `/usr/bin/security find-generic-password -s
  net.prismlens.jev-cli -a typesafe -w` ONCE per process (stdout trimmed). Cache the result, including
  "missing". Never log it, never put it in an error message, never write it anywhere. (That Keychain item
  is created by /usr/bin/security, so spawning that binary reads it with no access dialog. Do NOT add a
  second Keychain item.)
- `ask(state:questions:timeout:) async -> Reply?`: nil on no key / network error / timeout / non-2xx /
  undecodable. Injectable transport + key provider for tests.

## 2. Context Cleaner — Jev fact check (additive only)
After sanitize, for each row with output (not Lean, not Error):
- **Blocks:** split the ORIGINAL into blocks: a new block starts at a blank line or a line whose trimmed
  text starts with `#`, `- `, `* `, `+ `, `<digits>. `, `>` or `|`; continuation lines are joined with
  one space. `norm(s)` = lowercase → delete the characters `* _ \` # > |` → drop a leading list marker →
  collapse whitespace → trim.
- **Vanished:** a block is vanished when `norm(block).count >= 15`, `norm(block)` is not a substring of
  `norm(whole output)`, AND its best word-Dice similarity against every output block is `< 0.6`
  (Dice = 2·|common words, multiset| / (|a|+|b|), words split on spaces after norm).
- Take the first 40 vanished blocks. Two Jev calls, in parallel, timeout 8 s each:
  - FILLER: state `{"dropped":[blocks]}`, one noul per block `f<i>`, instructions verbatim:
    ``Is `dropped[<i>]` only emphasis, generic good-practice advice, motivational framing or a section heading, with no project-specific fact, path, command, number, decision or status?``
  - KEPT: state `{"dropped":[blocks],"after":"<output>"}`, one noul per block `k<i>`, verbatim:
    ``Does `after` state the same information as `dropped[<i>]`, possibly in different words?``
- **Flag** a block when `max(filler, kept) < 0.5` → an orange "possible lost fact" chip showing the
  block's first ~80 chars (full text in the chip's tooltip). Any flag → the row is UNCHECKED for apply.
- Jev never removes or clears a regex chip, never re-checks a row. It can only ADD flags.
- No reply (no key, error, timeout) → a small grey note "fact check off" on that row, regex chips only.
  More than 40 vanished blocks → grey note "large rewrite — review by eye" and the row is unchecked.
- Probe result: 24 of 25 vanished blocks correctly cleared, and the 1 flag was a real (dated) loss; 2 of 2 planted rule
  deletions flagged. Known limit: a fact that survives only in scattered fragments can pass.

## 3. Context Cleaner — Jev ordering (NOT skipping)
Before the rewrite queue starts: one Jev score per unique content, max 8 in flight, timeout 5 s each,
state `{"file":"<content>"}`, question `pad`, type score:
- instructions: `{"question": "How much of `file` could be deleted without losing any fact, path, command, decision or status the reader needs?", "focus": "Judge filler (emphasis, generic advice, repetition), not whether the facts are still true."}`
- criteria (ordered, verbatim):
  0 `Already lean: nearly every line states a project-specific fact, path, command, decision or status; removing lines would lose information.`
  1 `Mostly lean: a few emphasis words, one repeated point, or a single generic reminder could go.`
  2 `Noticeable padding: several lines of loud emphasis (IMPORTANT, NEVER in capitals, bold warnings), generic good-practice advice, or rules stated twice.`
  3 `Heavily padded: whole sections are generic advice any engineer already follows, motivational framing, or the same rule repeated in several places.`
Stable-sort the queue by score descending (no score → 1.0), so the biggest wins land first. Nothing is
skipped and nothing is shown: on unseen files a 25%-cut file scored 0.48 next to 4%-cut files at 0.44,
so a skip threshold would lose real savings. Triage must never delay the queue by more than 5 s total.

## 4. AI fill — Jev picks instantly, Claude writes the charter
In `AgentBuilder.startFill`, run a Jev call AND the existing `AgentFill.run` in parallel. Record the
draft's pre-fill values first.
- Jev call (timeout 3 s): state `{"request":"<text>"}`. Questions (criteria verbatim):
  - `model` choice: haiku `search, inventories and read-only sweeps` · sonnet `routine implementation, tests, mechanical edits` · opus `architecture, coordination and hard debugging` · fable `the highest-stakes judgment calls`; instructions `Which model fits the weight of `request`?`
  - `effort` score, instructions `How much reasoning effort does `request` need?`, levels: `low: a lookup or listing` · `medium: routine code changes` · `high: tricky debugging or multi-part coordination` · `xhigh: architecture across many parts` · `max: a decision where a mistake is very expensive` → round(score) indexes AgentEffort.
  - `permission` choice: default `acts but asks before each change` · acceptEdits `edits files freely inside its task` · plan `read-only: investigates or plans, changes nothing` · auto `fully autonomous, runs unattended`; instructions `How much autonomy does `request` imply?`
  - `role` choice (ONLY when not editing an existing agent): lead `coordinates helpers inside one repo` · helper `does focused hands-on work` · global `works across many repos and hands work to repo leads`; instructions `What role does `request` describe?`
- Apply each Jev field whose `confidence >= 0.6` to the draft immediately (on the main actor).
  Probe: model 6/6, role 5/6, permission 4/5 correct; every miss had confidence < 0.6.
- When Claude returns: the charter always comes from Claude. Every other field is applied ONLY if it
  still equals its pre-fill value (so Jev's confident picks and anything the user touched win).
  Symbol stays Claude's. Claude failing keeps Jev's picks and shows the existing error.
- Out of scope: Needs-you classification stays the deterministic hook (proven on recorded sessions; a
  network call inside a hook adds latency and a failure mode).

## Tests (TrueTests; NEVER hit the network or the real Keychain — inject transport + key provider)
JevClient: request body shape, reply decoding (noul/choice/score fixtures), nil on 500/timeout/garbage,
key order (env beats provider; provider called once; missing cached). Fact check: blocks/norm/Dice
fixtures incl. a re-wrapped paragraph (kept), a reworded-but-present line (kept), a deleted rule
(vanished); flag rule truth table; >40 → note; no reply → note; never touches regex chips. Ordering:
stable sort, nil → 1.0, all-nil = scan order. Fill merge: floor 0.6, role skipped when editing, Claude
doesn't overwrite Jev/user-changed fields, charter always Claude's, Claude error keeps Jev fields.
Plus ONE `@Suite` of live tests that run only when env `JEV_LIVE=1` (key via the real provider): one
noul, one choice, one score round trip. Do not run them yourself; the reviewer does.

## DISCIPLINE (non-negotiable)
- Lane: ONLY ~/Projects/true on `main` (no other builder is running). Axon is read-only.
  Never read/write real ~/.true/* or ~/.claude/* in tests. Never run the cleaner on real files.
- Commits: atomic, message says what+why. NEVER push, merge, tag.
- Gates in the FOREGROUND only. Build `nice -n 10 swift build -j 2`; tests with SPEC.md's command,
  `-j 2`. Full suite at most ~4 times. 'done' = pasted passing output.
- True.app IS RUNNING and hosts live sessions. NEVER launch, open, quit, kill or signal it. Do NOT run
  `scripts/package.sh`. No GUI, no `open`, no `osascript`.
- If blocked: BLOCKED + one line. No extra scope.

Order: JevClient + tests → fact check + tests → ordering + tests → AI fill + tests → SPEC.md "Run 6"
notes → full test run. Commit after each step that builds.

Finish with a short plain-English report: what works, pasted final build + test output, commits, what
was never exercised live, risks.
