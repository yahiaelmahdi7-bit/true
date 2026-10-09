import Foundation

/// Typed mirrors of the JSON True's phone server returns. Keys match the server exactly; fields the Mac
/// omits (or the mock omits) are optional or default to zero so a missing key never fails a whole poll.

// MARK: Hub (GET /api/hub)

public struct HubSnapshot: Codable, Equatable, Sendable {
    public var now: Double?
    public var working: Int
    public var needsYou: Int
    public var failed: Int
    public var summary: String
    public var projects: [HubProject]

    public init(now: Double? = nil, working: Int = 0, needsYou: Int = 0, failed: Int = 0, summary: String = "", projects: [HubProject] = []) {
        self.now = now; self.working = working; self.needsYou = needsYou; self.failed = failed
        self.summary = summary; self.projects = projects
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        now = try c.decodeIfPresent(Double.self, forKey: .now)
        working = try c.decodeIfPresent(Int.self, forKey: .working) ?? 0
        needsYou = try c.decodeIfPresent(Int.self, forKey: .needsYou) ?? 0
        failed = try c.decodeIfPresent(Int.self, forKey: .failed) ?? 0
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        projects = try c.decodeIfPresent([HubProject].self, forKey: .projects) ?? []
    }

    /// Ids of every row whose status is "needs you" (the unit the phone notifies on).
    public var needsYouIDs: Set<String> {
        Set(projects.flatMap(\.rows).filter { $0.statusKey == "needsYou" }.map(\.id))
    }
}

public struct HubProject: Codable, Equatable, Sendable {
    public var key: String?
    public var title: String
    public var summary: String
    public var working: Int
    public var needsYou: Int
    public var failed: Int
    public var rows: [HubRow]

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        working = try c.decodeIfPresent(Int.self, forKey: .working) ?? 0
        needsYou = try c.decodeIfPresent(Int.self, forKey: .needsYou) ?? 0
        failed = try c.decodeIfPresent(Int.self, forKey: .failed) ?? 0
        rows = try c.decodeIfPresent([HubRow].self, forKey: .rows) ?? []
    }
}

/// `kind` is "seat" | "background" | "other"; `statusKey` is the AgentStatus raw value
/// ("working", "needsYou", "idle", "done", "failed", "asleep"...). Kept as strings so a new Mac value never breaks decoding.
public struct HubRow: Codable, Equatable, Sendable, Identifiable {
    public var kind: String
    public var id: String
    public var name: String
    public var status: String
    public var statusKey: String
    public var model: String?
    public var pane: String?
    public var cwd: String?
    public var elapsed: String?
    public var builderId: String?
    public var acked: Bool?
    public var branch: String?
    public var updated: Double?
}

public struct BuilderDetail: Codable, Equatable, Sendable {
    public var id: String?
    public var name: String
    public var status: String
    public var acked: Bool
    public var canAck: Bool
    public var text: String
}

// MARK: Inbox, shots, clip

public struct InboxResponse: Codable, Equatable, Sendable { public var items: [InboxItem] }

/// `kind` is "text" or "file"; `preview` only exists for text items.
public struct InboxItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var size: Int
    public var created: Double?
    public var preview: String?
}

public struct ShotsResponse: Codable, Equatable, Sendable { public var shots: [Shot] }

/// `created` is ISO-8601; `w`/`h` are pixel sizes.
public struct Shot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var created: String
    public var kind: String
    public var w: Int
    public var h: Int
}

public struct DropResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var `where`: String?
    public var id: String?
    public var name: String?
}

// MARK: Command bar (route / slot / run / recent)

public struct RecentResponse: Codable, Equatable, Sendable { public var items: [String] }

public struct RouteOption: Codable, Equatable, Sendable { public var value: String; public var label: String }

public struct RouteInfo: Codable, Equatable, Sendable {
    public var text: String
    public var kind: String
    public var kindLabel: String
    public var project: String?
    public var target: String
    public var whereLabel: String
    public var model: String?
    public var effort: String?
    public var uncertain: [String]
    public var twoChoice: Bool
    public var dangerous: Bool
    public var typedOnly: Bool
    public var runnable: Bool

    enum CodingKeys: String, CodingKey {
        case text, kind, kindLabel, project, target, model, effort, uncertain, twoChoice, dangerous, typedOnly, runnable
        case whereLabel = "where"
    }
}

/// POST /api/route and POST /api/route/{id}/slot. The slot reply carries the same shape.
public struct RouteResponse: Codable, Equatable, Sendable {
    public var routeId: String?
    public var route: RouteInfo
    public var alternatives: [String]
    /// slot name ("kind", "project", "target", "model", "effort") -> the values the Mac will accept for it.
    public var candidates: [String: [RouteOption]]

    public var uncertain: [String] { route.uncertain }
    public var dangerous: Bool { route.dangerous }
    public var runnable: Bool { route.runnable }
    public var twoChoice: Bool { route.twoChoice }
}

/// POST /api/run. 200 -> `ok` with `pane` (a pane UUID) or `background` (a builder name).
/// 409 is NOT an error: `needsConfirm == true` with a `reason`; resend with confirmed: true.
public struct RunResponse: Codable, Equatable, Sendable {
    public var ok: Bool?
    public var pane: String?
    public var background: String?
    public var needsConfirm: Bool?
    public var reason: String?
}

// MARK: Tabs (GET /api/tabs)

public struct TabsResponse: Codable, Equatable, Sendable {
    public var tabs: [RemoteTab]
    public var now: Double?
}

public struct RemoteTab: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var selected: Bool
    public var panes: [RemotePane]
}

public struct RemotePane: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var cwd: String
    public var agent: String?
    public var needsYou: Bool
    public var busy: Bool
    public var live: Bool
}

struct PairResponse: Codable { var token: String?; var error: String? }
