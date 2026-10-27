import Testing
import Foundation
import SwiftUI
import AppKit
@testable import True

/// Stills of the v4 Hub board, dark and light, from fixtures. Skipped unless TRUE_SNAPSHOT_DIR is set:
/// `TRUE_SNAPSHOT_DIR=$PWD/.out/stills/hub-v4-tiles swift test --filter HubBoardStillsTests`.
@MainActor
@Suite(.enabled(if: !(ProcessInfo.processInfo.environment["TRUE_SNAPSHOT_DIR"] ?? "").isEmpty,
                "TRUE_SNAPSHOT_DIR not set"))
struct HubBoardStillsTests {
    private var dir: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["TRUE_SNAPSHOT_DIR"] ?? "/tmp") }
    private static let now = HubBoardFixture.now

    private func snapshot<V: View>(_ name: String, width: CGFloat, height: CGFloat, dark: Bool, @ViewBuilder _ view: () -> V) throws {
        let ink = HubInk(dark ? .dark : .light)
        let root = view().frame(width: width, height: height, alignment: .topLeading)
            .environment(\.colorScheme, dark ? .dark : .light).background(ink.surface)
        let host = NSHostingView(rootView: root)
        let size = NSSize(width: width, height: height)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { Issue.record("no bitmap rep"); return }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { Issue.record("no png"); return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    private func hub(_ buckets: [TriageBucket]) -> some View {
        HubPanelContent(groups: [], allSeats: [], filter: .constant(.all), now: Self.now, actions: .inert, bucketsOverride: buckets)
    }

    @Test func stills() throws {
        for dark in [true, false] {
            try snapshot("1-board", width: 1000, height: 780, dark: dark) { hub(HubBoardFixture.today) }
            try snapshot("2-empty", width: 1000, height: 520, dark: dark) { hub([]) }
            let model = CloudComposerModel(projects: [])
            model.link = .online
            model.selected = CloudRepoInfo(path: "/Users/y/Projects/gamenight", kind: .ready, branch: "main", sha: "a1b2c3d4e5",
                                           subject: "Fix footer links", committedAt: Self.now - 3600, dirtyCount: 0)
            try snapshot("3-new-composer", width: CloudComposerContent.width, height: 613, dark: dark) {
                CloudComposerContent(model: model, now: Self.now)
            }
            let tile = try #require(HubTriage.board(HubBoardFixture.today).needsYou.first { $0.title == "9 reviews waiting" })
            try snapshot("4-tile-sheet", width: HubTileSheet.width, height: 500, dark: dark) {
                HubTileSheet(tile: tile, now: Self.now, onItem: { _ in }, onClose: {})
            }
        }
    }
}
