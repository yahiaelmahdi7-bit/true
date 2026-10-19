import SwiftUI

/// "12m ago" for a finished row, "12m" for one still running, "now" under a minute.
func triageTime(_ item: TriageItem, now: Double) -> String {
    let s = max(0, now - item.at)
    if s < 60 { return item.tone == .working ? "<1m" : "now" }
    return item.tone == .working ? hubElapsed(s) : hubElapsed(s) + " ago"
}

extension TriageTone {
    var glyph: String {
        switch self {
        case .failed: return "xmark.circle.fill"
        case .needsYou: return "exclamationmark.circle.fill"
        case .working: return "circle.dotted"
        case .done: return "checkmark.circle"
        case .idle: return "circle"
        }
    }
    var color: Color {
        switch self {
        case .failed: return Theme.hubFailed
        case .needsYou: return Theme.verdictWarn
        case .working: return Theme.text
        case .done: return Theme.hubSecondary
        case .idle: return Theme.dimText
        }
    }
    var word: String {
        switch self {
        case .failed: return "failed"
        case .needsYou: return "needs you"
        case .working: return "working"
        case .done: return "done"
        case .idle: return "idle"
        }
    }
}

struct TriageGlyph: View {
    let tone: TriageTone
    var cloud = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Image(systemName: tone.glyph).font(.system(size: 17, weight: .medium)).foregroundStyle(tone.color)
            .symbolEffect(.pulse, isActive: tone == .working && !reduceMotion)
            .frame(width: 24, height: 24)
            .overlay(alignment: .bottomTrailing) {
                if cloud {
                    Image(systemName: "icloud.fill").font(.system(size: 8)).foregroundStyle(Theme.hubSecondary)
                        .padding(1.5).background(Color.black, in: .circle).offset(x: 4, y: 3)
                }
            }
            .accessibilityHidden(true)
    }
}

/// The one button on a row. Needs-you rows get the inverted capsule (same device as the attention pill).
struct TriageButton: View {
    let label: String
    let loud: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.callout.weight(.medium)).lineLimit(1)
                .foregroundStyle(loud ? Color.black : Theme.text)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(loud ? Color.white : Color.white.opacity(0.10), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

struct ProjectChip: View {
    let name: String
    var body: some View {
        if !name.isEmpty {
            Text(name).font(.caption).foregroundStyle(Theme.hubSecondary).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.white.opacity(0.07), in: .capsule)
                .frame(maxWidth: 120)
        }
    }
}

/// Row chrome: hover and keyboard selection share one fill.
private struct TriageRowFrame<Content: View>: View {
    let selected: Bool
    var indent: CGFloat = 0
    @ViewBuilder var content: Content
    @State private var hovering = false
    var body: some View {
        content
            .padding(.leading, 10 + indent).padding(.trailing, 10).padding(.vertical, 7).frame(minHeight: 46)
            .background(selected ? Color.white.opacity(0.10) : hovering ? Theme.hubHoverFill : .clear,
                        in: .rect(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0.18 : 0), lineWidth: 1))
            .contentShape(.rect(cornerRadius: 10, style: .continuous))
            .onHover { hovering = $0 }
    }
}

struct TriageRowView: View {
    let item: TriageItem
    let now: Double
    let selected: Bool
    var indent: CGFloat = 0
    var showProject = true
    let onAction: (TriageItem) -> Void

    var body: some View {
        TriageRowFrame(selected: selected, indent: indent) {
            HStack(spacing: 10) {
                TriageGlyph(tone: item.tone, cloud: item.isCloud)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.body).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                    Text(item.subtitle).font(.callout).foregroundStyle(Theme.hubSecondary).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 6)
                if showProject { ProjectChip(name: item.project) }
                Text(triageTime(item, now: now)).font(.callout.monospacedDigit()).foregroundStyle(Theme.hubSecondary)
                    .frame(minWidth: 52, alignment: .trailing)
                if !item.actionLabel.isEmpty {
                    TriageButton(label: item.actionLabel, loud: item.tone == .needsYou) { onAction(item) }
                }
            }
        }
        .onTapGesture(count: 2) { onAction(item) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.isCloud ? "cloud, " : "")\(item.tone.word), \(item.project), \(item.subtitle)")
        .accessibilityAction(named: item.actionLabel) { onAction(item) }
    }
}

struct TriageGroupView: View {
    let id: String
    let project: String
    let tone: TriageTone
    let label: String
    let items: [TriageItem]
    let now: Double
    let expanded: Bool
    let selected: String?
    let toggle: () -> Void
    let onAction: (TriageItem) -> Void

    private var groupTime: String {
        guard var newest = items.first else { return "" }
        newest.at = items.map(\.at).max() ?? newest.at
        return triageTime(newest, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TriageRowFrame(selected: selected == id) {
                HStack(spacing: 10) {
                    TriageGlyph(tone: tone, cloud: items.allSatisfy(\.isCloud))
                    (Text(project).foregroundStyle(Theme.text) + Text(" · \(label)").foregroundStyle(Theme.hubSecondary))
                        .font(.body).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(groupTime).font(.callout.monospacedDigit()).foregroundStyle(Theme.hubSecondary)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.hubSecondary).rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 20)
                }
            }
            .onTapGesture(perform: toggle)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(project), \(label)")
            .accessibilityHint(expanded ? "Collapses the list" : "Shows each one")
            .accessibilityAddTraits(.isButton)
            if expanded {
                ForEach(items) { i in
                    TriageRowView(item: i, now: now, selected: selected == i.id, indent: 24, showProject: false, onAction: onAction)
                        .id(i.id)
                }
            }
        }
    }
}

/// The All tab body: four sections, ↑↓ to move, ⏎ for the row's button. Pure over buckets + closures.
struct TriageListView: View {
    let buckets: [TriageBucket]
    let now: Double
    /// Set by the header's "N failed": select that row and scroll to it.
    @Binding var jump: String?
    var peers: AnyView = AnyView(EmptyView())
    let onAction: (TriageItem) -> Void

    @State private var selected: String?
    @State private var expanded: Set<String> = []
    @State private var historyOpen = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ids: [String] { HubTriage.visibleIDs(buckets, expanded: expanded, historyOpen: historyOpen) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(buckets) { b in section(b) }
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
            }
            .focusable().focused($focused).focusEffectDisabled()
            .onAppear { focused = true }
            .onKeyPress(.upArrow) { selected = HubTriage.move(ids, from: selected, by: -1); return .handled }
            .onKeyPress(.downArrow) { selected = HubTriage.move(ids, from: selected, by: 1); return .handled }
            .onKeyPress(.return) { activate(); return selected == nil ? .ignored : .handled }
            .onChange(of: selected) { _, new in
                if let new { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { proxy.scrollTo(new) } }
            }
            .onChange(of: jump) { _, new in
                guard let new else { return }
                selected = new; focused = true
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) }
                jump = nil
            }
        }
    }

    private func activate() {
        guard let selected, let hit = HubTriage.entry(buckets, id: selected) else { return }
        if let item = hit.item { onAction(item) } else if let g = hit.groupID { toggle(g) }
    }

    private func toggle(_ id: String) {
        withAnimation(reduceMotion ? nil : .snappy) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    @ViewBuilder private func section(_ b: TriageBucket) -> some View {
        if b.section == .history {
            VStack(alignment: .leading, spacing: 4) {
                Button { withAnimation(reduceMotion ? nil : .snappy) { historyOpen.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(historyOpen ? 90 : 0)).frame(width: 12)
                        header(b)
                    }.contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(historyOpen ? "Collapses History" : "Shows older work")
                if historyOpen {
                    peers
                    entries(b)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                header(b)
                if b.entries.isEmpty {
                    Text(b.section.emptyText).font(.callout).foregroundStyle(Theme.dimText).padding(.horizontal, 10).padding(.vertical, 6)
                } else {
                    entries(b)
                }
            }
        }
    }

    private func header(_ b: TriageBucket) -> some View {
        HStack(spacing: 6) {
            Text(b.section.title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
            Text("\(b.count)").font(.callout.monospacedDigit()).foregroundStyle(Theme.hubSecondary)
            Spacer()
        }
        .padding(.horizontal, b.section == .history ? 0 : 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func entries(_ b: TriageBucket) -> some View {
        if b.section == .history && b.entries.isEmpty {
            Text(b.section.emptyText).font(.callout).foregroundStyle(Theme.dimText).padding(.horizontal, 10).padding(.vertical, 6)
        }
        ForEach(b.entries) { e in
            switch e {
            case .row(let i):
                TriageRowView(item: i, now: now, selected: selected == i.id, onAction: onAction)
                    .id(i.id).onTapGesture { selected = i.id }
            case .group(let id, let project, let tone, let label, let items):
                TriageGroupView(id: id, project: project, tone: tone, label: label, items: items, now: now,
                                expanded: expanded.contains(id), selected: selected,
                                toggle: { selected = id; toggle(id) }, onAction: onAction)
                    .id(id)
            }
        }
    }
}
