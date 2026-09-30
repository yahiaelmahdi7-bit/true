import SwiftUI

/// The Hub's Crew tab body: pure view over a snapshot + closures (no store, no workspace).
struct CrewTabView: View {
    let snapshot: CrewSnapshot?
    var notice: String?
    var onPick: (CrewAgent) -> Void = { _ in }

    var body: some View {
        if let snapshot {
            if snapshot.isEmpty {
                ContentUnavailableView("No crew found", systemImage: "person.3",
                                       description: Text("No sub-agents in .claude/agents."))
            } else {
                list(snapshot)
            }
        } else {
            Spacer()
        }
    }

    private func list(_ s: CrewSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(s.header).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .lineLimit(1).truncationMode(.middle).padding(.horizontal, 4)
                if let notice {
                    Label(notice, systemImage: "doc.on.clipboard").font(.caption).foregroundStyle(Theme.text)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.hubCardFill, in: .capsule)
                        .transition(.opacity)
                }
                ForEach(s.project) { g in
                    VStack(alignment: .leading, spacing: 4) {
                        label(g.title)
                        ForEach(g.agents) { CrewRow(agent: $0, onPick: onPick) }
                    }
                }
                if !s.global.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        label("Everywhere")
                        ForEach(s.global) { g in
                            DisclosureGroup {
                                ForEach(g.agents) { CrewRow(agent: $0, onPick: onPick) }
                            } label: {
                                HStack {
                                    Text(g.title).font(.callout.weight(.medium)).foregroundStyle(Theme.text)
                                    Spacer()
                                    Text("\(g.agents.count)").font(.caption.monospacedDigit()).foregroundStyle(Theme.hubSecondary)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 16)
        }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.caption.weight(.medium)).foregroundStyle(Theme.hubSecondary).padding(.horizontal, 4)
    }
}

struct CrewRow: View {
    let agent: CrewAgent
    let onPick: (CrewAgent) -> Void

    var body: some View {
        Button { onPick(agent) } label: {
            HubRowFrame {
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(CrewColor.tint(agent.color)).frame(width: 10, height: 10).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(agent.name).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                            .lineLimit(1).truncationMode(.middle)
                        if !agent.summary.isEmpty {
                            Text(agent.summary).font(.caption).foregroundStyle(Theme.hubSecondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(agent.model).font(.caption).foregroundStyle(Theme.hubSecondary).lineLimit(1)
                }
            }
        }
        .buttonStyle(CrewPressStyle())
        .help(agent.fullDescription.isEmpty ? agent.name : agent.fullDescription)
        .accessibilityLabel("\(agent.name), \(agent.model). \(agent.summary)")
        .accessibilityHint("Types a starter prompt into the focused Claude pane")
    }
}

/// Plain button with a pressed fill (hover comes from `HubRowFrame`).
private struct CrewPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.08) : .clear, in: .rect(cornerRadius: 12, style: .continuous))
    }
}

enum CrewColor {
    static func tint(_ name: String?) -> Color {
        switch name {
        case "blue": .blue
        case "red": .red
        case "pink": .pink
        case "purple": .purple
        case "orange": .orange
        case "green": .green
        case "yellow": .yellow
        case "cyan": .cyan
        default: .secondary
        }
    }
}
