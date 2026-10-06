import Foundation
import os

/// `~/.true/overseer/verdicts.jsonl`: one line per judgment, the calibration set for the thresholds (and for
/// Run 13). Directory 0700, file 0600, state already redacted. Over 5 MB the file becomes `verdicts.1.jsonl`
/// (one old file kept). Plain file IO on the caller's thread; the store calls it off the main actor.
struct OverseerLog: Sendable {
    static let maxBytes = 5 << 20
    static let logger = Logger(subsystem: "net.prismlens.true", category: "overseer")
    static let standard = OverseerLog(dir: URL(fileURLWithPath: NSHomeDirectory() + "/.true/overseer"))

    let dir: URL
    var file: URL { dir.appendingPathComponent("verdicts.jsonl") }
    var rotated: URL { dir.appendingPathComponent("verdicts.1.jsonl") }

    struct Record: Sendable {
        var at: Date
        var pane: UUID
        var session: String?
        var cwd: String?
        var judgment: OverseerJudgment
        var latencyMs: Int
        var digest: TurnDigest      // already redacted
    }

    /// The os.Logger line: pane prefix, outcome + confidence, proof, contradiction, next_safe, verdict, ms, state chars.
    static func line(_ r: Record) -> String {
        func p(_ d: Double?) -> String { d.map { String(format: "%.2f", $0) } ?? "-" }
        let j = r.judgment
        return "pane=\(r.pane.uuidString.prefix(8)) outcome=\(j.outcome ?? "-")@\(p(j.outcomeConfidence)) "
            + "proof=\(p(j.proof)) contradiction=\(p(j.contradiction)) next_safe=\(p(j.nextSafe)) "
            + "verdict=\(j.verdict?.rawValue ?? "none") ms=\(r.latencyMs) chars=\(r.digest.stateChars)"
    }

    static func json(_ r: Record) -> [String: Any] {
        let j = r.judgment
        var answers: [String: Any] = [:]
        if let o = j.outcome { answers["outcome"] = ["choice": o, "confidence": j.outcomeConfidence ?? NSNull(),
                                                     "probabilities": j.outcomeProbabilities ?? [:]] as [String: Any] }
        if let v = j.proof { answers["proof"] = ["noul": v] }
        if let v = j.contradiction { answers["contradiction"] = ["noul": v] }
        if let v = j.nextSafe { answers["next_safe"] = ["noul": v] }
        return ["at": ISO8601DateFormatter().string(from: r.at), "pane": r.pane.uuidString,
                "session": r.session ?? NSNull(), "cwd": r.cwd ?? NSNull(),
                "verdict": j.verdict?.rawValue ?? NSNull(), "reason": j.reason ?? NSNull(),
                "answers": answers, "latencyMs": r.latencyMs, "state": r.digest.state]
    }

    func append(_ r: Record) {
        Self.logger.info("\(Self.line(r), privacy: .public)")
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(dir.path, 0o700)
        let obj = Self.json(r)
        guard JSONSerialization.isValidJSONObject(obj),
              var data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        data.append(10)
        if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > Self.maxBytes {
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: file, to: rotated)
        }
        if !fm.fileExists(atPath: file.path) {
            fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        chmod(file.path, 0o600)
        guard let h = try? FileHandle(forWritingTo: file) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: data)
    }
}
