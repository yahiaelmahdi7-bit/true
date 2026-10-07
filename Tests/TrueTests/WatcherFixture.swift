import Foundation

/// Reads the FIXED hand-labelled Watcher set (Fixtures/watcher-labelled.json) or the fresh set in env WATCHER_FRESH.
/// Never edited by tests.
enum WatcherFixture {
    static var url: URL {
        if let p = ProcessInfo.processInfo.environment["WATCHER_FRESH"], !p.isEmpty { return URL(fileURLWithPath: p) }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/watcher-labelled.json")
    }
    static var devURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/watcher-labelled.json")
    }
    static func load(_ u: URL = devURL) -> [String: Any] {
        guard let d = try? Data(contentsOf: u), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return j
    }
    static func list(_ key: String, _ u: URL = devURL) -> [[String: Any]] { load(u)[key] as? [[String: Any]] ?? [] }
}
