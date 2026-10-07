import Testing
import Foundation
import Carbon.HIToolbox
@testable import True

@Suite struct ShotsOverlayTests {
    private func entry(_ id: String, _ date: Date) -> TrayEntry {
        TrayEntry(id: id, file: "shots/\(id).png", created: date, kind: .original, parent: nil,
                  source: nil, width: 10, height: 10)
    }
    private func cal(_ tz: String) -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: tz)!; return c
    }
    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    @Test func groupsAcrossMidnight() {
        let c = cal("UTC")
        let now = date("2026-10-08T00:30:00Z")
        let g = ShotsOverlayLogic.group([entry("a", date("2026-10-08T00:10:00Z")),
                                         entry("b", date("2026-10-07T23:50:00Z")),
                                         entry("c", date("2026-10-05T12:00:00Z"))], now: now, calendar: c)
        #expect(g.map(\.title) == ["Today", "Yesterday", "Earlier"])
        #expect(g.map { $0.entries.map(\.id) } == [["a"], ["b"], ["c"]])
    }

    @Test func groupingFollowsTheCalendarTimeZone() {
        // 23:30 UTC on the 7th is already the 8th in Tokyo.
        let e = entry("a", date("2026-10-07T23:30:00Z"))
        let now = date("2026-10-08T05:00:00Z")
        #expect(ShotsOverlayLogic.group([e], now: now, calendar: cal("UTC")).first?.title == "Yesterday")
        #expect(ShotsOverlayLogic.group([e], now: now, calendar: cal("Asia/Tokyo")).first?.title == "Today")
    }

    @Test func emptyGroupsAreDropped() {
        #expect(ShotsOverlayLogic.group([], now: Date(), calendar: cal("UTC")).isEmpty)
        let g = ShotsOverlayLogic.group([entry("a", date("2026-01-01T00:00:00Z"))], now: date("2026-10-08T00:00:00Z"), calendar: cal("UTC"))
        #expect(g.map(\.title) == ["Earlier"])
    }

    @Test func pinchClampsColumns() {
        #expect(ShotsOverlayLogic.columns(base: 5, pinchScale: 1) == 5)
        #expect(ShotsOverlayLogic.columns(base: 5, pinchScale: 2) == 3)      // 2.5 rounds to 3 (floor of range anyway)
        #expect(ShotsOverlayLogic.columns(base: 5, pinchScale: 100) == 3)
        #expect(ShotsOverlayLogic.columns(base: 5, pinchScale: 0.1) == 9)
        #expect(ShotsOverlayLogic.columns(base: 5, pinchScale: 0.5) == 9)    // 10 → clamped
        #expect(ShotsOverlayLogic.columns(base: 5, pinchScale: .nan) == 5)
        #expect(ShotsOverlayLogic.columns(base: 5, pinchScale: 0) == 5)
        #expect(ShotsOverlayLogic.clampColumns(0) == 3 && ShotsOverlayLogic.clampColumns(40) == 9)
    }

    @Test func hotKeyMapsToCarbon() {
        #expect(ShotsHotKey.carbonKeyCode == UInt32(kVK_ANSI_S))
        #expect(ShotsHotKey.carbonModifiers == UInt32(controlKey | optionKey | cmdKey))
        #expect(ShotsHotKey.eventModifiers == [.control, .option, .command])
    }

    @Test func picksTheMouseScreen() {
        let frames = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        #expect(ShotsOverlayLogic.screenIndex(mouse: CGPoint(x: 1500, y: 100), frames: frames) == 1)
        #expect(ShotsOverlayLogic.screenIndex(mouse: CGPoint(x: 10, y: 10), frames: frames) == 0)
        #expect(ShotsOverlayLogic.screenIndex(mouse: CGPoint(x: -5, y: 10), frames: frames) == nil)
        #expect(ShotsOverlayLogic.screenIndex(mouse: .zero, frames: []) == nil)
    }

    @Test func insetsClearMenuBarDockAndNotch() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let visible = CGRect(x: 0, y: 70, width: 1000, height: 700)   // 30 menu bar on top, 70 Dock at the bottom
        let i = ShotsOverlayLogic.contentInsets(frame: frame, visible: visible, safeTop: 0, margin: 20)
        #expect(i.top == 50 && i.bottom == 90 && i.leading == 20 && i.trailing == 20)
        #expect(ShotsOverlayLogic.contentInsets(frame: frame, visible: frame, safeTop: 38, margin: 20).top == 58)
    }

    @Test func dropFilterAcceptsImagesOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.png", "b.JPG", "c.heic", "d.txt", "e.pdf", "f"] {
            try Data([0]).write(to: dir.appendingPathComponent(name))
        }
        let ok = { ShotsOverlayLogic.acceptsDrop(dir.appendingPathComponent($0)) }
        #expect(ok("a.png") && ok("b.JPG") && ok("c.heic"))
        #expect(!ok("d.txt") && !ok("e.pdf") && !ok("f"))
        #expect(!ShotsOverlayLogic.acceptsDrop(dir))
        #expect(!ShotsOverlayLogic.acceptsDrop(URL(string: "https://example.com/a.png")!))
    }

    @Test func viewerStopsAtTheEnds() {
        #expect(ShotsOverlayLogic.neighbor(of: 0, count: 3, step: -1) == nil)
        #expect(ShotsOverlayLogic.neighbor(of: 2, count: 3, step: 1) == nil)
        #expect(ShotsOverlayLogic.neighbor(of: 1, count: 3, step: 1) == 2)
        #expect(ShotsOverlayLogic.neighbor(of: 1, count: 3, step: -1) == 0)
        #expect(ShotsOverlayLogic.neighbor(of: 0, count: 0, step: 1) == nil)
    }
}
