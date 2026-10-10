import Foundation

/// A parsed Nova action (the reflex verdict, or one Haiku tool call, as a hands-level instruction).
struct NovaAction: Sendable, Equatable {
    var action: String
    var agent: String?
    var query: String?
    var target: String?
}

/// Raw-question Jev call for the reflex. True's `JevClient` takes the compact `JevQuestion` shape;
/// the lifted reflex spec uses the richer `{what, examples}` criteria and `{question, focus}`
/// instructions, so it posts its own body — same endpoint, same key (`JevKey`), same decoder.
enum NovaJev {
    struct Reply: Sendable {
        let answers: [String: JevAnswer]
        let latency: TimeInterval
        let model: String
    }

    private static let keyBox = KeyBox()
    private final class KeyBox: @unchecked Sendable {
        private let lock = NSLock()
        private var resolved = false
        private var key: String?
        func get() -> String? {
            lock.withLock {
                if !resolved {
                    resolved = true
                    let e = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"]
                    key = (e?.isEmpty == false) ? e : JevKey.fromKeychain()
                }
                return key
            }
        }
    }
    static var isConfigured: Bool { keyBox.get() != nil }

    static func body(state: Any, questions: [String: Any]) -> Data? {
        let obj: [String: Any] = ["model": JevClient.model, "state": state, "questions": questions]
        guard JSONSerialization.isValidJSONObject(obj) else { return nil }
        return try? JSONSerialization.data(withJSONObject: obj)
    }

    /// nil on every failure (no key, network, timeout, non-2xx, garbage): callers fall through.
    static func ask(state: Any, questions: [String: Any], timeout: TimeInterval) async -> Reply? {
        guard let key = keyBox.get(), let body = body(state: state, questions: questions) else { return nil }
        var req = URLRequest(url: JevClient.endpoint)
        req.httpMethod = "POST"; req.httpBody = body; req.timeoutInterval = timeout
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let started = Date()
        let request = req
        return await withTaskGroup(of: Reply?.self) { group in
            group.addTask {
                guard let r = try? await URLSessionJevTransport().send(request), (200..<300).contains(r.status),
                      let reply = JevClient.decode(r.body) else { return nil }
                return Reply(answers: reply.answers, latency: Date().timeIntervalSince(started), model: JevClient.model)
            }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

extension JevAnswer {
    /// The probability Jev put on `option`, or 0 for one it never mentioned.
    func probability(of option: String) -> Double { probabilities?[option] ?? 0 }
}
