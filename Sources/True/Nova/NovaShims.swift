import Foundation
import Security

// Small stand-ins for Axon types the lifted voice code references (Axon's VoiceModels/VoiceConfig/Vault).

/// Push-to-talk key (lifted from Axon's `Hotkey`).
enum Hotkey: String, CaseIterable, Codable, Identifiable, Sendable {
    case fn, rightOption
    var id: String { rawValue }
    var label: String { self == .fn ? "fn" : "right ⌥" }
}

/// Transcription failures (subset of Axon's `VoiceError`; Apple live is the only backend in True v1).
enum VoiceError: Error, LocalizedError {
    case unavailable(String), noAudio, empty, cli(String)
    var errorDescription: String? {
        switch self {
        case .unavailable(let w): return "\(w) isn't available"
        case .noAudio: return "no audio"
        case .empty: return "heard nothing"
        case .cli(let m): return m
        }
    }
}

/// Keychain access through `/usr/bin/security` (same as `JevKey`: no access dialog, value never logged).
/// Service `net.prismlens.true`; account per secret (`anthropic`, `elevenlabs`).
enum Vault {
    static let service = "net.prismlens.true"

    static func get(_ account: String, envFallback: [String] = []) -> String? {
        for name in envFallback { if let v = ProcessInfo.processInfo.environment[name], !v.isEmpty { return v } }
        let (status, out) = run(["find-generic-password", "-s", service, "-a", account, "-w"])
        let key = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return status == 0 && !key.isEmpty ? key : nil
    }
    static func has(_ account: String, envFallback: [String] = []) -> Bool {
        get(account, envFallback: envFallback) != nil
    }
    @discardableResult
    static func set(_ account: String, _ value: String) -> Bool {   // Security.framework: the value never appears in a process argv (L1)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let data = Data(value.utf8)
        let upd = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if upd == errSecSuccess { return true }
        guard upd == errSecItemNotFound else { return false }
        return SecItemAdd((q.merging([kSecValueData as String: data]) { a, _ in a }) as CFDictionary, nil) == errSecSuccess
    }
    @discardableResult
    static func delete(_ account: String) -> Bool {
        run(["delete-generic-password", "-s", service, "-a", account]).0 == 0
    }

    /// Test seam: sees every argv this enum would spawn (the write path must spawn nothing).
    nonisolated(unsafe) static var processSpy: (([String]) -> Void)?
    private static func run(_ args: [String]) -> (Int32, String) {
        processSpy?(args)
        guard let r = Subprocess.exec("/usr/bin/security", args, timeout: nil) else { return (-1, "") }
        return (r.status, String(decoding: r.out, as: UTF8.self))
    }
}
