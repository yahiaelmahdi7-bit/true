import Testing
import Foundation
@testable import True

/// Opt-in (`TRUE_LIVE_LAN=1`): two in-process engines with temp dirs and the real Bonjour transport. Never runs by default.
/// The full-flow case also needs the real relay (`TRUE_LIVE_RELAY=1`).
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["TRUE_LIVE_LAN"] == "1")) struct PeerLanLiveTests {
    @MainActor final class Side {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("true-live-lan-\(UUID().uuidString)")
        let identity = PeerIdentity.generate(), launcher = FakeLauncher()
        let engine: PeerEngine
        let lan: PeerLanCoordinator
        init(_ name: String, relay: PeerTransport) {
            engine = PeerEngine(root: root, identity: identity, launcher: launcher, transport: relay, inboundMode: { .bypass },
                                ownName: name, steering: { true }, share: { .activity }, allowedDirs: { [] }, chatOn: { false },
                                sharedRepos: { [:] }, setSharedRepos: { _ in }, desk: { false }, projectsRoot: root.path + "/Projects",
                                now: { Date() }, scheduler: { s, f in DispatchQueue.global().asyncAfter(deadline: .now() + s, execute: f) })
            lan = PeerLanCoordinator(transport: PeerLanNetwork(), engine: engine)
        }
        func close() { lan.close(); try? FileManager.default.removeItem(at: root) }
    }

    private func until(_ timeout: TimeInterval, _ ok: @MainActor () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if ok() { return true }; try? await Task.sleep(nanoseconds: 200_000_000) }
        return ok()
    }

    @Test func eachSeesTheOtherWithinFiveSecondsAndPairedAfterPinning() async throws {
        let relay = FakeRelay()
        let a = Side("Live Al \(UUID().uuidString.prefix(4))", relay: relay.transport(for: "a")), b = Side("Live Bo \(UUID().uuidString.prefix(4))", relay: relay.transport(for: "b"))
        defer { a.close(); b.close() }
        a.lan.open(); b.lan.open()
        #expect(await until(5) { a.lan.rows.contains { $0.name == b.engine.ownName } && b.lan.rows.contains { $0.name == a.engine.ownName } })
        #expect(a.lan.rows.first { $0.name == b.engine.ownName }?.paired == false)
        _ = a.engine.pairWithInvite(b.engine.invite(), label: "Bea")
        a.lan.close(); a.lan.open()
        #expect(await until(5) { a.lan.rows.first { $0.name == b.engine.ownName }?.paired == true })
    }
}
