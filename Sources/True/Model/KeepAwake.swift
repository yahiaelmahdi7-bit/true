import Foundation
import IOKit.pwr_mgt
import Observation

/// Keeps the screen on while at least one agent is working or waiting on you, and lets the Mac
/// idle normally the moment they are all idle, done or asleep. A power assertion is a lease on the
/// idle timers: a display-sleep assertion (what `caffeinate -d` takes) stops the screen dimming and
/// the screensaver starting, so the password lock that follows either one never comes. It also
/// implies no system sleep. Driven by hook events through Observation: no timers, and nothing runs
/// while nobody is working. (Closing a laptop lid still sleeps: that is not an idle timer.)
@MainActor
final class KeepAwake {
    static let shared = KeepAwake(reason: "True: agents are working")
    let reason: String
    private var assertion: IOPMAssertionID = 0
    private(set) var held = false

    init(reason: String) { self.reason = reason }

    /// The whole rule, pure so it is testable. "Needs you" counts: an agent blocked on a prompt
    /// should find the screen unlocked when you come back to answer it.
    nonisolated static func shouldHold(_ statuses: some Sequence<AgentStatus>) -> Bool {
        statuses.contains { $0 == .working || $0 == .needsYou }
    }

    /// Follow every pane's status. Observation fires once per registration, so each change re-arms.
    func follow(_ registry: AgentRegistry) {
        withObservationTracking {
            set(Self.shouldHold(registry.paneStatus.values))
        } onChange: { [weak self, weak registry] in
            Task { @MainActor in
                guard let self, let registry else { return }
                self.follow(registry)
            }
        }
    }

    func set(_ on: Bool) { on ? hold() : release() }

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
