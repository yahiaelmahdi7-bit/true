import Foundation

/// The Hub's All view as a triage list (pure, no IO): what needs you first, what is working, what is done and
/// waiting for a look, and everything older. Built from the same models the old view used.

enum TriageSection: Int, CaseIterable, Identifiable {
    case needsYou, working, review, history
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .needsYou: return "Needs you"
        case .working: return "Working"
        case .review: return "Done, to review"
        case .history: return "History"
        }
    }
    var emptyText: String {
        switch self {
        case .needsYou: return "Nothing is waiting on you."
        case .working: return "Nothing is running."
        case .review: return "Nothing to review."
        case .history: return "Nothing older."
        }
    }
}

/// How a row looks: failed red, needs-you amber, working animated, done neutral.
enum TriageTone: Int {
    case needsYou, failed, working, done, idle
}

enum TriageAction: Equatable {
    case builder(String), cloud(String), watcher(String), seat(String), peer(Int32), pane(UUID)
}

struct TriageItem: Identifiable, Equatable {
    var id: String
    var section: TriageSection
    var tone: TriageTone
    var title: String
    var subtitle: String
    /// Project folder name, shown as a chip.
    var project: String
    /// Seconds since 1970 the row's clock runs from (start while working, end once finished).
    var at: Double
    var isCloud = false
    /// The one button on the row; empty = none.
    var actionLabel: String
    var action: TriageAction
    /// Noun for a group of these ("builders", "cloud jobs"); the verb comes from the tone.
    var noun = "items"
}

/// One visible entry: a row, or a run of same-project rows folded into one.
enum TriageEntry: Identifiable, Equatable {
    case row(TriageItem)
    case group(id: String, project: String, tone: TriageTone, label: String, items: [TriageItem])

    var id: String {
        switch self {
        case .row(let i): return i.id
        case .group(let id, _, _, _, _): return id
        }
    }
}

struct TriageBucket: Identifiable, Equatable {
    var section: TriageSection
    var entries: [TriageEntry]
    var count: Int
    var id: Int { section.rawValue }
}

enum HubTriage {
    /// A run shorter than this stays as separate rows.
    static let groupMin = 3

    /// Everything on screen, in the four sections (always all four, so empty states can show).
    @MainActor
    static func build(groups: [HubProjectGroup], seatStatus: (String) -> AgentStatus, cloud: [CloudJob],
                      watcher: [InboxItem], yourMove: [YourMoveRow] = [], now: Double) -> [TriageBucket] {
        var items: [TriageItem] = []
        for g in groups {
            for a in g.seats {
                let s = seatStatus(a.name)
                guard s == .needsYou || s == .working || s == .idle || s == .done else { continue }   // asleep seats live on the Agents tab
                let sec: TriageSection = s == .needsYou ? .needsYou : s == .working ? .working : .history
                items.append(TriageItem(id: "seat:\(a.name)", section: sec,
                                        tone: s == .needsYou ? .needsYou : s == .working ? .working : .idle,
                                        title: a.name, subtitle: "Agent · \(s.label)", project: g.title, at: now,
                                        actionLabel: "Open", action: .seat(a.name), noun: "agents"))
            }
            for b in g.background { items.append(item(b, project: g.title, now: now)) }
            for p in g.others {
                items.append(TriageItem(id: "peer:\(p.pid)", section: p.busy ? .working : .history,
                                        tone: p.busy ? .working : .idle, title: p.displayName,
                                        subtitle: "Claude session · \(hubKindLabel(p.kind))", project: g.title,
                                        at: p.updatedAt, actionLabel: "Reveal", action: .peer(p.pid), noun: "sessions"))
            }
        }
        for j in cloud where j.archived != true { items.append(item(j, now: now)) }
        for w in watcher {
            items.append(TriageItem(id: "watch:\(w.id)", section: .needsYou, tone: .needsYou, title: w.title,
                                    subtitle: w.level.map { $0.label } ?? "Watcher",
                                    project: (w.repo as NSString).lastPathComponent, at: w.at,
                                    actionLabel: "Open", action: .watcher(w.id), noun: "items"))
        }
        for r in yourMove {
            // The Overseer's verdict on a pane: stuck or asking is yours now; "says done, unchecked" is a review.
            let urgent = r.kind == .blocked || r.kind == .asksYou || r.kind == .asksToContinue
            items.append(TriageItem(id: "pane:\(r.pane.uuidString)", section: urgent ? .needsYou : .review,
                                    tone: r.kind == .blocked ? .failed : .needsYou, title: r.name,
                                    subtitle: "\(r.kind.label) · \(r.reason)", project: r.project, at: r.at.timeIntervalSince1970,
                                    actionLabel: "Open", action: .pane(r.pane), noun: "panes"))
        }
        return TriageSection.allCases.map { sec in
            let mine = sorted(items.filter { $0.section == sec })
            return TriageBucket(section: sec, entries: fold(mine), count: mine.count)
        }
    }

    static func item(_ b: BuilderRecord, project: String, now: Double) -> TriageItem {
        let ran = hubElapsed(b.elapsed(now: now))
        let model = b.model.isEmpty ? "" : b.model.capitalized + " · "
        let at = b.state == .running ? b.started : (b.ended ?? b.started)
        func make(_ sec: TriageSection, _ tone: TriageTone, _ sub: String, _ label: String) -> TriageItem {
            TriageItem(id: "builder:\(b.id)", section: sec, tone: tone, title: b.name, subtitle: sub, project: project,
                       at: at, actionLabel: label, action: .builder(b.id), noun: "builders")
        }
        switch b.state {
        case .running: return make(.working, .working, "\(model)running \(ran)", "Open")
        case .paused: return make(.needsYou, .needsYou, "\(model)paused, waiting for a go-ahead", "Open")
        case .done: return make(b.acked ? .history : .review, .done, "\(model)finished in \(ran)", b.acked ? "Open" : "Review gates")
        case .failed, .killed, .died:
            let word = b.state == .failed ? "failed" : b.state == .killed ? "stopped" : "died"
            return make(b.acked ? .history : .needsYou, .failed, "\(model)\(word) after \(ran)", "Open")
        }
    }

    static func item(_ j: CloudJob, now: Double) -> TriageItem {
        let repo = (j.repo as NSString).lastPathComponent
        let unviewed = j.unviewed == true
        func make(_ sec: TriageSection, _ tone: TriageTone, _ sub: String, _ label: String, _ at: Double) -> TriageItem {
            TriageItem(id: "cloud:\(j.id)", section: sec, tone: tone, title: j.title, subtitle: sub, project: repo, at: at,
                       isCloud: true, actionLabel: label, action: .cloud(j.id), noun: "cloud jobs")
        }
        if j.needsYou { return make(.needsYou, .needsYou, j.needsYouReason ?? "Needs an answer to continue", "Answer", j.updatedAt) }
        if j.isWorking {
            return make(.working, .working, j.foremanStatus == "QUEUED" ? "Queued" : "Running \(hubElapsed(now - j.createdAt))", "Open", j.createdAt)
        }
        if j.isFailed { return make(unviewed ? .needsYou : .history, .failed, j.reason ?? "Failed", "Open", j.updatedAt) }
        return make(unviewed ? .review : .history, .done, "Finished", unviewed ? "Review" : "Open", j.updatedAt)
    }

    /// Loud tones first, then project clusters (newest project first), newest row first inside a cluster. Clustering
    /// is what lets consecutive rows of one project fold.
    static func sorted(_ items: [TriageItem]) -> [TriageItem] {
        var newest: [String: Double] = [:]
        for i in items { newest[i.project] = max(newest[i.project] ?? 0, i.at) }
        return items.sorted { a, b in
            if a.tone.rawValue != b.tone.rawValue { return a.tone.rawValue < b.tone.rawValue }
            if a.project != b.project {
                let (na, nb) = (newest[a.project] ?? 0, newest[b.project] ?? 0)
                return na != nb ? na > nb : a.project.lowercased() < b.project.lowercased()
            }
            return a.at != b.at ? a.at > b.at : a.id < b.id
        }
    }

    /// Runs of ≥ `groupMin` consecutive rows sharing project + tone + kind become one group.
    static func fold(_ items: [TriageItem]) -> [TriageEntry] {
        var out: [TriageEntry] = []
        var i = 0
        while i < items.count {
            var j = i + 1
            while j < items.count, items[j].project == items[i].project, items[j].tone == items[i].tone,
                  items[j].noun == items[i].noun, items[j].isCloud == items[i].isCloud { j += 1 }
            let run = Array(items[i..<j])
            if run.count >= groupMin {
                out.append(.group(id: "group:\(run[0].id)", project: run[0].project, tone: run[0].tone,
                                  label: groupLabel(run), items: run))
            } else {
                out.append(contentsOf: run.map { .row($0) })
            }
            i = j
        }
        return out
    }

    /// "6 builders finished" / "4 builders failed" / "3 builders working".
    static func groupLabel(_ run: [TriageItem]) -> String {
        let verb: String
        switch run[0].tone {
        case .failed: verb = "failed"
        case .working: verb = "working"
        case .needsYou: verb = "need you"
        case .done: verb = "finished"
        case .idle: verb = "idle"
        }
        return "\(run.count) \(run[0].noun) \(verb)"
    }

    // MARK: header counts + keyboard order

    static func count(_ buckets: [TriageBucket], tone: TriageTone) -> Int {
        buckets.reduce(0) { total, b in
            total + b.entries.reduce(0) { sub, e in
                switch e {
                case .row(let i): return sub + (i.tone == tone ? 1 : 0)
                case .group(_, _, let t, _, let items): return sub + (t == tone ? items.count : 0)
                }
            }
        }
    }

    /// First row id with this tone (what clicking "4 failed" jumps to).
    static func firstID(_ buckets: [TriageBucket], tone: TriageTone) -> String? {
        for b in buckets {
            for e in b.entries {
                switch e {
                case .row(let i) where i.tone == tone: return i.id
                case .group(let id, _, let t, _, _) where t == tone: return id
                default: break
                }
            }
        }
        return nil
    }

    /// Ids in the order ↑↓ walks them: every entry, plus a group's children while it is expanded; History's rows
    /// only while History is open.
    static func visibleIDs(_ buckets: [TriageBucket], expanded: Set<String>, historyOpen: Bool) -> [String] {
        var out: [String] = []
        for b in buckets where b.section != .history || historyOpen {
            for e in b.entries {
                out.append(e.id)
                if case .group(let id, _, _, _, let items) = e, expanded.contains(id) { out.append(contentsOf: items.map(\.id)) }
            }
        }
        return out
    }

    /// The next id after `current` moving `delta` rows, clamped; nothing selected → the first (↓) or last (↑).
    static func move(_ ids: [String], from current: String?, by delta: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let at = ids.firstIndex(of: current) else { return delta >= 0 ? ids.first : ids.last }
        return ids[min(max(at + delta, 0), ids.count - 1)]
    }

    static func entry(_ buckets: [TriageBucket], id: String) -> (item: TriageItem?, groupID: String?)? {
        for b in buckets {
            for e in b.entries {
                switch e {
                case .row(let i) where i.id == id: return (i, nil)
                case .group(let gid, _, _, _, let items):
                    if gid == id { return (nil, gid) }
                    if let i = items.first(where: { $0.id == id }) { return (i, nil) }
                default: break
                }
            }
        }
        return nil
    }
}

/// Header status pill for the cloud factory.
enum CloudLink: Equatable {
    case connected, offline, checking
    static func of(error: String?, loaded: Bool) -> CloudLink { !loaded ? .checking : error == nil ? .connected : .offline }
    var label: String {
        switch self {
        case .connected: return "Cloud · connected"
        case .offline: return "Cloud · offline — retry"
        case .checking: return "Cloud · checking"
        }
    }
}
