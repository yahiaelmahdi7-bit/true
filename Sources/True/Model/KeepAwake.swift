import Foundation
import IOKit.pwr_mgt

/// Keeps the screen on for as long as True is open. A power assertion is a lease on the idle timers:
/// a display-sleep assertion (what `caffeinate -d` takes) stops the screen dimming and the
/// screensaver starting, so the password lock that follows either one never comes. It also implies
/// no system sleep. Taken once at launch; the kernel drops it the moment the process exits, so a
/// quit (or a crash) can never leave the Mac pinned awake. (Closing a laptop lid still sleeps: that
/// is not an idle timer.)
@MainActor
final class KeepAwake {
    static let shared = KeepAwake(reason: "True is open")
    let reason: String
    private var assertion: IOPMAssertionID = 0
    private(set) var held = false

    init(reason: String) { self.reason = reason }

    func hold() {
        guard !held else { return }
        let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             reason as CFString, &assertion)
        held = ok == kIOReturnSuccess
    }

    func release() {
        guard held else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        held = false
    }
}
