# Clip Studio — Accounts & Mail UX rebuild (spec v1, 2026-10-13)

**Goal (one sentence):** creating a platform account is a guided ~3-minute job that never needs a second app except the
platform's own signup page, and every verification email is one glance + one click.

Branch: continue `builder/clip-studio-accounts-inbox-20261013-151423` (v1 already there: Accounts tab ⌘4, inbox sync,
Keychain creds, 4 stills in docs/proof/accounts/). Rebuild the UI on top of that engine; keep what works.

**Reference idioms (mirror, never import):** Apple **Mail** for the inbox (sidebar → list → reader), Apple **Passwords**
for an account's sign-in details (title, labeled rows, click-to-copy, verification-code ring), System Settings-style
sheets for the create flow. Rules from `docs/DESIGN.md` hold: native controls, SF Symbols, semantic colors, light AND dark,
no web views; name the HIG Sample Book component IDs you used per screen and add the rows to DESIGN.md.

## Jobs to be done (in priority order)
1. Create an account for a campaign on TikTok / Instagram / YouTube.
2. Grab a code the second it lands.
3. Log into an account later: email, password, 2FA, one click each.
4. See which accounts are ready to post, and fix the one that isn't.
5. Triage mail: what needs action vs. noise.

## What v1 gets wrong (from the stills): fix every one
- The sidebar does three jobs (mail filter, accounts, spare-address pool); 15 spare addresses push accounts off-screen.
  Spare addresses are plumbing, not navigation.
- Accounts with no handle show "planned" as their name, then the PLANNED badge again.
- "New account" is a bare button with no flow: the user has to copy a spare address, invent a password, sign up and come back.
- Mail: no unread/read triage, no grouping by day, codes mixed with noise (deals@shop-example.com), no "expired" signal
  on old codes, loose floating column with no row structure, "Open link" is weak bare text.
- Detail: "Set…" truncated; Generate/Set crowd the password row; no posting state; no next step.
- Accounts belong to campaigns in the data model, but the UI hides that.

## Information architecture — Accounts tab (⌘4), NavigationSplitView
**Sidebar** (`list.style-sidebar`):
- Section **Mail**: "Inbox" (`badge.numeric` = unseen), "Codes" (badge = codes < 15 min old).
- One section per campaign (campaign name as header). One row per platform account: platform glyph, handle, or
  "TikTok · not set up" in secondary text, trailing status (see stepper), unseen-mail badge.
- A campaign platform with no account row yet → ghost row "Add Instagram" that opens the Create sheet preselected.
- Footer: sync state ("Synced 17 s ago" / the error + its fix) and a refresh button.
- **No spare addresses in the sidebar.** They move to Settings → Accounts & Keys → "Mail addresses" (`list.table`:
  address · platform · assigned to · "Add 5"). The create flow assigns one automatically.
- "New Account" is a toolbar button (`button.prominent`) for this tab, ⌘N while the tab is focused.

## Screen 1 — Account detail (Passwords idiom)
Header: large platform glyph, handle as title, "Campaign · Platform" secondary. Content max ~640 pt wide, leading-aligned
in its column (not floating in the center of an empty pane).

**Status stepper:** Planned → Created → Connected → Posting, current step marked, and ONE primary button for the next step:
- planned → "Continue setup" (opens the Create sheet at the right step)
- created → "Connect for posting" (the provider set for that platform: Upload-Post, or direct `clipengine auth <platform>`)
- connected → "Start posting" (advance to posting after a one-line confirm saying what it means; NEVER touches `post.golive`)
- posting → no button; show "Last post 2 h ago · 9 this week" from the tracker
- Auth expired / YouTube 7-day refresh lapse / Upload-Post unlinked → inline banner with the fix button ("Reconnect").

**Sign-in card** (one `form.grouped`, `labeled-content.default` rows, no nested boxes):
- Email · Username · Password (masked; reveal + copy; a "Change" menu: Generate new / Type new… — no truncated "Set…") ·
  2FA (6-digit code with a countdown ring, click copies; if no TOTP secret: "Add 2FA code…" to paste a secret/otpauth URI).
- Click a row = copy. Inline "Copied" replaces the icon for 1.5 s. If the pasteboard still holds the password after 90 s, clear it.

**Latest code (hero):** only when a code for this address arrived < 15 min ago. Large monospaced digits (system font
`.monospacedDigit()`, ~44 pt semibold, not a decorative face), "arrived 40 s ago", Copy button. Older → it drops into
the mail list, dimmed, labeled "probably expired".

**Mail** for this address (same row component as the Inbox). **Setup kit** disclosure (reuse `AccountKitView` content:
handle ideas, bio, profile picture, checklist), collapsed once status ≥ created. **Posting** card: provider, connection
badge (`badge.text` Connected / Expired / Not connected), last post.

## Screen 2 — Inbox (Mail idiom)
Message list + reader. Toolbar: segmented filter **All · Unseen · Codes** and a search field.
- Sections: Today / Yesterday / Earlier.
- Row: unseen dot · platform glyph · account handle (resolved from `to_addr` via `mailboxes`; fall back to the address) ·
  subject · time · trailing chip: the code (click copies) or "Open link".
- Reader: subject, from, to (account name is a link that jumps to the account), time; code hero if any; "Open in browser"
  (`button.bordered`) showing the link's domain; plain-text `body_text` (no web view).
- Opening marks seen; "Mark as Unseen" (⌘⇧U). Keyboard: ↑/↓ move, C copy code, O open link.
- Non-platform mail stays in All but never in Codes. Nothing is ever auto-deleted.

## Flow — Create account (sheet, `form.grouped`, step indicator at top)
Triggers: toolbar New Account, a ghost row, or "Continue setup".
1. **Where:** campaign picker (defaults to the selected campaign), platform segmented control (a platform the campaign
   already has is disabled with the reason). Continue → creates the planned row (`accounts` create is idempotent).
2. **Sign up:** everything the signup form needs, each click-to-copy, in that platform's field order:
   email (next spare address for the platform via `assign_next`; if the pool is empty, add 5 silently: it's a catch-all),
   password (generated now and saved to the Keychain immediately, so it's never lost), handle (first kit suggestion,
   editable). Primary: "Open TikTok sign-up" opens the platform's signup URL in the default browser and the sheet moves to 3.
3. **Verify:** live waiting state, "Waiting for TikTok's code at tt-03@in.prismlens.net — usually under a minute", elapsed
   time. Sync polls every 5 s while this step is on screen (back off on 429, stop when the sheet closes). When the code
   lands: show it big, copy it to the pasteboard automatically, play the system "Glass" sound once, and post a user
   notification with the code if the app isn't frontmost. Link-type confirmations (Instagram "Confirm your email") show
   "Open confirmation link" instead. After 3 min with nothing: show the address again (typo check), "Sync now", and a hint
   to ask the platform to resend.
4. **Done:** "Which handle did you get?" prefilled with the suggestion → Finish advances to created with that handle,
   then offers "Connect for posting" (primary) or "Later".
Cancel: confirm only if a password was generated; the credentials stay in the Keychain on the planned account and the
address stays assigned to it (nothing lost; "Continue setup" resumes at step 2).

## States & edges (FINISH-STANDARD: every one needs a still or a test)
- No Resend key → one inline banner in the Mail section: "Mail is off. Add the Resend inbound key" → Settings.
- Sync errors (`unauthorized` / `rate_limited` / `network` from `SyncError.state`) → banner with the fix; never a silent spinner.
- Empty inbox, empty campaign, account with no mail: `empty-states.type-large-symbol` with the one next action.
- Long handles/addresses truncate in the middle, full value in the hover tooltip.
- Light and dark mode both.

## Engine changes this needs
- Inbox CLI: list with `account_id` resolved (join `mailboxes`), filter by account/unseen/codes, and mark seen/unseen.
- `mailboxes`: assign on step 2 (already) and a way to release an address from an abandoned planned account.
- "connected" must mean the provider set for that platform is authorized: Upload-Post linked OR direct auth valid
  (`auth <platform> --status`). If the direct-posting code isn't on this branch, show Upload-Post state only and leave a TODO.

## Visual rules (taste hard-rejects apply literally)
- Accent = the app's existing green, only for the primary action, unseen dots and "Connected". Status colors are semantic.
- No box-in-box, no stray divider lines (list separators only), no centered-everything layouts, no emoji, one type system
  (system font; monospaced digits only for codes/addresses/passwords).
- Every user-visible string: plain, short, no exclamation marks; run it through /humanizer.

## Proof required (look at every still yourself and self-critique against /taste before finishing)
`docs/proof/accounts-v2/`, light + dark: Inbox (codes + unseen + noise), Inbox reader, account detail at planned /
created / connected-with-expired-banner / posting, Create sheet steps 1-4 (step 3 waiting AND code-arrived), no-key,
sync-error, empty. Tests: engine pytest for the new CLI; Swift tests for the create-flow state machine (assign →
password saved → code arrives → advance), seen toggling, code-age dimming. Gates: full engine pytest + `swift test` green.
No real signups, no network to platforms or Resend in tests. No push, no merge, never flip `post.golive`.
