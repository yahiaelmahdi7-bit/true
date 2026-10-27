# Telegram for macOS 12.8 - design reference notes (for True chat redesign)

Method: static pass on /Applications/Telegram.app only (assetutil on Assets.car, `strings` on the Mach-O,
Localizable.strings, Resources listing). Nothing launched, no user data read, no code copied. Labels:
**confirmed** = seen in bundle; **likely** = inferred from names; **guess**. Hard numbers are scarce: bubbles,
colors and spacing are drawn in code, not in the asset catalog (the catalog has zero chat colors; its only 8
Color entries belong to the app icon). Evidence column = what showed it.

## 1. Message bubbles
- Bubbles are stretchable images keyed by neighbor position: `chatBubble_{none|both|...}_{incoming|outgoing}_withInset`
  plus a matching `chatBubbleBorder_*` set (confirmed, string names). "none/both" = tail-less vs tail variants of a
  grouped run; so consecutive messages from one sender are joined with tight inner corners, tail only at the
  end of a run (likely; name pattern + `_cachedBubbleFrame`).
- Separate palette slots: `bubbleBackground_incoming/outgoing`, `bubbleBackgroundHighlight_*` (tap/jump flash),
  `bubbleBorder_*` (hairline stroke per direction), `bubbleBackgroundTop_outgoing` + `...Bottom_outgoing`
  (outgoing bubble is a vertical gradient; incoming is flat) (confirmed names).
- Accent slots per direction: `accentIconBubble_*`, `chatReplyTitleBubble_*` - quote/reply title color changes
  inside own vs other bubbles (confirmed).
- Timestamp + read state live inside the bubble, bottom-right; check glyphs `Icon_MessageCheckMark1` / `Icon_MessageCheckmark2`
  are 12pt (24px @2x), sending clock `Icon_MessageSending` 12pt, failed `Icon_MessageSentFailed` (confirmed, catalog).
  Channel views counter has three tints: in-bubble incoming/outgoing and over-media overlay (`chatChannelViewsOverlayBubble`).
- Layer: `ChatMessageBubbleBackdrop` suggests bubbles can sample one shared wallpaper-aligned backdrop (likely).
- Selection: `ChatBubbleSelectionFragment`, `BubblesCheckbox` - multi-select shows a round checkbox in the gutter.
- Corner radii / max width / dark hex values: not recoverable statically (see Couldn't determine).

## 2. Media
- Albums: a `GroupedLayout` engine with `GroupedLayoutAttempt` (confirmed type names) = tries several row layouts
  and keeps the best aspect fit; result is a tight collage inside one bubble with small gaps (likely). Composer side has `MediaGroupPreviewRow`.
- Round video notes: `ChatVideoMessageContentView`, `VideoMessageCorner`, custom shaders `VideoMessage.vsh/.fsh`,
  `Icon_VideoMessageShadow` is 254pt square (508px) = the circle plus its soft shadow, mute/unmute badge icons
  (confirmed). Circle clip is GPU-drawn, not a mask view.
- Voice notes: `ChatVoiceContentView`, `AudioWaveformView` (bar waveform from stored sample array), play/pause is a morph
  (`anim_play.json`, `Icon_InlinePlayerPlay/Pause`), speed chip `Icon_InlinePlayer_x2`.
  Transcription: `VoiceTranscriptionControl`, `TranscribeAudioTextView`, `Icon_ChannelFeature_VoiceToText`; text expands
  under the waveform in the same bubble (likely).
- Files: `ChatFileContentView`, `Icon_MessageFile`; round progress/download glyph `Icon_MediaDownload`.
- Link previews: `WebpagePreviewMessageAttribute` (preview is a message attribute, rendered as a bubble block with accent
  left bar - the left-bar part is likely from `TextViewBlockQuote` + `chatReplyTitleBubble` slots). Instant View: `InstantViewController`.
- Media viewer: `GalleryViewer`, `GalleryModernControls`, thumb strip `GalleryThumbsControl`, rotate/zoom/share/fast-save
  icons (`Icon_GalleryRotate/ZoomIn/ZoomOut/Share/Fast_Save`), PiP `Icon_VideoPlayer_PIPIN`, 15s rewind (confirmed).

## 3. Bots
- "/" command list: `BotCommand` / `BotCommands` scopes (per chat, per admin); menu button: `BotMenuButton` + animations
  `bot_menu_web_app.tgs`, `bot_menu_close.tgs` (menu icon morphs open/closed) (confirmed).
- Inline keyboard under a message: `ReplyMarkupNode/Row/Button/ButtonLayout` - rows of equal-flex buttons attached
  below the bubble as separate rounded tiles; link buttons carry `Icon_InlineBotUrl` (8pt corner glyph, 16px),
  web-app `Icon_InlineBotWeb`, copy `Icon_InlineBotCopy` (confirmed).
- Reply keyboard: `replyKeyboardMarkup/Hide/ForceReply` + `chatActiveReplyMarkup` state and `Icon_ReplyMarkupButton`
  (toggle in composer, 30pt) - keyboard replaces the emoji/attach panel area (likely).
- Bots have no special bubble style; difference is "bot" presence label (`Presence.bot`), the Start button
  (`Chat.Input.StartBot` = "Start") in place of the composer, and inline results (`BotInlineResult`).

## 4. Composer
- Types: `ChatInputView` > `ChatInputTextView` (growing), `ChatInputAttachButton`, `ChatInputSendButton`,
  `ChatInputRecordingView`, `ChatInputAccessory` (reply/edit/forward strip above the field), `ChatInputMenuView`.
- Attach popover items in order: Photo or Video, Camera, File, Location, Poll, Gift Premium, Checklist, Audio File
  (Localizable.strings). Icons: `Icon_AttachPhoto/Camera/File/Location/Poll` at 30pt.
- Quote/reply bar: `TextInputTextQuoteAttribute`, `Icon_Quote_Collapse/Expand`, `Icon_ChatAction_ReplyMessage`;
  reply on Mac is a context-menu item with hint "double click" (confirmed string) - double-click a bubble = reply.
- Mentions: `ChatTextInputTextMentionAttribute`, `ChatPresentationInputQuery(Result)` = a typed query ("@", "/", ":")
  produces a popup list above the composer (likely).
- Voice record: `ChatInputRecordingView`, `Icon_RecordVoice` / `Icon_RecordVideoMessage` (30pt) share the send slot;
  send glyph swaps by state (`Icon_SendMessage` 25pt, `_Large` 40pt, `_Small` 26pt), `begin_record.caf` sound (confirmed).

## 5. Chat chrome
- Chat list: `ChatListRowItem/RowView`, unread badge slots (`badgeColor`, `badgeMutedBackgroundColor`, `badgeSelected*`) -
  3 states: normal accent, muted gray, selected-row inverted (confirmed names). Pinned `Icon_ChatListPinned` and mention
  `Icon_ChatListMention` both 20pt; swipe actions have their own icons (pin/mute/read/archive/delete).
- Left sidebar = folder rail (`LeftSidebarView`, `Icon_Sidebar_*`, ~35 folder glyphs).
- Pinned bar: `ChatPinnedView` (11pt pin glyph `Icon_ChatPinnedMessage`), paged by "Previous message" / "Pinned message #n" strings;
  `Icon_ChatPinnedList` opens the full list. Other header strips share `ChatHeaderController`: translate, ad, search headers.
- Date pills: `ChatDateStickView` (sticky floating date); service lines: `ChatServiceRowView`; `ChatUnreadRowView` ("new messages" divider);
  `Icon_ChatListScrollUnread` (10x5.5pt) is the scroll-to-unread chevron.
- Wallpaper: `ChatWallpaperRowView`, cached blurred and pattern-mask variants (`CachedBlurredWallpaperRepresentation`,
  `CachedPatternWallpaperMaskRepresentation`), bundled `builtin-wallpaper-svg` + `darkerTexture.jpg`/`lighterTexture.jpg`/`flecks.jpg`.
- Glass: 12.8 has Liquid Glass types - `LiquidGlassView`, `NSGlassEffectContainerView`, `GlassContainerView`,
  `GlassTouchEffect`, `AdaptiveGlassEffectView`, plus `LegacyGlassEffectContainerView` fallback (confirmed); also `VariableBlurView`,
  `MaskedVariableBlurView`, `EdgeEffectView` = progressive blur at scroll edges (title bar and composer float over content) (likely).

## 6. Dark palette
- Not in the catalog. Themes are code: `ColorPalette` module with `dayClassic` and `nightAccent` (dark) plus a user accent
  (`AccentColorRow`, per-peer name colors `PeerNameColors`, `InputViewTheme`). 242 incoming/outgoing-paired slots.
- Only literal colors found: app-icon blues (sRGB 0.114/0.576/0.824 = #1D93D2; system blue 0/0.478/1). Dark hex values: undetermined.

## Borrow for True
1. Bubble runs: tail only on the last message of a same-sender run; tight inner corners inside the run.
2. Outgoing bubble = subtle vertical gradient of the accent; incoming = flat neutral. Hairline border per direction.
3. Time + read ticks live inside the bubble bottom-right (12pt glyphs: clock, one tick, two ticks, failed).
4. Reply/quote title tints per bubble direction (own vs other), not one global accent.
5. Inline keyboard = separate equal-width tiles stacked under the bubble, glyph corner for link/web/copy.
6. One send slot that morphs: mic / video / send, with record sound and a recording view replacing the field.
7. Attach popover: short list, fixed order (media, camera, file, location, poll), 30pt glyphs.
8. Pinned bar paged with "pinned #n", list button opens all; single-line, accent bar at left.
9. Sticky date pill + "new messages" divider + scroll-to-unread chevron.
10. Voice note = bar waveform + play morph + speed chip + inline transcript expanding below.
11. Float title bar and composer over content with variable (progressive) blur / glass on macOS 26.
12. Album collage via a layout solver that tries several row splits and keeps the best aspect fit.

## Couldn't determine
- Bubble corner radii, tail geometry, max width (percent or points), inter-bubble spacing, grouping time threshold.
- All dark/light hex values, bubble gradient stops, wallpaper tint math (needs disassembly of the palette initializers or a
  runtime dump; the catalog has none).
- Animation durations/springs (compiled constants), waveform bar count/width, album gap size, composer min/max height.
- How the "/" menu popup is positioned and whether the menu button is inside the field or beside it.
