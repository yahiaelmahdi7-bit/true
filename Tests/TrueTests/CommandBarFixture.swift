import Foundation
@testable import True

/// Decodes the FIXED hand-labelled routes (Fixtures/commandbar-labelled.json). Never edited by tests.
struct CommandBarFixture: Decodable {
    struct P: Decodable { var name: String; var path: String }
    struct S: Decodable { var name: String; var project: String; var awake: Bool }
    struct F: Decodable { var kind: String; var project: String?; var seat: String? }
    struct E: Decodable { var kind: String?; var project: String?; var target: String?; var action: String?; var destructive: Bool? }
    struct Case: Decodable { var id: String; var text: String; var focused: F; var expect: E; var ambiguous: Bool? }
    var projects: [P]
    var seats: [S]
    var cases: [Case]

    static var defaultURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/commandbar-labelled.json")
    }

    /// The live suite's input: an absolute path in env COMMANDBAR_FIXTURE when set, else the default fixture.
    static func liveURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        guard let p = env["COMMANDBAR_FIXTURE"], p.hasPrefix("/") else { return defaultURL }
        return URL(fileURLWithPath: p)
    }

    static func load(from url: URL? = nil) throws -> CommandBarFixture {
        let url = url ?? defaultURL
        return try JSONDecoder().decode(CommandBarFixture.self, from: Data(contentsOf: url))
    }

    var projectList: [Project] {
        projects.map { Project(name: $0.name, path: $0.path, parent: URL(fileURLWithPath: $0.path).deletingLastPathComponent().path) }
    }
    var barSeats: [BarSeat] { seats.map { BarSeat(name: $0.name, project: $0.project, awake: $0.awake) } }
    func pane(_ c: Case) -> FocusedPane {
        FocusedPane(kind: PaneKind(rawValue: c.focused.kind) ?? .empty, project: c.focused.project, seat: c.focused.seat)
    }
}
