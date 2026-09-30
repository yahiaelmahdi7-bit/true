import SwiftUI
import AppKit

/// The ⌘E panel: every Claude session on this Mac, grouped by project (SPEC Run 7). Seats keep their
/// character cards; background builds and other live sessions get slim read-only rows.
struct HubPanel: View {
    let registry: AgentRegistry
    @State private var hub = HubStore.shared
    @State private var detail: BuilderRecord?

    var body: some View {
        // The elapsed-time ticker lives here, not in the model: a TimelineView only ticks while it is in
        // the view hierarchy, so a hidden Hub costs no wakeups (idle-CPU rule). 30 s is plenty for "12m".
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            content(now: timeline.date.timeIntervalSince1970)
        }
        .frame(width: 330)
        .background(Theme.background)
        .onAppear { hub.hubAppeared() }
        .sheet(item: $detail) { BuilderDetailSheet(record: $0) }
    }

    private func content(now: Double) -> some View {
        let groups = HubModel.build(seats: registry.agents, seatStatus: { registry.statusOf($0) },
                                    seatAwake: { registry.isAwake($0) }, peers: hub.peers,
                                    builders: hub.builders, now: now, seatsOnly: hub.seatsOnly)
        return VStack(spacing: 0) {
            HStack {
                Text("Hub").font(.headline)
                Spacer()
                Button { registry.builder = BuilderDraft() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("New Agent")
            }
            .padding(.horizontal, 14).frame(height: 38)
            Picker("Show", selection: $hub.seatsOnly) {
                Text("All").tag(false)
                Text("Seats").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 12).padding(.bottom, 8)
            Divider()
            if groups.isEmpty && registry.agents.isEmpty {
                ContentUnavailableView("No agents yet", systemImage: "person.crop.circle.badge.plus",
                                       description: Text("Press + to build your first one. Agents start asleep."))
            } else if groups.isEmpty {
                ContentUnavailableView("Nothing running", systemImage: "moon.zzz",
                                       description: Text("No live sessions or background builds."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groups) { group in
                            groupView(group, now: now)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func groupView(_ g: HubProjectGroup, now: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(g.title, systemImage: g.key.isEmpty ? "globe" : "folder")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !g.summary.isEmpty { Text(g.summary).font(.caption2).foregroundStyle(Theme.dimText) }
            }
            ForEach(g.seats) { AgentCard(agent: $0, registry: registry) }
            if !g.background.isEmpty {
                sectionLabel("Background")
                ForEach(g.background) { b in
                    BuilderRow(record: b, now: now).onTapGesture { detail = b }
                }
            }
            if !g.others.isEmpty {
                sectionLabel("Other sessions")
                ForEach(g.others) { p in
                    PeerRow(peer: p).onTapGesture {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p.cwd)])
                    }
                }
            }
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.caption2.weight(.medium)).foregroundStyle(Theme.dimText).padding(.top, 2)
    }
}

/// "12m", "1h 05m" — coarse on purpose; the ticker refreshes every 30 s.
func hubElapsed(_ seconds: Double) -> String {
    let m = Int(seconds / 60)
    return m < 60 ? "\(max(m, 0))m" : String(format: "%dh %02dm", m / 60, m % 60)
}

private struct HubRowFrame<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(10)
            .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(.rect)
    }
}

struct BuilderRow: View {
    let record: BuilderRecord
    let now: Double
    var body: some View {
        let tint = AgentModel(rawValue: record.model)?.tint ?? Color(white: 0.55)
        HubRowFrame {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "hammer").font(.caption).foregroundStyle(tint)
                    Text(record.name).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    StatusPill(status: record.status)
                }
                HStack(spacing: 8) {
                    if !record.model.isEmpty { Text(record.model.capitalized).font(.caption.weight(.medium)).foregroundStyle(tint) }
                    Text(hubElapsed(record.elapsed(now: now))).font(.caption).foregroundStyle(.secondary)
                    if let parent = record.parent { Text("from \(parent)").font(.caption2).foregroundStyle(Theme.dimText) }
                    Spacer(minLength: 0)
                }
            }
        }
        .help("Show this build's result")
    }
}

struct PeerRow: View {
    let peer: PeerSession
    var body: some View {
        HubRowFrame {
            HStack(spacing: 6) {
                Image(systemName: "terminal").font(.caption).foregroundStyle(.secondary)
                Text(peer.displayName).font(.callout).lineLimit(1).truncationMode(.middle)
                Text(peer.kind).font(.caption2).foregroundStyle(Theme.dimText)
                Spacer(minLength: 0)
                StatusPill(status: peer.busy ? .working : .idle)
            }
        }
        .help("Reveal \(peer.cwd) in Finder")
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
