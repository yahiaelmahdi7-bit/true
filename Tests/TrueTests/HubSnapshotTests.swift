import Testing
import Foundation
import SwiftUI
import AppKit
@testable import True

/// Renders the Hub from fixtures to PNGs (the only way to see it without launching True.app).
/// Skipped unless TRUE_SNAPSHOT_DIR is set: `TRUE_SNAPSHOT_DIR=$PWD/docs/design/hub-v2 swift test --filter HubSnapshotTests`.
@MainActor
@Suite(.enabled(if: !(ProcessInfo.processInfo.environment["TRUE_SNAPSHOT_DIR"] ?? "").isEmpty,
                "TRUE_SNAPSHOT_DIR not set"))
struct HubSnapshotTests {
    private var dir: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TRUE_SNAPSHOT_DIR"] ?? "/tmp")
    }

    /// Host in an offscreen borderless window (never ordered front), dark appearance, 2x PNG.
    private func snapshot<V: View>(_ name: String, width: CGFloat, height: CGFloat? = nil, @ViewBuilder _ view: () -> V) throws {
        let root = view().frame(width: width, height: height, alignment: .topLeading).environment(\.colorScheme, .dark).background(Theme.background)
        let host = NSHostingView(rootView: root)
        let fitted = host.fittingSize
        let size = NSSize(width: width, height: height ?? max(fitted.height, 100))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI settle (transitions, .task) before capture.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { Issue.record("no bitmap rep"); return }
        rep.size = NSSize(width: size.width, height: size.height)
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { Issue.record("no png"); return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    // MARK: fixtures

    private static let now = 1_800_000_000.0
    private let lead = Agent(name: "lead", role: .lead, repo: "/Users/y/Projects/true", model: .opus, effort: .high,
                             permission: .auto, symbol: "crown", hue: "coral")
    private let helper = Agent(name: "true-hub-design-helper-with-a-very-long-name", role: .helper,
                               repo: "/Users/y/Projects/true", model: .sonnet, effort: .low, permission: .default)
    private let cfo = Agent(name: "cfo", role: .lead, repo: "/Users/y/Projects/finance-desk", model: .opus,
                            effort: .medium, permission: .acceptEdits)

    private func builder(_ id: String, _ cwd: String, state: BuilderState, parent: String?, acked: Bool = false) -> BuilderRecord {
        BuilderRecord(id: id, name: id, cwd: cwd, originCwd: cwd, model: "sonnet", sessionID: "s-\(id)", claudePID: 0,
                      started: Self.now - 1500, ended: state == .running ? nil : Self.now - 200, state: state,
                      acked: acked, parent: parent, branch: nil, worktree: nil, cost: 1.2, budget: 5, dir: nil)
    }

    private var statuses: [String: AgentStatus] { ["lead": .working, helper.name: .asleep, "cfo": .needsYou] }
    private var actions: SeatActions {
        var a = SeatActions.inert
        let s = statuses
        a.status = { s[$0] ?? .asleep }
        a.isAwake = { (s[$0] ?? .asleep) != .asleep }
        return a
    }

    private func groups(seatsOnly: Bool = false) -> [HubProjectGroup] {
        let peers = [PeerSession(pid: Int32(ProcessInfo.processInfo.processIdentifier), sessionID: "p1",
                                 cwd: "/Users/y/Projects/true", name: "scratch", kind: "interactive", busy: false,
                                 updatedAt: Self.now - 60)]
        let builders = [builder("true-hub-design", "/Users/y/Projects/true", state: .running, parent: "lead"),
                        builder("true-fixes", "/Users/y/Projects/true", state: .done, parent: nil),
                        builder("ledger-audit", "/Users/y/Projects/finance-desk", state: .failed, parent: "cfo")]
        return HubModel.build(seats: [lead, helper, cfo], seatStatus: { self.statuses[$0] ?? .asleep },
                              seatAwake: { (self.statuses[$0] ?? .asleep) != .asleep }, peers: peers,
                              builders: builders, now: Self.now, seatsOnly: seatsOnly, hasGit: { _ in true })
    }

    private func hub(groups: [HubProjectGroup], seats: [Agent], seatsOnly: Bool = false) -> some View {
        HubPanelContent(groups: groups, allSeats: seats, filter: .constant(seatsOnly ? .seats : .all), now: Self.now, actions: actions)
    }

    // MARK: snapshots

    @Test func hubAll() throws {
        try snapshot("hub-all", width: HubPanelContent.width) { hub(groups: groups(), seats: [lead, helper, cfo]) }
    }

    @Test func hubSeats() throws {
        try snapshot("hub-seats", width: HubPanelContent.width) {
            hub(groups: groups(seatsOnly: true), seats: [lead, helper, cfo], seatsOnly: true)
        }
    }

    @Test func hubEmpty() throws {
        try snapshot("hub-empty", width: HubPanelContent.width, height: 420) { hub(groups: [], seats: []) }
    }

    @Test func builderColour() throws {
        try snapshot("builder-colour", width: 420) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    AgentAvatar(hue: .aqua, symbol: "crown", status: .idle, size: 56)
                    VStack(alignment: .leading) {
                        Text("lead").font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                        Text("Opus · Auto").font(.caption).foregroundStyle(Theme.hubSecondary)
                    }
                }
                Text("Colour").font(.caption.weight(.medium)).foregroundStyle(Theme.hubSecondary)
                HueRow(selection: .constant(.aqua))
            }.padding(20)
        }
    }

    @Test func avatars() throws {
        let states: [AgentStatus] = [.asleep, .idle, .working, .needsYou]
        try snapshot("avatars", width: 480) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(AgentHue.allCases, id: \.self) { h in
                    HStack(spacing: 18) {
                        Text(h.rawValue).font(.caption).foregroundStyle(Theme.hubSecondary).frame(width: 64, alignment: .leading)
                        ForEach(states, id: \.self) { s in AgentAvatar(hue: h, symbol: "crown", status: s, size: 40).frame(width: 52, height: 52) }
                    }
                }
                HStack(spacing: 18) {
                    AgentAvatar(hue: .rose, symbol: "hammer", status: .working, size: 28, parentHue: .azure)
                    AgentAvatar(hue: nil, symbol: "terminal", status: .idle, size: 28)
                }
            }.padding(20)
        }
    }
}
