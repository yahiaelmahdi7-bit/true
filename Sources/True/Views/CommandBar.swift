import SwiftUI

/// Isolates the bar's observation so opening it never re-evaluates the whole window body.
struct CommandBarHost: View {
    private let store = CommandBarStore.shared
    var body: some View {
        if store.isOpen { CommandBarView(store: store) }
    }
}

/// ⌘K: one text field, one quiet line that says where Return will send it.
struct CommandBarView: View {
    @Bindable var store: CommandBarStore
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture { store.close() }
            card
                .frame(width: 640)
                .padding(.top, 110)
        }
        .transition(.opacity)
    }

    private var card: some View {
        VStack(spacing: 0) {
            field
            if store.route != nil || store.reading {
                Divider().opacity(0.5)
                RouteLine(route: store.route, plan: store.plan, reading: store.reading, armed: store.armed,
                          choose: { store.choose($0) })
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
        .background {
            Button("") { store.run(background: true) }.keyboardShortcut(.return, modifiers: .command)
            Button("") { store.close() }.keyboardShortcut(.cancelAction)
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right").font(.title3).foregroundStyle(.secondary)
            TextField("Run, ask, or tell True…", text: $store.text)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit { store.run() }
                .onKeyPress(.upArrow) { store.historyUp(); return .handled }
                .onKeyPress(.downArrow) { store.historyDown(); return .handled }
                .onKeyPress(.tab) { store.takeRunnerUp(); return .handled }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

/// The one-line route: kind · project · target (· model · effort), `?` where Jev was unsure.
struct RouteLine: View {
    var route: Route?
    var plan: Plan?
    var reading = false
    var armed = false
    var choose: (CommandKind) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 6) {
            if let r = route {
                if r.twoChoice {
                    Text("Which one?").font(.callout).foregroundStyle(.secondary)
                    choice("Run in shell", .shellCommand)
                    choice("Send to Claude", .agentTask)
                } else {
                    chips(r)
                }
            }
            Spacer(minLength: 8)
            if reading {
                ProgressView().controlSize(.mini)
                Text("reading…").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 22)
    }

    @ViewBuilder
    private func chips(_ r: Route) -> some View {
        chip(kindLabel(r.kind), "return.right", r.uncertain.contains(.kind))
        if r.kind != .none {
            chip(r.project?.name ?? "this pane", "folder", r.uncertain.contains(.project))
        }
        if r.kind.sendsToClaude {
            chip(targetLabel(r.target), "arrow.turn.down.right", r.uncertain.contains(.target))
            if newProcess(r.target) {
                if let m = r.model { chip(m.label, nil, false) }
                if let e = r.effort { chip(e.label, nil, false) }
            }
        }
        if r.kind.sendsToClaude, r.isDestructive {
            Text(armed ? "Return again to send" : "will ask first")
                .font(.caption.weight(.medium)).foregroundStyle(.orange)
        }
        if r.kind == .shellCommand, let p = plan, !p.autoSubmit {
            Text("typed, not sent").font(.caption).foregroundStyle(.orange)
        }
        if let alt = r.alternatives.first {
            Text("Tab: \(kindLabel(alt))").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func newProcess(_ t: CommandTarget) -> Bool { t == .newClaudePane || t == .backgroundBuilder }

    private func kindLabel(_ k: CommandKind) -> String {
        switch k {
        case .shellCommand: "Run in shell"
        case .agentTask: "Send to Claude"
        case .questionForClaude: "Ask Claude"
        case .trueAction: "True action"
        case .none: "Nothing to do"
        }
    }

    private func targetLabel(_ t: CommandTarget) -> String {
        switch t {
        case .focusedPane: "current"
        case .newClaudePane: "new pane"
        case .backgroundBuilder: "background"
        case .seat(let n): n
        }
    }

    private func chip(_ text: String, _ icon: String?, _ unsure: Bool) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(unsure ? text + " ?" : text).font(.caption)
        }
        .foregroundStyle(unsure ? .primary : .secondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.white.opacity(unsure ? 0.12 : 0.07), in: Capsule())
    }

    private func choice(_ text: String, _ k: CommandKind) -> some View {
        Button(text) { choose(k) }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(.white.opacity(0.14), in: Capsule())
    }
}
