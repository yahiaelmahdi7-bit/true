import SwiftUI
import UniformTypeIdentifiers

/// The character creator: live card on the left, native controls on the right.
struct AgentBuilderSheet: View {
    @State var draft: BuilderDraft
    let registry: AgentRegistry
    @Environment(\.dismiss) private var dismiss
    @State private var pickingRepo = false
    @State private var request = ""
    @State private var fillTask: Task<Void, Never>?
    @State private var fillError: String?

    var body: some View {
        let existing = registry.agents
        let name = draft.name(existing: existing)
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 12) {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
                AgentCardFace(agent: preview(existing), name: name ?? "pick a repo", status: .asleep)
                    .frame(width: 290)
                Spacer(minLength: 0)
            }
            Form {
                Section("Describe") {
                    TextField("What should this agent do?", text: $request, axis: .vertical)
                        .lineLimit(1...3)
                    HStack {
                        Button {
                            if fillTask != nil { fillTask?.cancel() } else { startFill() }
                        } label: {
                            Label(fillTask != nil ? "Cancel" : "Fill", systemImage: fillTask != nil ? "xmark" : "sparkles")
                        }
                        .disabled(fillTask == nil && request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if fillTask != nil { ProgressView().controlSize(.small) }
                    }
                    if let fillError {
                        Text(fillError).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    LabeledContent("Repo") {
                        HStack {
                            Text(draft.repo.isEmpty ? "None" : (draft.repo as NSString).lastPathComponent)
                                .foregroundStyle(.secondary)
                            if draft.editing == nil { Button("Choose…") { pickingRepo = true } }
                        }
                    }
                    LabeledContent("Name", value: name ?? (draft.repo.isEmpty ? "—" : "no free slot"))
                    if draft.editing == nil {
                        Picker("Role", selection: $draft.role) {
                            ForEach(AgentRole.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: draft.role) { _, r in
                            if Self.isDefault(draft.symbol) { draft.symbol = r.defaultSymbol }
                        }
                    }
                }
                Section {
                    Picker("Model", selection: $draft.model) {
                        ForEach(AgentModel.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Effort") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Slider(value: effortBinding, in: 0...4, step: 1)
                            Text(draft.effort.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Picker("Permissions", selection: $draft.permission) {
                        ForEach(AgentPermission.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 8), spacing: 6) {
                        ForEach(BuilderDraft.symbols, id: \.self) { s in
                            Button { draft.symbol = s } label: {
                                Image(systemName: s).frame(width: 30, height: 26)
                                    .background(draft.symbol == s ? draft.model.tint.opacity(0.3) : .clear,
                                                in: .rect(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Charter") {
                    TextEditor(text: $draft.charter)
                        .font(.body).frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                }
                if draft.role == .lead {
                    let helpers = draft.helperChoices(existing: existing)
                    Section("Manages") {
                        if helpers.isEmpty {
                            Text("No helpers in this repo yet — build them first.").foregroundStyle(.secondary)
                        }
                        ForEach(helpers) { h in
                            Toggle(h.name, isOn: Binding(
                                get: { draft.team.contains(h.name) },
                                set: { on in if on { draft.team.insert(h.name) } else { draft.team.remove(h.name) } }))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 400)
        }
        .padding(16)
        .frame(minHeight: 560)
        .safeAreaInset(edge: .bottom) {
            HStack {
                if let editing = draft.editing {
                    Button("Delete", role: .destructive) { registry.delete(editing); dismiss() }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(draft.editing == nil ? "Create" : "Save") {
                    if let a = draft.agent(existing: existing) { registry.save(a) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSave(existing: existing))
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .onDisappear { fillTask?.cancel() }
        .fileImporter(isPresented: $pickingRepo, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { draft.repo = url.path }
        }
    }

    private func startFill() {
        fillError = nil
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = draft
        fillTask = Task {
            defer { fillTask = nil }
            do {
                let profile = try await AgentFill.run(request: text, draft: snapshot)
                if !Task.isCancelled { AgentFill.apply(profile, to: &draft) }
            } catch is CancellationError {
            } catch {
                fillError = error.localizedDescription
            }
        }
    }

    private var effortBinding: Binding<Double> {
        Binding(get: { Double(draft.effort.level - 1) },
                set: { draft.effort = AgentEffort.allCases[min(max(Int($0.rounded()), 0), 4)] })
    }

    private static func isDefault(_ symbol: String) -> Bool {
        AgentRole.allCases.contains { $0.defaultSymbol == symbol }
    }

    private func preview(_ existing: [Agent]) -> Agent {
        Agent(name: draft.name(existing: existing) ?? "", role: draft.role, repo: draft.repo,
              model: draft.model, effort: draft.effort, permission: draft.permission,
              charter: draft.charter, symbol: draft.symbol)
    }
}
