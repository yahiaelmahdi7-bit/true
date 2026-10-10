import Foundation

/// ONE path guard (read_file, find_files results, every path argument of an allowlisted shell command): resolve
/// symlinks, compare case-insensitively against the protected set, refuse on any doubt.
enum NovaPaths {
    /// Protected locations under the home directory (lowercased compare).
    static let homeSecrets = [".ssh", ".true", ".aws", ".config/gh", ".config/gcloud", ".netrc", ".npmrc", ".docker", ".kube",
                              ".gnupg", ".azure", ".zsh_history", ".zhistory", ".bash_history", ".git-credentials", ".pgpass",
                              "library/keychains"]

    static func roots(home: String) -> [String] {
        var homes = [home]
        if let r = real(home) { homes.append(r) }
        return Set(homes.flatMap { h in homeSecrets.map { (h + "/" + $0).lowercased() } }).sorted()
    }
    private static func real(_ p: String) -> String? {
        guard let c = realpath(p, nil) else { return nil }
        defer { free(c) }
        return String(cString: c)
    }
    /// Symlink-resolved absolute path. A path that doesn't exist yet resolves its deepest existing ancestor and keeps
    /// the (lexically cleaned) tail. nil = couldn't resolve at all = doubt.
    static func canonical(_ path: String, base: String) -> String? {
        let p = (path as NSString).expandingTildeInPath
        let abs = p.hasPrefix("/") ? p : (base as NSString).appendingPathComponent(p)
        var cur = URL(fileURLWithPath: abs).standardizedFileURL.path
        var tail: [String] = []
        while true {
            if let r = real(cur) { return tail.isEmpty ? r : (r == "/" ? "" : r) + "/" + tail.reversed().joined(separator: "/") }
            if cur == "/" || cur.isEmpty { return nil }
            tail.append((cur as NSString).lastPathComponent); cur = (cur as NSString).deletingLastPathComponent
        }
    }
    static func isSecret(_ canon: String, home: String = NSHomeDirectory()) -> Bool {
        let l = canon.lowercased()
        for r in roots(home: home) where l == r || l.hasPrefix(r + "/") { return true }
        if l.contains("/library/keychains") { return true }
        let name = (l as NSString).lastPathComponent
        return name == ".env" || name.hasPrefix(".env.") || [".pem", ".key", ".p12", ".pfx"].contains { name.hasSuffix($0) }
            || name.hasPrefix("id_rsa") || name.hasPrefix("id_ed25519") || name.hasPrefix("id_ecdsa")
    }
    /// True when `canon` is a directory that CONTAINS a protected location (a recursive tool pointed there would read it).
    static func containsSecret(_ canon: String, home: String = NSHomeDirectory()) -> Bool {
        let l = canon.lowercased() == "/" ? "" : canon.lowercased()
        return roots(home: home).contains { $0.hasPrefix(l + "/") }
    }
    static func check(_ rawPath: String, base: String = NSHomeDirectory(), home: String = NSHomeDirectory()) -> GateVerdict {
        let path = rawPath == "~" ? home : (rawPath.hasPrefix("~/") ? home + String(rawPath.dropFirst()) : rawPath)   // ~ means THIS home
        guard let c = canonical(path, base: base) else { return .refuse("can't resolve that path") }
        if isSecret(c, home: home) || isSecret(URL(fileURLWithPath: ((path as NSString).expandingTildeInPath as NSString).standardizingPath).path, home: home) {
            return .refuse("that file holds secrets")
        }
        return .allow
    }
    /// Open first, ask the kernel where the descriptor really is (F_GETPATH), check THAT, read from the same fd.
    static func openChecked(_ path: String, home: String = NSHomeDirectory()) -> (fd: Int32?, verdict: GateVerdict) {
        if case .refuse(let w) = check(path, home: home) { return (nil, .refuse(w)) }
        let fd = open((path as NSString).expandingTildeInPath, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { return (nil, .refuse("can't open that file")) }
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &buf) == 0 else { close(fd); return (nil, .refuse("can't resolve that path")) }
        if isSecret(String(cString: buf), home: home) { close(fd); return (nil, .refuse("that file holds secrets")) }
        return (fd, .allow)
    }
}

/// The free (unparked) shell path: tokenise ourselves, check every token, and exec the binary directly from a fixed
/// table. Anything not provably read-only parks. Nothing here ever reaches a shell.
enum NovaShell {
    enum Plan: Equatable {
        case run(exe: String, args: [String], cwd: String)
        case park(String)
        case refuse(String)
    }
    struct Spec { var exe: String; var short: Set<Character> = []; var long: Set<String> = []; var digits = false
                  var paths = true; var recursive = false; var maxPositional = 99 }

    static let forbidden = CharacterSet(charactersIn: ";&|<>`$()=*?[]{}~!'\"\\#\n\r\t%^")
    static let table: [String: Spec] = [
        "ls": Spec(exe: "/bin/ls", short: Set("alhtrSF1dG")), "cat": Spec(exe: "/bin/cat", short: Set("nbs")),
        "head": Spec(exe: "/usr/bin/head", short: Set("nc"), digits: true), "tail": Spec(exe: "/usr/bin/tail", short: Set("nc"), digits: true),
        "grep": Spec(exe: "/usr/bin/grep", short: Set("inlcvwFEhsoq")), "rg": Spec(exe: "/opt/homebrew/bin/rg", short: Set("inlcvwFs"), recursive: true),
        "wc": Spec(exe: "/usr/bin/wc", short: Set("lwcm")), "du": Spec(exe: "/usr/bin/du", short: Set("shkcd"), digits: true, recursive: true),
        "df": Spec(exe: "/bin/df", short: Set("hk"), paths: false), "file": Spec(exe: "/usr/bin/file", short: Set("b")),
        "stat": Spec(exe: "/usr/bin/stat"), "sort": Spec(exe: "/usr/bin/sort", short: Set("nrufbd")),
        "uniq": Spec(exe: "/usr/bin/uniq", short: Set("cdui"), maxPositional: 1), "tree": Spec(exe: "/opt/homebrew/bin/tree", short: Set("adfL"), digits: true, recursive: true),
        "pwd": Spec(exe: "/bin/pwd", paths: false, maxPositional: 0), "which": Spec(exe: "/usr/bin/which", paths: false),
        "echo": Spec(exe: "/bin/echo", short: Set("n"), paths: false), "date": Spec(exe: "/bin/date", paths: false, maxPositional: 0),
        "whoami": Spec(exe: "/usr/bin/whoami", paths: false, maxPositional: 0), "uname": Spec(exe: "/usr/bin/uname", short: Set("a"), paths: false, maxPositional: 0),
        "ps": Spec(exe: "/bin/ps", paths: false, maxPositional: 1),
    ]
    static let findOptions: Set<String> = ["-name", "-iname", "-type", "-maxdepth", "-mindepth"]
    static let gitSubs: Set<String> = ["status", "log", "diff", "branch", "show"]
    static let gitLong: Set<String> = ["--oneline", "--stat", "--short", "--porcelain", "--name-only", "--name-status", "--staged",
                                       "--cached", "--graph", "--decorate", "--no-color", "--list", "--show-current", "--shortstat",
                                       "--abbrev-commit", "--"]
    static let env = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8", "GIT_OPTIONAL_LOCKS": "0", "GIT_CONFIG_NOSYSTEM": "1"]

    static func plan(_ command: String, cwd: String = "", home: String = NSHomeDirectory(), exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> Plan {
        let c = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let park = Plan.park("run: " + c)
        guard !c.isEmpty else { return .refuse("empty command") }
        if c.unicodeScalars.contains(where: forbidden.contains) { return park }
        let words = c.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let cmd = words.first else { return park }
        let dir = cwd.isEmpty ? home : (cwd as NSString).expandingTildeInPath
        guard let dirReal = NovaPaths.canonical(dir, base: home) else { return .refuse("can't resolve the folder") }
        if NovaPaths.isSecret(dirReal, home: home) { return .refuse("that folder holds secrets") }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirReal, isDirectory: &isDir), isDir.boolValue else { return park }
        var rest = Array(words.dropFirst())
        var spec: Spec
        var prefix: [String] = []
        if cmd == "git" {
            guard let sub = rest.first, gitSubs.contains(sub), exists("/usr/bin/git") else { return park }
            rest.removeFirst()
            spec = Spec(exe: "/usr/bin/git", short: Set("nsbpavr"), long: gitLong, digits: true, maxPositional: sub == "branch" ? 0 : 99)
            prefix = ["--no-pager", "-c", "core.fsmonitor=", "-c", "core.pager=cat", "-c", "core.hooksPath=/dev/null", sub]
            if sub != "branch" && sub != "status" { prefix += ["--no-ext-diff", "--no-textconv"] }
        } else if cmd == "find" {
            spec = Spec(exe: "/usr/bin/find", recursive: true)
        } else if let s = table[cmd] { spec = s } else { return park }
        guard exists(spec.exe) else { return park }
        var positional: [String] = []
        for t in rest {
            if cmd == "find", t.hasPrefix("-") { guard findOptions.contains(t) else { return park }; continue }
            if t.hasPrefix("--") { guard spec.long.contains(t) else { return park }; continue }
            if t.hasPrefix("-"), t.count > 1 {
                let body = t.dropFirst()
                guard body.allSatisfy({ spec.short.contains($0) }) || (spec.digits && body.allSatisfy(\.isNumber)) else { return park }
                continue
            }
            positional.append(t)
        }
        if cmd == "ps", let p = positional.first, !["aux", "ax"].contains(p) { return park }
        if cmd == "find", positional.contains(where: { $0.hasPrefix("-") }) { return park }
        guard positional.count <= spec.maxPositional else { return park }
        if spec.paths {
            for p in positional {
                switch NovaPaths.check(p, base: dirReal, home: home) {
                case .refuse(let w): return .refuse(w)
                default: break
                }
                if spec.recursive, let cp = NovaPaths.canonical(p, base: dirReal), NovaPaths.containsSecret(cp, home: home) { return park }
            }
            let searchesCwd = cmd == "rg" ? positional.count <= 1 : positional.isEmpty
            if spec.recursive, searchesCwd, NovaPaths.containsSecret(dirReal, home: home) { return park }
        }
        return .run(exe: spec.exe, args: prefix + rest, cwd: dirReal)
    }
}
