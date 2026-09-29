import AppKit
import IOKit.pwr_mgt

/// Holds the Mac awake while True is the frontmost app, so a long agent session survives an AFK
/// user. A power assertion is a lease on the sleep timer: while `assertion` is held, macOS does not
/// idle-sleep the system (the display may still dim — the terminals do not need it lit). Released
/// the moment another app comes to the front, so True never pins a machine it is not driving.
@MainActor
final class KeepAwake {
    static let shared = KeepAwake()
    private var assertion: IOPMAssertionID = 0
    private(set) var held = false

    /// Follow app activation. Idempotent: safe to call again after launch.
    func follow(_ app: NSApplication) {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: app, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hold() }
        }
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: app, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.release() }
        }
        if app.isActive { hold() }
    }

    func hold() {
        guard !held else { return }
        let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             "True is frontmost: agents may be mid-session" as CFString,
                                             &assertion)
        held = ok == kIOReturnSuccess
    }

    func release() {
        guard held else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        held = false
    }
}
