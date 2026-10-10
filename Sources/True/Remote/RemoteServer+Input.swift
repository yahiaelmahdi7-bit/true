import Foundation

/// The phone composer's door: one whole prompt per request, delivered through PaneDelivery (the only
/// thing that may type into a pane). Auth already ran in `handle`; the text is never logged.
extension RemoteServer {
    static let maxPaneInputBytes = 64 * 1024

    /// POST /api/pane/<uuid>/input {"intent","text"} → {"outcome"}. 404 unknown pane, 400 bad body.
    func handlePaneInput(_ fd: Int32, _ req: HTTPRequest) {
        func reply(_ status: Int, _ reason: String, _ obj: [String: Any]) {
            let body = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
            _ = send(fd, HTTPResponse.make(status: status, reason: reason, body: [UInt8](body), contentType: "application/json"))
        }
        let idPart = String(req.path.dropFirst("/api/pane/".count).dropLast("/input".count))
        guard let pane = UUID(uuidString: idPart) else { reply(404, "Not Found", ["error": "No such pane"]); return }
        let len = req.declaredLength
        guard len > 0 else { reply(len == 0 ? 400 : 411, len == 0 ? "Bad Request" : "Length Required", ["error": "Send JSON"]); return }
        guard len <= Self.maxPaneInputBytes else { reply(413, "Payload Too Large", ["error": "Over 64 KB"]); return }
        var body = Array(req.body.prefix(len))
        if DropReceiver.pump(fd, have: body.count, total: len, deadline: HTTPRequest.bodyDeadline, sink: { body += $0; return true }) != .ok {
            reply(408, "Request Timeout", ["error": "Too slow"]); return
        }
        guard let o = (try? JSONSerialization.jsonObject(with: Data(body))) as? [String: Any],
              let name = o["intent"] as? String, let intent = PaneInputIntent(rawValue: name) else {
            reply(400, "Bad Request", ["error": "Need {\"intent\",\"text\"}"]); return
        }
        let text = o["text"] as? String ?? ""
        if intent == .prompt || intent == .stage || intent == .control,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reply(400, "Bad Request", ["error": "Need text"]); return
        }
        guard let outcome = backend.paneInput(pane: pane, intent: intent, text: text) else {
            reply(404, "Not Found", ["error": "No such pane"]); return
        }
        reply(200, "OK", ["outcome": outcome])
    }
}
