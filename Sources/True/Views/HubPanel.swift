import SwiftUI
import AppKit

/// The ⌘E panel: every Claude session on this Mac, grouped by project (SPEC Run 7). Store-bound shell;
/// the drawing lives in `HubPanelContent` so snapshot tests can render it from fixtures.
struct HubPanel: View {
    let registry: AgentRegistry
    @State private var hub = HubStore.shared
    @State private var detail: BuilderRecord?
    @State private var crew = CrewStore.shared
    @State private var crewNotice: String?

    private struct CrewTrigger: Hashable { var active: Bool; var cwd: String }

    private var focusedCwd: String {
        let t = WorkspaceModel.shared.selectedTab
        return t.cwds[t.focusedPane] ?? NSHomeDirectory()
    }

    var body: some View {
        // The elapsed-time ticker lives here, not in the model: a TimelineView only ticks while it is in
        // the view hierarchy, so a hidden Hub costs no wakeups (idle-CPU rule). 30 s is plenty for "12m".
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date.timeIntervalSince1970
            let groups = HubModel.build(seats: registry.agents, seatStatus: { registry.statusOf($0) },
                                        seatAwake: { registry.isAwake($0) }, peers: hub.peers,
                                        builders: hub.builders, now: now, seatsOnly: hub.filter == .seats)
            HubPanelContent(groups: groups, allSeats: registry.agents, filter: $hub.filter, now: now,
                            actions: .live(registry),
                            onNew: { registry.builder = BuilderDraft() },
                            onDetail: { detail = $0 },
                            onReveal: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: $0.cwd)]) },
                            crew: crew.snapshot, crewNotice: crewNotice,
                            onCrewPick: { crewNotice = CrewDelivery.pick($0) })
        }
        .onAppear { hub.hubAppeared() }
        // Crew scan: only while the Crew tab is showing, and again when the focused pane's cwd changes.
        // `.task(id:)` runs once per id change and cancels with the view: no watcher, timer or poll.
        .task(id: CrewTrigger(active: hub.filter == .crew, cwd: focusedCwd)) {
            if hub.filter == .crew { await crew.refresh(cwd: focusedCwd) }
        }
        // One-shot auto-hide of the "Copied" notice; a new notice restarts it.
        .task(id: crewNotice) {
            guard crewNotice != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { crewNotice = nil }
        }
        .sheet(item: $detail) { BuilderDetailSheet(record: $0) }
    }
}

/// Pure view over groups + closures. No store, no registry.
struct HubPanelContent: View {
    static let width: CGFloat = 340
    let groups: [HubProjectGroup]
    /// Every saved seat — a builder's `parent` may live in another project's group.
    let allSeats: [Agent]
    @Binding var filter: HubFilter
    let now: Double
    let actions: SeatActions
    var onNew: () -> Void = {}
    var onDetail: (BuilderRecord) -> Void = { _ in }
    var onReveal: (PeerSession) -> Void = { _ in }
    var crew: CrewSnapshot?
    var crewNotice: String?
    var onCrewPick: (CrewAgent) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            if filter == .crew {
                CrewTabView(snapshot: crew, notice: crewNotice, onPick: onCrewPick)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: crewNotice)
            } else if groups.isEmpty && allSeats.isEmpty {
                ContentUnavailableView {
                    Label("No agents yet", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("Agents start asleep. Build your first one.")
                } actions: {
                    // Custom (not .borderedProminent): prominent buttons dim when the window isn't key. Same inverted
                    // white-on-black device as the attention pill.
                    Button(action: onNew) {
                        Text("New Agent").font(.callout.weight(.semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 16).padding(.vertical, 6).background(.white, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            } else if groups.isEmpty {
                ContentUnavailableView("Nothing running", systemImage: "moon.zzz",
                                       description: Text("No live sessions or background builds."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(groups) { group in
                            groupView(group).transition(rowTransition)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 16)
                    .animation(reduceMotion ? nil : .snappy, value: groups.map(\.id))
                }
            }
        }
        .frame(width: Self.width)
        .background(Theme.background)
    }

    private var rowTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top))
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Hub").font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer()
                Button(action: onNew) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                        .frame(width: 26, height: 26).background(Color.white.opacity(0.08), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain).help("New Agent").accessibilityLabel("New Agent")
            }
            Picker("Show", selection: $filter) {
                Text("All").tag(HubFilter.all)
                Text("Seats").tag(HubFilter.seats)
                Text("Crew").tag(HubFilter.crew)
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 12)
    }

    private func groupView(_ g: HubProjectGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(g.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                if !g.summary.isEmpty {
                    Text(g.summary).font(.caption.monospacedDigit()).foregroundStyle(Theme.hubSecondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            ForEach(g.seats) { AgentCard(agent: $0, actions: actions).transition(rowTransition) }
            if !g.background.isEmpty {
                sectionLabel("Background")
                ForEach(g.background) { b in
                    BuilderRow(record: b, now: now, parentHue: HubAvatar.parentHue(of: b.parent, seats: allSeats))
                        .onTapGesture { onDetail(b) }.transition(rowTransition)
                }
            }
            if !g.others.isEmpty {
                sectionLabel("Other sessions")
                ForEach(g.others) { p in
                    PeerRow(peer: p).onTapGesture { onReveal(p) }.transition(rowTransition)
                }
            }
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.caption.weight(.medium)).foregroundStyle(Theme.hubSecondary)
            .padding(.horizontal, 4).padding(.top, 8)
    }
}

enum HubAvatar {
    /// The hue of the seat a builder was started by (`record.parent` = a seat name), if we have that seat.
    static func parentHue(of parent: String?, seats: [Agent]) -> AgentHue? {
        guard let parent else { return nil }
        return seats.first { $0.name == parent }?.resolvedHue
    }
}

/// "12m", "1h 05m" — coarse on purpose; the ticker refreshes every 30 s.
func hubElapsed(_ seconds: Double) -> String {
    let m = Int(seconds / 60)
    return m < 60 ? "\(max(m, 0))m" : String(format: "%dh %02dm", m / 60, m % 60)
}

/// A lighter row than a seat card: nothing at rest, a faint fill on hover, 44 pt tall.
struct HubRowFrame<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        content
            .padding(.horizontal, 8).padding(.vertical, 6).frame(minHeight: 44)
            .background(hovering ? Theme.hubHoverFill : .clear, in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect(cornerRadius: 12, style: .continuous))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

struct BuilderRow: View {
    let record: BuilderRecord
    let now: Double
    var parentHue: AgentHue?
    var body: some View {
        let hue = AgentHue.derived(from: record.name)
        HubRowFrame {
            HStack(spacing: 10) {
                AgentAvatar(hue: hue, symbol: "hammer", status: record.status, size: 28, parentHue: parentHue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.name).font(.callout).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                    Text(secondary).font(.caption).foregroundStyle(Theme.hubSecondary).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 4)
                Text(hubElapsed(record.elapsed(now: now))).font(.caption.monospacedDigit()).foregroundStyle(Theme.hubSecondary)
            }
        }
        .help("Show this build's result")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.name), background build, \(secondary), \(hubElapsed(record.elapsed(now: now)))")
    }

    private var secondary: String {
        var parts = [record.status.label]
        if !record.model.isEmpty { parts.append(record.model.capitalized) }
        if let parent = record.parent { parts.append("from \(parent)") }
        return parts.joined(separator: " · ")
    }
}

struct PeerRow: View {
    let peer: PeerSession
    var body: some View {
        HubRowFrame {
            HStack(spacing: 10) {
                // Not our crew → no colour, no presence dot: strangers stay grey.
                AgentAvatar(hue: nil, symbol: "terminal", status: peer.busy ? .working : .idle, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(peer.displayName).font(.callout).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                    Text("\(peer.busy ? "Working" : "Idle") · \(peer.kind)").font(.caption)
                        .foregroundStyle(Theme.hubSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .help("Reveal \(peer.cwd) in Finder")
        .accessibilityElement(children: .combine)
    }
}

/// Read-only: the build's meta plus its report, or the tail of what it last did. Loaded off the main actor.
struct BuilderDetailSheet: View {
    let record: BuilderRecord
    @State private var text = "Loading…"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(record.name).font(.headline)
                StatusPill(status: record.status)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Group {
                Text("\(record.id) · \(record.model) · \(record.cwd)")
                if let b = record.branch { Text("branch \(b)") }
                if let c = record.cost { Text(String(format: "cost $%.2f", c) + (record.budget.map { String(format: " of $%.2f", $0) } ?? "")) }
                if let p = record.parent { Text("started by \(p)") }
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            Divider()
            ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(16).frame(width: 480, height: 420)
        .task { text = await Task.detached { HubScanner.detail(of: record) }.value }
    }
}
