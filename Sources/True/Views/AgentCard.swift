import SwiftUI

extension AgentModel {
    /// Tier as brightness — True is black and white only: the heavier the model, the whiter.
    var tint: Color {
        switch self {
        case .haiku: return Color(white: 0.55)
        case .sonnet: return Color(white: 0.70)
        case .opus: return Color(white: 0.85)
        case .fable: return Color(white: 1.0)
        }
    }
}

extension AgentStatus {
    var tint: Color {
        switch self {
        case .asleep: return Color(white: 0.25)
        case .idle: return Color(white: 0.45)
        case .working: return Color(white: 0.90)
        case .needsYou: return Color(white: 1.0)
        case .done: return Color(white: 0.65)
        case .failed: return Color(white: 0.55)
        }
    }
}

/// Five lit/unlit bars — the effort level at a glance.
struct EffortMeter: View {
    let level: Int
    let tint: Color
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Capsule().fill(i <= level ? tint : Color.primary.opacity(0.15))
                    .frame(width: 5, height: 5 + CGFloat(i) * 2)
            }
        }
        .frame(height: 15, alignment: .bottom)
        .accessibilityLabel("Effort \(level) of 5")
    }
}

struct StatusPill: View {
    let status: AgentStatus
    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(status.tint.opacity(0.22), in: .capsule)
            .foregroundStyle(status == .asleep ? Color.secondary : status.tint)
    }
}

/// The character card. Pure display from an `Agent` + a status, so the builder reuses it as its
/// live preview.
struct AgentCardFace: View {
    let agent: Agent
    let name: String
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: agent.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(agent.model.tint)
                .frame(width: 40, height: 40)
                .background(agent.model.tint.opacity(0.18), in: .circle)
                .overlay(Circle().strokeBorder(agent.model.tint.opacity(0.5), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    StatusPill(status: status)
                }
                HStack(spacing: 8) {
                    Text(agent.model.label).font(.caption.weight(.medium)).foregroundStyle(agent.model.tint)
                    EffortMeter(level: agent.effort.level, tint: agent.model.tint)
                    Spacer(minLength: 0)
                    Label(agent.permission.label, systemImage: agent.permission.symbol)
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// A card in the panel: click wakes / focuses, buttons sleep / edit, the lead has a message field.
struct AgentCard: View {
    let agent: Agent
    let registry: AgentRegistry
    @State private var message = ""
    @State private var note: String?

    var body: some View {
        let status = registry.statusOf(agent.name)
        VStack(alignment: .leading, spacing: 6) {
            AgentCardFace(agent: agent, name: agent.name, status: status)
                .contentShape(.rect)
                .onTapGesture { registry.wake(agent.name) }
                .help(registry.isAwake(agent.name) ? "Focus its tab" : "Wake \(agent.name)")
            HStack(spacing: 8) {
                if registry.isAwake(agent.name) {
                    Button("Sleep", systemImage: "moon.zzz") { registry.sleep(agent.name) }
                } else {
                    Button("Wake", systemImage: "sun.max") { registry.wake(agent.name) }
                }
                Button("Edit", systemImage: "slider.horizontal.3") {
                    registry.builder = BuilderDraft(editing: agent)
                }
                Spacer(minLength: 0)
                if let note { Text(note).font(.caption2).foregroundStyle(Theme.text) }
            }
            .buttonStyle(.borderless).controlSize(.small).labelStyle(.titleAndIcon)
            if agent.role != .helper {
                TextField("Message \(agent.name)…", text: $message)
                    .textFieldStyle(.roundedBorder).controlSize(.small)
                    .onSubmit(send)
            }
        }
    }

    private func send() {
        let text = message
        message = ""
        note = registry.isAwake(agent.name) ? nil : "waking…"
        registry.talk(agent.name, text) { outcome in
            Task { @MainActor in
                switch outcome {
                case .landed, .staged: note = nil
                case .unverified: note = "sent — not confirmed"
                case .stuckInComposer: note = "still in the composer"
                case .noPane, .promptGone: note = "couldn't deliver"
                }
            }
        }
    }
}

struct AgentsPanel: View {
    let registry: AgentRegistry

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agents").font(.headline)
                Spacer()
                Button { registry.builder = BuilderDraft() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("New Agent")
            }
            .padding(.horizontal, 14).frame(height: 38)
            Divider()
            if registry.agents.isEmpty {
                ContentUnavailableView("No agents yet", systemImage: "person.crop.circle.badge.plus",
                                       description: Text("Press + to build your first one. Agents start asleep."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(AgentRegistry.grouped(registry.agents), id: \.key) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(group.title, systemImage: group.key.isEmpty ? "globe" : "folder")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(group.agents) { AgentCard(agent: $0, registry: registry) }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 330)
        .background(Theme.background)
    }
}
