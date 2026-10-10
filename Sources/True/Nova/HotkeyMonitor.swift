import AppKit
import CoreGraphics

/// Watches the whole session for the chosen hold key (Fn or right ⌥) via a listen-only
/// `CGEventTap` on `flagsChanged`. Emits rising/falling edges to `onEdge`. Requires Input
/// Monitoring; posting text later requires Accessibility (see `VoiceSystem`).
///
/// The tap callback is a C function pointer (no captured context) that recovers `self` from the
/// `refcon` and hops to the main actor. We attach the run-loop source to the main run loop, so the
/// callback already runs on the main thread; `@unchecked Sendable` + a hop keep Swift 6 happy.
final class HotkeyMonitor: @unchecked Sendable {
    /// Called on the main actor with `true` on press, `false` on release, deduped to real edges.
    var onEdge: ((Bool) -> Void)?

    private var hotkey: Hotkey = .fn
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pressed = false

    var isRunning: Bool { tap != nil }

    /// True when a keyboard event tap can be created — i.e. Input Monitoring is granted.
    static var canListen: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    static func requestListen() -> Bool { CGRequestListenEventAccess() }

    func setHotkey(_ hotkey: Hotkey) { self.hotkey = hotkey; pressed = false }

    /// Start the tap. No-op if already running or if Input Monitoring isn't granted.
    func start() {
        guard tap == nil, HotkeyMonitor.canListen else { return }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    monitor.reenable()
                    return Unmanaged.passUnretained(event)
                }
                // Pull primitives out before hopping — CGEvent isn't Sendable.
                let flags = event.flags
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let down = monitor.isDown(flags: flags, keyCode: keyCode)
                // The source is on the main run loop, so we're already on main. Hop via a main-actor
                // Task rather than `assumeIsolated`: the latter calls `swift_task_isCurrentExecutor`,
                // which crashes on macOS 26 (see the note in Package.swift). Task scheduling targets
                // the main executor directly with no such check; a one-tick delay is imperceptible.
                Task { @MainActor in monitor.deliver(down) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        tap = nil; source = nil; pressed = false
    }

    private func reenable() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }

    /// Is the active hotkey currently held, given a flagsChanged snapshot?
    private func isDown(flags: CGEventFlags, keyCode: Int64) -> Bool {
        switch hotkey {
        case .fn:
            return flags.contains(.maskSecondaryFn)
        case .rightOption:
            // keyCode 61 == right Option; the flag reflects whether it's now down.
            return keyCode == 61 && flags.contains(.maskAlternate)
        }
    }

    /// Dedup to true edges, then forward on the main actor.
    private func deliver(_ down: Bool) {
        guard down != pressed else { return }
        pressed = down
        onEdge?(down)
    }
}
