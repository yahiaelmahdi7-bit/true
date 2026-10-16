import Foundation
import Security

/// Bearer token in the Keychain, shared with the share extension through the app group.
/// `AfterFirstUnlockThisDeviceOnly`: readable by the background refresh while the phone is locked, never synced or backed up.
final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let service = "net.prismlens.true.token"
    private let account = "bearer"
    private let accessGroup: String?
    /// Unsigned simulator builds have no Keychain entitlement (-34018), so keep the token in memory there.
    nonisolated(unsafe) private static var memory: String?

    /// `accessGroup` is nil when the build is unsigned (simulator without a team): the app group entitlement is then absent.
    init() { accessGroup = Self.resolveGroup() }

    private static func resolveGroup() -> String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String else { return nil }
        return prefix + SharedConfig.group
    }

    private func query(grouped: Bool) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if grouped, let g = accessGroup { q[kSecAttrAccessGroup as String] = g }
        return q
    }

    func load() -> String? {
        for grouped in [true, false] {
            var q = query(grouped: grouped)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data { return String(data: d, encoding: .utf8) }
        }
        #if DEBUG
        return Self.memory
        #else
        return nil
        #endif
    }

    func save(_ token: String) {
        clear()
        #if DEBUG
        Self.memory = token
        #endif
        for grouped in [true, false] {
            var q = query(grouped: grouped)
            q[kSecValueData as String] = Data(token.utf8)
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            if SecItemAdd(q as CFDictionary, nil) == errSecSuccess { return }
        }
    }

    func clear() {
        #if DEBUG
        Self.memory = nil
        #endif
        for grouped in [true, false] { SecItemDelete(query(grouped: grouped) as CFDictionary) }
    }
}
