import Testing
import Foundation
@testable import True

@Suite struct KeepAwakeTests {
    /// The assertion is real and is the display kind: `pmset -g assertions` lists our reason under
    /// PreventUserIdleDisplaySleep while held, and not after. The reason is unique per run so a
    /// running True.app holding its own assertion can't make this pass or fail.
    @Test @MainActor func holdKeepsTheDisplayOn() throws {
        let reason = "True test \(UUID().uuidString)"
        let k = KeepAwake(reason: reason)
        k.hold()
        #expect(k.held)
        let line = assertions().split(separator: "\n").first { $0.contains(reason) }
        #expect(line?.contains("PreventUserIdleDisplaySleep") == true)
        k.release()
        #expect(!k.held)
        #expect(!assertions().contains(reason))
        k.release()   // double release is a no-op, never a double-free
    }

    @Test func holdsOnlyWhileSomeoneIsWorkingOrWaiting() {
        #expect(KeepAwake.shouldHold([.idle, .working]))
        #expect(KeepAwake.shouldHold([.done, .needsYou]))
        #expect(!KeepAwake.shouldHold([.idle, .done, .asleep]))
        #expect(!KeepAwake.shouldHold([]))
    }

    /// A pane's status follows its hook events: a prompt starts work, Stop ends it, an interrupt
    /// that lands on the idle prompt releases it too.
    @Test func paneStatusFollowsHookEvents() {
        var s = AgentStatus.idle
        s = AgentStatus.next(after: .progress, from: s); #expect(s == .working)
        s = AgentStatus.next(after: .notification, from: s); #expect(s == .working)
        s = AgentStatus.next(after: .need, from: s); #expect(s == .needsYou)
        s = AgentStatus.next(after: .stop, from: s); #expect(!KeepAwake.shouldHold([s]))
        s = AgentStatus.next(after: .progress, from: s)
        s = AgentStatus.next(after: .idle, from: s); #expect(!KeepAwake.shouldHold([s]))
    }

    private func assertions() -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "assertions"]; let out = Pipe(); p.standardOutput = out
        try? p.run(); p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
