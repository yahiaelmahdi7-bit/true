import Foundation

/// The control socket (`~/.true/control.sock`): how an agent, from inside its own pane, asks True to
/// do something — today, to *summon* another agent. Request/response, one JSON line each way:
/// `{"op":"status"}` / `{"op":"summon","agent":"…","message":"…","from":"…"}`. The client is the
/// `truectl` script (`AgentControl.truectl`), which tags `from` with `$TRUE_AGENT`.
enum ControlRequest: Equatable, Sendable {
    case status
    case summon(agent: String, message: String, from: String?)

    /// Anything malformed returns nil — the socket is a doorbell, never a crash surface.
    static func parse(_ line: Data) -> ControlRequest? {
        struct Wire: Decodable { let op: String; let agent: String?; let message: String?; let from: String? }
        guard let w = try? JSONDecoder().decode(Wire.self, from: line) else { return nil }
        switch w.op {
        case "status":
            return .status
        case "summon":
            guard let agent = w.agent, let message = w.message else { return nil }
            return .summon(agent: agent, message: message, from: w.from)
        default:
            return nil
        }
    }
}

struct ControlResponse: Encodable, Equatable, Sendable {
    struct Row: Encodable, Equatable, Sendable {
        let name: String, role: String, repo: String, status: String, awake: Bool
    }
    var ok: Bool
    var error: String?
    var outcome: String?
    var agents: [Row]?

    static func failure(_ message: String) -> ControlResponse { ControlResponse(ok: false, error: message) }

    /// One line, trailing newline — the wire format `truectl` reads.
    func encoded() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(self)).map { $0 + Data("\n".utf8) } ?? Data("{\"ok\":false}\n".utf8)
    }
}

enum AgentControl {
    /// Who may summon whom. A human (no caller, or a name that is no agent) may reach anyone; a
    /// global reaches only the LEADS on its team, a lead only the HELPERS on its team, a helper no one.
    /// Enforced here, not in the role card: a card is advice, this is the door.
    static func mayReach(caller: String?, target: Agent, agents: [Agent]) -> Bool {
        guard let caller, let c = agents.first(where: { $0.name == caller }) else { return true }
        switch c.role {
        case .global: return target.role == .lead && c.team.contains(target.name)
        case .lead: return target.role == .helper && c.team.contains(target.name)
        case .helper: return false
        }
    }

    /// What lands in the target's pane. A summoned agent is told who to answer, since the brief is
    /// its only context for that.
    static func deliveredText(message: String, from: String?) -> String {
        guard let from, !from.isEmpty else { return message }
        return message + "\n\n(Summoned by `\(from)`. When you finish or get blocked, reply to `\(from)` with the SendMessage tool — a one-line summary, what changed, the verification output.)"
    }

    /// How long a summon may wait for a sleeping agent to boot. `talk` gives up on its own after 60 s
    /// of no SessionStart; this is the backstop for a callback that never comes at all.
    static let summonTimeout: Duration = .seconds(90)

    /// Replies exactly once, whichever of `talk`'s callback and the timeout comes first.
    @MainActor private final class Once {
        private var done = false
        func run(_ body: () -> Void) { guard !done else { return }; done = true; body() }
    }

    @MainActor
    static func handle(_ req: ControlRequest, registry: AgentRegistry,
                       reply: @escaping @Sendable (ControlResponse) -> Void) {
        switch req {
        case .status:
            let rows = registry.agents.map {
                ControlResponse.Row(name: $0.name, role: $0.role.rawValue, repo: $0.repoName,
                                    status: registry.statusOf($0.name).rawValue, awake: registry.isAwake($0.name))
            }
            reply(ControlResponse(ok: true, agents: rows))
        case .summon(let agent, let message, let from):
            guard let target = registry.agent(named: agent) else { return reply(.failure("no agent named \(agent)")) }
            let caller = from.flatMap { registry.agent(named: $0) }?.name
            guard mayReach(caller: caller, target: target, agents: registry.agents) else {
                return reply(.failure("\(caller ?? "") may not summon \(target.name) (globals summon their leads, leads summon their helpers)"))
            }
            // `talk` ignores an empty body without calling back, which would read as a 90 s hang.
            guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return reply(.failure("empty message"))
            }
            let once = Once()
            registry.talk(target.name, deliveredText(message: message, from: caller)) { outcome in
                Task { @MainActor in
                    once.run { reply(ControlResponse(ok: true, outcome: String(describing: outcome))) }
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: summonTimeout)
                once.run { reply(.failure("timed out waiting for \(target.name) to boot")) }
            }
        }
    }

    /// The client agents run. Prints nothing on stdout but its result; errors go to stderr.
    /// `TRUE_CONTROL_SOCK` overrides the baked-in socket (used by tests).
    static func truectl(socketPath: String) -> String {
        #"""
        #!/usr/bin/env python3
        # truectl — the command-line door to the running True app (control socket).
        #   truectl status                        one line per agent: name  role  status  awake|asleep  repo
        #   truectl summon <agent> <message...>   wake <agent> if asleep and deliver the brief ("-" = read stdin)
        # Sends one JSON line, waits for one reply line. stdout carries only the result; errors go to
        # stderr. Exit 0 ok, 1 refused/failed, 2 True is not running.
        import json, os, socket, sys

        DEFAULT_SOCK = __SOCKET__
        USAGE = "usage: truectl status | truectl summon <agent> <message words... | ->"

        def die(msg, code=1):
            sys.stderr.write(msg + "\n")
            sys.exit(code)

        def call(wire):
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(100)
            try:
                s.connect(os.environ.get("TRUE_CONTROL_SOCK") or DEFAULT_SOCK)
            except (FileNotFoundError, ConnectionRefusedError):
                die("True is not running", 2)
            except OSError as e:
                die("cannot reach True: %s" % e, 2)
            buf = b""
            try:
                s.sendall((json.dumps(wire) + "\n").encode())
                while b"\n" not in buf:
                    chunk = s.recv(65536)
                    if not chunk:
                        break
                    buf += chunk
            except socket.timeout:
                die("timed out waiting for True")
            finally:
                s.close()
            try:
                return json.loads(buf.split(b"\n")[0].decode())
            except ValueError:
                die("True sent no usable reply")

        def main(argv):
            if argv[:1] == ["status"] and len(argv) == 1:
                r = call({"op": "status"})
                if not r.get("ok"):
                    die(r.get("error") or "failed")
                for a in r.get("agents") or []:
                    print("%s  %s  %s  %s  %s" % (a["name"], a["role"], a["status"],
                                                  "awake" if a["awake"] else "asleep", a["repo"]))
            elif argv[:1] == ["summon"] and len(argv) >= 3:
                agent = argv[1]
                message = sys.stdin.read() if argv[2:] == ["-"] else " ".join(argv[2:])
                r = call({"op": "summon", "agent": agent, "message": message,
                          "from": os.environ.get("TRUE_AGENT")})
                if not r.get("ok"):
                    die(r.get("error") or "failed")
                print("summoned %s (%s)" % (agent, r.get("outcome") or "unknown"))
            else:
                die(USAGE)

        main(sys.argv[1:])
        """#
        .replacingOccurrences(of: "__SOCKET__", with: AgentHooks.pythonString(socketPath))
    }
}

/// `LineSocketServer` + `ControlRequest`. Started once at launch, like the events socket.
final class AgentControlSocket: @unchecked Sendable {
    private let server: LineSocketServer

    init(path: String, registry: AgentRegistry) {
        server = LineSocketServer(path: path) { line, reply in
            guard let req = ControlRequest.parse(line) else {
                return reply(ControlResponse.failure("bad request").encoded())
            }
            Task { @MainActor in
                AgentControl.handle(req, registry: registry) { reply($0.encoded()) }
            }
        }
    }

    @discardableResult
    func start() -> Bool { server.start() }
    func stop() { server.stop() }
}
