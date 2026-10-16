import Foundation
import os

/// Ring buffer of on-duty events (keep-alive + poll loop), kept in UserDefaults and mirrored to os_log.
@MainActor
enum DutyDiag {
    private static let key = "dutyLog"
    private static let maxLines = 120
    private static let log = Logger(subsystem: "net.prismlens.true", category: "duty")
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    /// Newest first.
    static var lines: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func note(_ s: String) {
        log.notice("\(s, privacy: .public)")
        var all = lines
        all.insert("\(stamp.string(from: Date()))  \(s)", at: 0)
        UserDefaults.standard.set(Array(all.prefix(maxLines)), forKey: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
