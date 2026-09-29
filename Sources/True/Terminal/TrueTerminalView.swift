import AppKit
import SwiftTerm

/// True's terminal view: `LocalProcessTerminalView` plus the four hard-won fixes lifted from Axon's
/// `MonitoredTerminalView` — coalesced redraws, precise/alt-screen scrolling, PTY flood flow
/// control, and the hover auto-click filter. Everything Axon teed into (Blocks, PaneTail, the
/// activity monitor, canvas gestures) is deliberately gone.
final class TrueTerminalView: LocalProcessTerminalView {
    var paneID: UUID?

    /// The rendered screen as text (end of the active buffer, whatever the viewport is scrolled to).
    /// Cells a renderer skipped with a cursor move come back as NUL, not space, so NUL becomes the
    /// space a person sees. PaneDelivery and the needs-you detector read this, never the raw stream.
    func screenText() -> String {
        PermissionDialog.screenText(getTerminal())
    }
    /// Called when the user clicks into this pane, so the model's focus follows the mouse.
    var onFocusClick: (() -> Void)?
    /// Called shortly after Return is typed — the cheap moment a `cd` may have happened.
    var onCommandSubmitted: (() -> Void)?

    /// Leftover trackpad travel, in points, carried between scroll events (see `handleScroll`).
    private var scrollCarry: CGFloat = 0

    /// How many are installed in a window — lets the app-wide pointer monitor answer `mouseMoved`
    /// with one comparison when no terminal is on screen instead of hit-testing the view tree.
    private(set) static var liveCount = 0
    private var countedLive = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let live = window != nil
        guard live != countedLive else { return }
        countedLive = live
        Self.liveCount += live ? 1 : -1
        if live { MemoryGuard.shared.register(self) } else { MemoryGuard.shared.unregister(self) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyThemeColors()
    }

    /// Black in Light and Dark alike (see ``Theme``). Re-applied on an appearance flip anyway, in
    /// case SwiftTerm re-derives anything from it.
    func applyThemeColors() {
        nativeBackgroundColor = Theme.nsBackground
        nativeForegroundColor = Theme.nsText
        caretColor = Theme.nsText
        // The default background goes transparent (the pane's own black shows through), so the
        // view's shadow is cast by the glyphs alone: a zero-offset white shadow reads as a glow.
        backgroundOpacity = 0
        shadow = Theme.textGlow
        // Black and white only, whatever a program asks for: Claude Code paints its orange in
        // 24-bit colour, which no 16-colour palette can catch, so the pixels are desaturated.
        wantsLayer = true
        layerUsesCoreImageFilters = true
        contentFilters = Theme.monochrome
        installColors(Self.ansiGreys)
    }

    /// The 16 ANSI colours as a ladder of greys. Desaturating the stock palette left blue and red
    /// nearly black on black; these keep every colour readable and still tell them apart by brightness.
    private static let ansiGreys: [SwiftTerm.Color] = [
        0.00, 0.60, 0.68, 0.80, 0.56, 0.64, 0.74, 0.85,   // black red green yellow blue magenta cyan white
        0.45, 0.72, 0.82, 0.92, 0.70, 0.76, 0.86, 1.00,   // the bright eight
    ].map { let v = UInt16($0 * 65535); return SwiftTerm.Color(red: v, green: v, blue: v) }

    /// AppKit delivers a click to exactly the pane under it, so this pane — no hit test of ours —
    /// claims focus: first responder for the typing, and the model for dimming, ⌘D and ⌘W. Two
    /// owners that could disagree was the bug: typing went here while ⌘D split the old pane.
    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        onFocusClick?()
        super.mouseDown(with: event)
    }

    /// SwiftTerm's scroller draws a faint track down the right edge even when disabled. Hidden, it
    /// also stops reserving that width (`reservedScrollerWidth` reads `isHidden`); wheel and
    /// trackpad scrolling go through ``handleScroll`` and are unaffected.
    func hideScroller() {
        for case let s as NSScroller in subviews { s.isHidden = true }
    }

    /// Set only while ``TerminalRedrawCoalescer`` is releasing a batched paint, so the `super`
    /// call below is not re-captured by our own override.
    private var isFlushingCoalesced = false

    /// Every streaming repaint goes through one shared display-link heartbeat instead of hitting
    /// AppKit the instant a PTY chunk lands — see ``TerminalRedrawCoalescer`` for the measurements.
    /// `needsDisplay = true` (the boolean property) deliberately stays un-intercepted: those call
    /// sites are caret blink, focus and resize — rare, and the ones where a frame of delay is felt.
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        guard !isFlushingCoalesced, Thread.isMainThread, window != nil else {
            super.setNeedsDisplay(invalidRect)
            return
        }
        TerminalRedrawCoalescer.shared.invalidate(self, rect: invalidRect)
    }

    /// Called by the coalescer on its tick with the unioned dirty rect for this pane.
    func flushCoalescedDisplay(_ rect: NSRect) {
        isFlushingCoalesced = true
        super.setNeedsDisplay(rect)
        isFlushingCoalesced = false
    }

    // MARK: - Scroll

    /// Scroll that actually scrolls — the fix for "I can't scroll up in my Claude session".
    ///
    /// SwiftTerm's own handler misses on both of the ways a terminal is used:
    ///
    /// 1. **Trackpads.** It reads `event.deltaY` and returns early when that's 0. A precise
    ///    (trackpad / Magic Mouse) scroll reports in `scrollingDeltaY` and rounds `deltaY` to 0 for
    ///    anything short of a big flick, so ordinary two-finger scrolling was a no-op. We read the
    ///    precise delta and carry the remainder between events, so slow scrolling accumulates.
    ///
    /// 2. **Full-screen TUIs.** `claude` runs on the ALTERNATE screen buffer, which by definition
    ///    has no scrollback. What those apps expect is the wheel forwarded to them — as mouse-wheel
    ///    events when they've asked for mouse reporting, otherwise as arrow keys.
    ///
    /// On the normal buffer this stays SwiftTerm's behaviour: scroll the pane's own history.
    ///
    /// Reached through a local event monitor rather than an override: SwiftTerm re-declares
    /// `scrollWheel` as `public` (not `open`), so it cannot be overridden from another module.
    fileprivate func handleScroll(_ event: NSEvent) {
        let term = getTerminal()

        // Points → lines. Precise deltas are in points; legacy wheel deltas are already in lines.
        let step: CGFloat = 14
        let points = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * step
        scrollCarry += points
        let lines = Int((scrollCarry / step).rounded(.towardZero))
        guard lines != 0 else { return }
        scrollCarry -= CGFloat(lines) * step
        let magnitude = min(abs(lines), max(term.rows, 3))   // cap a flick at roughly one screen
        let up = lines > 0

        // An app that has captured the mouse gets the wheel FIRST, on either buffer — `claude` runs
        // its tracking on the normal screen and scrolls its own view from these reports; scrolling
        // our scrollback under it just got repainted over, which read as "scroll doesn't work".
        // Shift is the terminal-emulator convention for "bypass the app, I want the scrollback".
        if term.mouseMode != .off && !event.modifierFlags.contains(.shift) {
            // SGR/normal wheel buttons: 64 = up, 65 = down, reported at the cell under the pointer.
            let local = convert(event.locationInWindow, from: nil)
            let cols = max(1, term.cols), rows = max(1, term.rows)
            let cellW = bounds.width / CGFloat(cols), cellH = bounds.height / CGFloat(rows)
            let col = min(cols - 1, max(0, Int(local.x / max(cellW, 1))))
            // The view is not flipped, so AppKit's y grows upward while the terminal's grows down.
            let row = min(rows - 1, max(0, Int((bounds.height - local.y) / max(cellH, 1))))
            for _ in 0..<magnitude {
                term.sendEvent(buttonFlags: up ? 64 : 65, x: col, y: row)
            }
            return
        }

        guard term.isCurrentBufferAlternate else {
            up ? scrollUp(lines: magnitude) : scrollDown(lines: magnitude)
            return
        }

        // Alternate screen with no mouse capture: no scrollback exists — arrows are what the app's
        // own scroll bindings listen for.
        let key = up
            ? (term.applicationCursor ? EscapeSequences.moveUpApp : EscapeSequences.moveUpNormal)
            : (term.applicationCursor ? EscapeSequences.moveDownApp : EscapeSequences.moveDownNormal)
        for _ in 0..<magnitude { send(key) }
    }

    // MARK: - Flood detection

    /// Bytes seen across ALL panes in the current window, and when that window opened — the app's
    /// only view of how hard its terminals are being written to.
    ///
    /// SwiftTerm's `LocalProcess` reads the PTY with no backpressure and queues every chunk in an
    /// unbounded array, draining it on the main queue under a fixed time slice. When a child
    /// outruns that drain the queue diverges, and the only lever we hold is how much main-thread
    /// time we leave for it. Rendering is the competition, so we measure the pressure and hand the
    /// time back — see `TerminalRedrawCoalescer`.
    private nonisolated(unsafe) static var windowBytes = 0
    private nonisolated(unsafe) static var windowStart = DispatchTime.now().uptimeNanoseconds
    private nonisolated(unsafe) static var floodingUntil: UInt64 = 0

    /// Whether any pane is currently being written to faster than a person could read. Sampled over
    /// a short window and held briefly, so a bursty build log doesn't flap the frame rate.
    /// Main-thread only; `nonisolated(unsafe)` because `assumeIsolated` hard-traps on macOS 26.
    static var isFlooding: Bool {
        DispatchTime.now().uptimeNanoseconds < floodingUntil
    }

    /// ~2 MB/s sustained. Ordinary agent output and even a brisk build log sit far below this.
    private static let floodBytesPerSecond = 2 * 1024 * 1024

    private static func notePressure(_ count: Int) {
        windowBytes += count
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now &- windowStart
        guard elapsed >= 250_000_000 else { return }          // sample every 250 ms
        let perSecond = Int(Double(windowBytes) * 1_000_000_000.0 / Double(elapsed))
        if perSecond >= floodBytesPerSecond {
            floodingUntil = now &+ 1_000_000_000            // hold the verdict for a second
            Task { @MainActor in MemoryGuard.shared.noteFlood() }
        }
        windowBytes = 0
        windowStart = now
    }

    // MARK: - Flow control (the hard bound)

    private var childPaused = false
    private var lastChunkAt = DispatchTime.now().uptimeNanoseconds
    private var flowTimer: Timer?
    /// The pid held while paused. A plain `pid_t` so `deinit` — which is nonisolated and may not
    /// touch a non-Sendable `Timer` — still has everything it needs to let the child go.
    private var pausedPid: pid_t = 0

    /// Stop the child writing when we cannot keep up, and start it again once we have.
    ///
    /// This is the only thing that actually BOUNDS memory under a flood, because SwiftTerm parks
    /// every chunk in an unbounded `pendingChunks` array (all `private`, no knob). Throttling our
    /// own rendering slowed the climb and did not stop it, because the producer was unthrottled.
    ///
    /// So throttle the producer. `SIGSTOP` to the child's process GROUP (its pgid is the shell pid
    /// — `forkpty` gives the job its own session) halts everything writing into this pane; the
    /// backlog then drains with no new arrivals. Knowing when to resume needs no access to
    /// SwiftTerm's queue: while it still has chunks, it keeps calling `dataReceived`, so a short
    /// gap in those callbacks IS the signal that it has emptied. Ordinary XOFF/XON, done with
    /// signals because an agent CLI in raw mode has turned XON/XOFF off.
    ///
    /// A stopped process that never resumes would be a far worse bug than the one being fixed, so
    /// resumption is belt-and-braces: the idle check resumes it, a hard watchdog resumes it
    /// regardless after `maxPauseSeconds`, and teardown resumes it unconditionally. The gap is
    /// longer than feels necessary on purpose: resuming the instant callbacks pause lets the child
    /// refill a half-drained queue (a slow upward creep instead of a flat line).
    ///
    /// The 20 ms timer exists ONLY while a child is paused, i.e. only during a flood.
    private static let idleGapNs: UInt64 = 150_000_000      // 150 ms of quiet = backlog drained
    private static let maxPauseSeconds: TimeInterval = 2.0  // never hold a child longer than this

    private func pauseChildIfFlooding() {
        guard !childPaused, Self.isFlooding else { return }
        let pid = process?.shellPid ?? 0
        guard pid > 0 else { return }
        // Negative pid = the whole process group, so a shell's children stop with it. A failure
        // here is not worth reporting: the app simply keeps the behaviour it had before.
        guard kill(-pid, SIGSTOP) == 0 || kill(pid, SIGSTOP) == 0 else { return }
        childPaused = true
        pausedPid = pid
        let started = DispatchTime.now().uptimeNanoseconds
        let t = Timer(timeInterval: 0.02, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let now = DispatchTime.now().uptimeNanoseconds
            let quiet = now &- self.lastChunkAt >= Self.idleGapNs
            let expired = Double(now &- started) / 1_000_000_000 >= Self.maxPauseSeconds
            if quiet || expired { self.resumeChild() }
        }
        RunLoop.main.add(t, forMode: .common)
        flowTimer = t
    }

    /// Let the child run again. Safe to call when it isn't paused.
    func resumeChild() {
        flowTimer?.invalidate()
        flowTimer = nil
        guard childPaused else { return }
        childPaused = false
        let pid = pausedPid != 0 ? pausedPid : (process?.shellPid ?? 0)
        pausedPid = 0
        Self.resume(pid: pid)
    }

    /// Stop this pane's child and LEAVE it stopped — the memory guard's hammer. No resume timer:
    /// something is pathological, and quietly restarting it would just restart the climb.
    func haltForMemoryGuard() {
        flowTimer?.invalidate()
        flowTimer = nil
        let pid = process?.shellPid ?? 0
        guard pid > 0 else { return }
        if kill(-pid, SIGSTOP) != 0 { _ = kill(pid, SIGSTOP) }
        childPaused = true
        pausedPid = pid
    }

    /// Nonisolated so `deinit` can call it. Idempotent and harmless on a dead pid.
    fileprivate nonisolated static func resume(pid: pid_t) {
        guard pid > 0 else { return }
        if kill(-pid, SIGCONT) != 0 { _ = kill(pid, SIGCONT) }
    }

    deinit {
        // A pane torn down mid-pause must never leave a stopped process behind.
        Self.resume(pid: pausedPid)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        Self.notePressure(slice.count)
        // Every arrival is evidence the backlog is still draining; the pause logic reads this.
        lastChunkAt = DispatchTime.now().uptimeNanoseconds
        pauseChildIfFlooding()
    }

    // MARK: - App-wide pointer/scroll interceptor

    /// Install the app-wide event interceptor. Idempotent; called as each terminal is created.
    ///
    /// A local monitor is the only seam available: SwiftTerm narrows `scrollWheel` / `mouseMoved`
    /// to `public` (not `open`) so they can't be overridden, and a wrapper view never sees the
    /// events because AppKit delivers them to the deepest view under the pointer — the terminal —
    /// which consumes them. The monitor runs BEFORE that dispatch, so we get first refusal.
    ///
    /// Jobs: (1) terminal scroll that works (`handleScroll`); (2) the hover auto-clicker fix —
    /// with any-event tracking on (mode 1003, which `claude` asks for), SwiftTerm reports every
    /// bare hover with `overwriteRelease: true`; its SGR encoder turns that into `CSI<32;x;y m` —
    /// literally "left button released here" — so moving the mouse over a session spam-clicked
    /// whatever was under it. Motion reports that carry no button are dropped; real clicks and
    /// drags pass through; (3) Return notification, observed only; (4) ⌘⇧1…9 jumps to tab N.
    /// Click-to-focus is `mouseDown`.
    static func installEventMonitor() {
        guard !monitorInstalled else { return }
        monitorInstalled = true
        NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .mouseMoved, .keyDown]
        ) { event in
            switch event.type {
            case .scrollWheel:
                if let term = Self.terminal(under: event) {
                    term.handleScroll(event)
                    return nil                       // handled — don't let SwiftTerm re-handle it
                }
                return event
            case .mouseMoved:
                // Hot path: SwiftTerm installs an `.activeAlways` `.mouseMoved` tracking area on
                // EVERY pane. Two cheap guards before any tree walk is allowed.
                guard TrueTerminalView.liveCount > 0 else { return event }
                guard let term = Self.hoveredTerminal(for: event) else { return event }
                if term.getTerminal().mouseMode == .anyEvent { return nil }
                return event
            case .keyDown:
                // Matched by key position: with Shift held the digits arrive as "!@#…", which a
                // menu shortcut never matches. (⌘⇧3/4/5 are macOS screenshots and never get here.)
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
                   let n = Self.digitKeys[event.keyCode] {
                    WorkspaceModel.shared.selectTab(number: n)
                    return nil
                }
                if let term = event.window?.firstResponder as? TrueTerminalView,
                   event.charactersIgnoringModifiers?.contains("\r") == true {
                    term.onCommandSubmitted?()
                }
                return event
            default:
                return event
            }
        }
    }

    /// ANSI key codes of the 1…9 row → the digit.
    private static let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    /// Where the last pointer hit landed, so ordinary motion inside one pane costs a rect test
    /// instead of a hit test. Never trusted for longer than a moment, so a panel that opens over a
    /// pane under a resting pointer can't keep answering as the pane.
    private static var hoverCache: (view: TrueTerminalView, frame: NSRect,
                                    window: NSWindow, at: TimeInterval)?

    private static func hoveredTerminal(for event: NSEvent) -> TrueTerminalView? {
        let now = ProcessInfo.processInfo.systemUptime
        if let c = hoverCache, c.window === event.window, c.view.window != nil,
           now - c.at < 0.25, c.frame.contains(event.locationInWindow) {
            return c.view
        }
        guard let term = terminal(under: event) else { hoverCache = nil; return nil }
        if let window = event.window {
            hoverCache = (term, term.convert(term.bounds, to: nil), window, now)
        }
        return term
    }

    /// The terminal under the pointer, if any. Walks up from the hit view because SwiftTerm puts
    /// helper subviews (selection, find bar) over the terminal.
    private static func terminal(under event: NSEvent) -> TrueTerminalView? {
        guard let content = event.window?.contentView else { return nil }
        // `hitTest` wants the point in the receiver's SUPERVIEW space. The hosting view is flipped
        // and its superview isn't, so converting into `content` itself mirrored y — in a stacked
        // split the wheel went to the other pane.
        let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        guard let hit = content.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let v = view {
            if let term = v as? TrueTerminalView { return term }
            view = v.superview
        }
        return nil
    }

    private static var monitorInstalled = false
}
