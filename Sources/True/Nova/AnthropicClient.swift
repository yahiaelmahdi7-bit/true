import Foundation

/// Raw-HTTP Messages API client for Nova's brain (Swift has no official SDK). Authoritative refs:
/// `.claude/briefs/run26-refs/api-*.md`. Model `claude-haiku-5-5`; NO temperature/top_p/top_k, NO prefill,
/// `tool_choice` auto only; `thinking` omitted (adaptive default). Key: Keychain `net.prismlens.true`/`anthropic`
/// (env fallback `ANTHROPIC_API_KEY`), never logged.
enum AnthropicRequest {
    static let model = "claude-haiku-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let version = "2023-06-01"
    static let maxTokens = 4096

    /// `tools` are custom tool dicts (already `strict` + `additionalProperties:false`). The cache breakpoints sit on the
    /// stable prefix only: the last tool and the system block. Volatile data (roster, focus, reflex prior) is user-turn.
    static func body(system: String, tools: [[String: Any]], messages: [[String: Any]], effort: String,
                     computerToolset: Bool = false, stream: Bool = true) -> [String: Any] {
        var allTools = tools
        if computerToolset { allTools.append(["type": "computer_toolset_20260801"]) }   // no `name` on toolset members
        if !allTools.isEmpty {
            var last = allTools.removeLast()
            last["cache_control"] = ["type": "ephemeral"]
            allTools.append(last)
        }
        var b: [String: Any] = [
            "model": model, "max_tokens": maxTokens, "stream": stream,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": messages,
            "output_config": ["effort": effort],
        ]
        if !allTools.isEmpty { b["tools"] = allTools; b["tool_choice"] = ["type": "auto"] }
        return b
    }

    static func urlRequest(body: Data, key: String) -> URLRequest {
        var r = URLRequest(url: endpoint, timeoutInterval: 60)
        r.httpMethod = "POST"
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(version, forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = body
        return r
    }
}

/// One parsed SSE frame.
struct SSEEvent: Equatable { let event: String; let data: [String: AnyHashable] }

/// Incremental SSE parser: feed lines, get events when a blank line closes a frame.
struct SSEParser {
    private var event = ""
    private var data = ""
    mutating func feed(line: String) -> SSEEvent? {
        if line.isEmpty {
            defer { event = ""; data = "" }
            guard !data.isEmpty, let d = data.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: AnyHashable] else { return nil }
            return SSEEvent(event: event.isEmpty ? (obj["type"] as? String ?? "") : event, data: obj)
        }
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") { event = line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
        else if line.hasPrefix("data:") { data += line.dropFirst(5).trimmingCharacters(in: .whitespaces) }
        return nil
    }
    static func parse(_ text: String) -> [SSEEvent] {
        var p = SSEParser(); var out: [SSEEvent] = []
        for l in text.components(separatedBy: "\n") { if let e = p.feed(line: l) { out.append(e) } }
        if let e = p.feed(line: "") { out.append(e) }
        return out
    }
}

enum BrainError: Error, Equatable { case api(String), http(Int), noKey, transport(String) }

/// Builds the assistant message from stream events. Content blocks are read BY TYPE (thinking may come first) and kept
/// verbatim so the history stays append-only and thinking blocks go back unchanged.
struct MessageAccumulator {
    private(set) var blocks: [Int: [String: Any]] = [:]
    private var partialJSON: [Int: String] = [:]
    private(set) var stopReason: String?
    private(set) var error: String?
    private(set) var finished = false

    /// Returns streamed text (for sentence-by-sentence speech), if this event carried any.
    mutating func apply(_ e: SSEEvent) -> String? {
        let d = e.data
        switch e.event {
        case "content_block_start":
            guard let i = d["index"] as? Int, var b = d["content_block"] as? [String: Any] else { return nil }
            if b["type"] as? String == "tool_use" { b["input"] = [String: Any]() }
            blocks[i] = b
        case "content_block_delta":
            guard let i = d["index"] as? Int, let delta = d["delta"] as? [String: Any], var b = blocks[i] else { return nil }
            switch delta["type"] as? String {
            case "text_delta": let t = delta["text"] as? String ?? ""; b["text"] = (b["text"] as? String ?? "") + t; blocks[i] = b; return t
            case "thinking_delta": b["thinking"] = (b["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
            case "signature_delta": b["signature"] = delta["signature"] as? String ?? ""
            case "input_json_delta": partialJSON[i, default: ""] += delta["partial_json"] as? String ?? ""
            default: break
            }
            blocks[i] = b
        case "content_block_stop":
            if let i = d["index"] as? Int, var b = blocks[i], b["type"] as? String == "tool_use" {
                let raw = partialJSON[i] ?? ""
                b["input"] = raw.isEmpty ? [String: Any]()
                    : ((try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? ["__invalid_json": raw])
                blocks[i] = b
            }
        case "message_delta":
            if let delta = d["delta"] as? [String: Any], let s = delta["stop_reason"] as? String { stopReason = s }
        case "message_stop": finished = true
        case "error":
            error = ((d["error"] as? [String: Any])?["message"] as? String) ?? "stream error"
        default: break   // ping, message_start, unknown future events
        }
        return nil
    }

    var content: [[String: Any]] { blocks.keys.sorted().compactMap { blocks[$0] } }
    var toolUses: [[String: Any]] { content.filter { $0["type"] as? String == "tool_use" } }
    var text: String { content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined() }
}

/// The wire. Tests inject a fake; live uses URLSession bytes.
protocol MessagesTransport: Sendable {
    func stream(body: [String: Any]) -> AsyncThrowingStream<SSEEvent, Error>
}

struct LiveMessagesTransport: MessagesTransport {
    func stream(body: [String: Any]) -> AsyncThrowingStream<SSEEvent, Error> {
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return AsyncThrowingStream { cont in
            let task = Task {
                do {
                    guard let key = Vault.get("anthropic", envFallback: ["ANTHROPIC_API_KEY"]) else { throw BrainError.noKey }
                    let req = AnthropicRequest.urlRequest(body: payload, key: key)
                    var attempt = 0
                    while true {
                        do {
                            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                            if code == 429 || code >= 500, attempt == 0 { attempt = 1; try await Task.sleep(for: .milliseconds(800)); continue }
                            if code != 200 { throw BrainError.http(code) }     // 400s are never retried
                            var p = SSEParser()
                            for try await line in bytes.lines { if let e = p.feed(line: line) { cont.yield(e) } }
                            if let e = p.feed(line: "") { cont.yield(e) }
                            cont.finish(); return
                        } catch let e as URLError where attempt == 0 && e.code != .cancelled {
                            attempt = 1; try await Task.sleep(for: .milliseconds(800))
                        }
                    }
                } catch { cont.finish(throwing: error) }
            }
            cont.onTermination = { _ in task.cancel() }   // reflex won → cancel = URLSession task cancelled
        }
    }
}
