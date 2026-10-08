import Foundation
import CryptoKit
import Security

/// Remote Access auth: three independent checks (loopback bind, tailnet identity header, paired-device
/// cookie). All pure or injectable so the decision table is unit-tested without a socket.
enum RemoteAuth {
    static let cookieName = "true_dev"
    static let loginHeader = "Tailscale-User-Login"

    static func sha256Hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 32 random bytes, hex. The raw token only ever exists in the phone's cookie.
    static func newToken() -> String {
        var b = [UInt8](repeating: 0, count: 32)
        let rc = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        precondition(rc == errSecSuccess, "no secure randomness")
        return b.map { String(format: "%02x", $0) }.joined()
    }

    enum Decision: Equatable {
        case allow
        case forbidden(String)      // 403 — wrong network identity
        case needsPairing           // no/bad/revoked device cookie
    }

    /// Decision table, in order: identity header first (403 beats everything), then the device cookie,
    /// then (WebSocket only) the Origin check.
    static func decide(loginHeader: String?, allowedLogin: String?, deviceValid: Bool,
                       webSocketOrigin: String?, isWebSocket: Bool, host: String?) -> Decision {
        guard let allowed = allowedLogin?.lowercased(), !allowed.isEmpty else { return .forbidden("no allowed login configured") }
        guard let login = loginHeader?.lowercased(), !login.isEmpty else { return .forbidden("missing tailscale login") }
        guard login == allowed else { return .forbidden("login not allowed") }
        guard deviceValid else { return .needsPairing }
        if isWebSocket, !originMatches(origin: webSocketOrigin, host: host) { return .forbidden("origin mismatch") }
        return .allow
    }

    /// `Origin: https://mac.tailnet.ts.net:8444` must name the same host as `Host` (ports ignored: the
    /// tailnet proxy rewrites them).
    static func originMatches(origin: String?, host: String?) -> Bool {
        guard let origin, let host, let u = URL(string: origin), let oh = u.host?.lowercased() else { return false }
        let h = host.split(separator: ":").first.map { String($0).lowercased() } ?? host.lowercased()
        return !h.isEmpty && oh == h
    }
}

/// The 6-digit pairing code: fresh each time it is shown, valid 5 minutes, single use, ≤5 guesses a minute.
final class PairingCodes: @unchecked Sendable {
    enum Outcome: Equatable { case ok, wrong, expired, rateLimited }
    static let lifetime: TimeInterval = 300
    static let maxAttemptsPerMinute = 5

    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private var code: String?
    private var issuedAt = Date.distantPast
    private var attempts: [Date] = []

    init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

    /// A new code replaces any old one.
    @discardableResult
    func issue() -> String {
        lock.lock(); defer { lock.unlock() }
        var v: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &v) { SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!) }
        let c = String(format: "%06d", Int(v % 1_000_000))
        code = c; issuedAt = now()
        return c
    }

    func expiry() -> Date? {
        lock.lock(); defer { lock.unlock() }
        return code == nil ? nil : issuedAt.addingTimeInterval(Self.lifetime)
    }

    func revokeCode() { lock.lock(); code = nil; lock.unlock() }

    func attempt(_ guess: String) -> Outcome {
        lock.lock(); defer { lock.unlock() }
        let t = now()
        attempts = attempts.filter { t.timeIntervalSince($0) < 60 }
        guard attempts.count < Self.maxAttemptsPerMinute else { return .rateLimited }
        attempts.append(t)
        guard let c = code else { return .expired }
        guard t.timeIntervalSince(issuedAt) <= Self.lifetime else { code = nil; return .expired }
        guard guess == c else { return .wrong }
        code = nil
        return .ok
    }
}

struct PairedDevice: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var label: String
    var tokenHash: String
    var created: Date
    var lastSeen: Date
}

/// Paired phones, hashed at rest in Application Support (mode 0600). Raw tokens are never stored.
final class DeviceStore: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var devices: [PairedDevice]

    static var standardURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("True/remote-devices.json")
    }

    init(url: URL = DeviceStore.standardURL) {
        self.url = url
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        devices = (try? Data(contentsOf: url)).flatMap { try? dec.decode([PairedDevice].self, from: $0) } ?? []
    }

    var all: [PairedDevice] { lock.lock(); defer { lock.unlock() }; return devices }

    /// Register a new device; returns the raw token to hand to the phone exactly once.
    func pair(label: String, at date: Date = Date()) -> String {
        lock.lock(); defer { lock.unlock() }
        let token = RemoteAuth.newToken()
        devices.append(PairedDevice(id: UUID(), label: label, tokenHash: RemoteAuth.sha256Hex(token),
                                    created: date, lastSeen: date))
        save()
        return token
    }

    /// Match a presented token by hash; touches last-seen (at most once a minute, to spare the disk).
    func validate(_ token: String?, at date: Date = Date()) -> PairedDevice? {
        guard let token, !token.isEmpty else { return nil }
        let h = RemoteAuth.sha256Hex(token)
        lock.lock(); defer { lock.unlock() }
        guard let i = devices.firstIndex(where: { $0.tokenHash == h }) else { return nil }
        if date.timeIntervalSince(devices[i].lastSeen) > 60 { devices[i].lastSeen = date; save() }
        return devices[i]
    }

    func revoke(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        devices.removeAll { $0.id == id }
        save()
    }

    private func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        guard let data = try? enc.encode(devices) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
