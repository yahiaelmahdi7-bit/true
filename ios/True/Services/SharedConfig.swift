import Foundation

/// Values the app and the share extension both need: where the Mac is. The token itself lives in the Keychain.
enum SharedConfig {
    static let group = "group.net.prismlens.true"
    private static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static var baseURL: URL? {
        get { defaults.string(forKey: "baseURL").flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: "baseURL") }
    }

    /// "mac.tailnet.ts.net:8444" -> https://mac.tailnet.ts.net:8444. An explicit http:// is kept (localhost mock, Debug only).
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard var c = URLComponents(string: s), c.host?.isEmpty == false else { return nil }
        c.path = ""; c.query = nil; c.fragment = nil
        return c.url
    }

    static var notifiedIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "notifiedIDs") ?? []) }
        set { defaults.set(Array(newValue), forKey: "notifiedIDs") }
    }
}
