# Hub v4: Discord notes (REA, structure only)

Source: discord.com web client, 2026-10-28, a public server opened in preview mode (not joined). Measured from
computed styles; no message content read. Discord's code is closed: patterns only, House grammar wins.

## Measured
- Message run ("group"): the first message of a run carries avatar + name + time; later messages in the run are
  bare text rows with no header. Group start: 17px top margin, 44px min height, 2px vertical padding.
- Avatar 40px circle in a 72px left gutter (avatar at x=16); text column starts at 72px for every row, so
  continuation rows line up under the first.
- Body text 16/22; name 16 weight 500; time 12 weight 500 in a muted ink (about 65% lightness on near-black).
- Day divider: 1px rule, 24px above, 8px below, date label centred on it.
- Rows mix freely: text, image attachments and link embeds (a card with a left accent bar) sit in the same row.

## Known behaviour (not measured this pass)
- Runs break on author change, a reply, or a gap of about 7 minutes.
- Continuation rows show their time in the gutter on hover only.
- Mention chip: accent wash behind accent-tinted text, small radius, weight 500; clicking opens the profile.
  A message that mentions you gets a warm wash and a 2px bar on its left edge.
- Voice message: a pill with play/pause, bar waveform, time left, speed toggle; no transcript by default.
- "/" in the composer opens a command list grouped by bot, each with its arguments shown as chips.

## Borrow for True
1. Runs, not bubbles-per-message, for group chat density: header once per run, 7-minute break.
2. One text column with a fixed gutter so mixed rows (text, media, embeds) align.
3. Mention chips as accent wash + accent ink; a message that @mentions you gets the left bar.
4. "/" command list grouped by bot (Chief, Oracle), arguments as chips.

Where this meets the Telegram notes: Telegram wins for bubbles, voice notes (with transcript), media and inline
buttons; Discord wins for runs, the gutter, mentions and the command list. iMessage sets the feel: glass bars,
calm colour, one accent.
