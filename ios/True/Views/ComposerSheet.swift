import SwiftUI

private let confirmWhy = [
    "background_builder": "Starts a background builder (~$5 ceiling)",
    "unjudged": "Couldn't check this for danger",
    "dangerous_text": "This looks destructive",
    "seat_working": "That seat is working and sleeping it interrupts the task",
]
private let slotOrder: [(key: String, title: String)] = [("kind", "Kind"), ("project", "Project"), ("target", "Where"), ("model", "Model"), ("effort", "Effort")]
private let slotSymbol = ["kind": "sparkles", "project": "folder", "target": "rectangle.split.2x1", "model": "cpu", "effort": "dial.low"]

struct ComposerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = UserDefaults.standard.string(forKey: "composerText") ?? ""
    @State private var route: RouteResponse?
    @State private var background = false
    @State private var busy = false
    @State private var message: String?
    @State private var recent: [String] = []
    @State private var confirmReason: String?
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What should happen?", text: $text, axis: .vertical)
                        .lineLimit(3...6).submitLabel(.go).focused($focused).textInputAutocapitalization(.sentences)
                        .onChange(of: text) { _, v in if v.contains(where: \.isNewline) { text = v.split(whereSeparator: \.isNewline).joined(separator: " ") } }
                        .onSubmit { Task { await doRoute() } }
                    // Single-primary rule: Route is prominent only until a route exists; then Run takes over.
                    if route == nil { routeButton.buttonStyle(.borderedProminent) } else { routeButton.buttonStyle(.bordered) }
                }
                if let message { Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.attention) } }
                if let r = route {
                    Section("Plan") {
                        TileRow(symbol: "sparkles", title: "Does", detail: r.route.kindLabel)
                        TileRow(symbol: "rectangle.split.2x1", title: "Where", detail: r.route.whereLabel)
                        if let p = r.route.project { TileRow(symbol: "folder", title: "Project", detail: p) }
                        if let m = r.route.model { TileRow(symbol: "cpu", title: "Model", detail: m) }
                        if let e = r.route.effort { TileRow(symbol: "dial.low", title: "Effort", detail: e) }
                    }
                    Section("Change") {
                        ForEach(slotOrder, id: \.key) { slot in
                            if let options = r.candidates[slot.key], options.count > 1 { slotRow(slot.key, slot.title, options, r) }
                        }
                    }
                    if r.route.dangerous { Section { Label("Looks risky — you will be asked to confirm.", systemImage: "exclamationmark.triangle").foregroundStyle(.attention) } }
                    if !r.runnable { Section { Text("Nothing to run from the phone for this route.").foregroundStyle(.secondary) } }
                } else if !recent.isEmpty {
                    Section("Recent") {
                        ForEach(recent, id: \.self) { r in
                            Button { text = r } label: { TileRow(symbol: "clock.arrow.circlepath", title: r, titleStyle: AnyShapeStyle(.secondary), truncation: .tail) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { if let r = route, r.runnable { runBar } }
            .navigationTitle("Start work").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                if busy { ToolbarItem(placement: .primaryAction) { ProgressView() } }
            }
            .alert("Run anyway?", isPresented: Binding(get: { confirmReason != nil }, set: { if !$0 { confirmReason = nil } })) {
                Button("Run anyway", role: .destructive) { Task { await run(confirmed: true) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text(confirmWhy[confirmReason ?? ""] ?? "This looks destructive (\((confirmReason ?? "risky").replacingOccurrences(of: "_", with: " ")))") }
        }
        .task {
            focused = true
            recent = (try? await model.session?.recent()) ?? []
            if UserDefaults.standard.bool(forKey: "composerRoute") || model.uiState == "composer-routed" { if text.isEmpty { text = "fix the failing login test in true" }; await doRoute() }
        }
    }

    private var routeButton: some View {
        Button { Task { await doRoute() } } label: { Text("Route").frame(maxWidth: .infinity) }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || busy)
    }

    private var modeMenu: some View {
        Menu {
            Picker("Where to run", selection: $background) {
                Label("In a pane", systemImage: "rectangle.on.rectangle").tag(false)
                Label("In the background", systemImage: "hammer").tag(true)
            }
        } label: {
            Label(background ? "In the background" : "In a pane", systemImage: background ? "hammer" : "rectangle.on.rectangle")
        }
        .buttonStyle(.glass).controlSize(.large)
    }

    private var runBar: some View {
        let runButton = Button { Task { await run(confirmed: false) } } label: {
            Group { if busy { ProgressView() } else { Text("Run") } }.frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent).controlSize(.large).disabled(busy)
        return Group {
            if typeSize.isAccessibilitySize { VStack(spacing: 12) { modeMenu; runButton } } else { HStack(spacing: 12) { modeMenu; runButton } }
        }
        .padding(.horizontal).padding(.bottom, 8)
    }

    @ViewBuilder private func slotRow(_ key: String, _ title: String, _ options: [RouteOption], _ r: RouteResponse) -> some View {
        let current = current(key, r)
        let binding = Binding(get: { current }, set: { v in Task { await setSlot(key, v) } })
        let uncertain = r.uncertain.contains(key)
        let sym = slotSymbol[key] ?? "circle"
        let titleStyle: AnyShapeStyle = uncertain ? AnyShapeStyle(.attention) : AnyShapeStyle(.primary)
        if options.count <= 3 {
            VStack(alignment: .leading, spacing: 8) {
                TileRow(symbol: sym, title: title, titleStyle: titleStyle) {
                    if uncertain { Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.attention) }
                }
                Picker(title, selection: binding) { ForEach(options, id: \.value) { Text($0.label).tag($0.value) } }
                    .pickerStyle(.segmented).tint(uncertain ? .attention : nil)
            }
        } else {
            TileRow(symbol: sym, title: title, titleStyle: titleStyle) {
                HStack(spacing: 4) {
                    Picker(title, selection: binding) { ForEach(options, id: \.value) { Text($0.label).tag($0.value) } }
                        .pickerStyle(.menu).labelsHidden()
                    if uncertain { Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.attention) }
                }
            }
        }
    }

    private func current(_ key: String, _ r: RouteResponse) -> String {
        switch key {
        case "kind": r.route.kind
        case "project": r.route.project ?? ""
        case "target": r.route.target
        case "model": r.route.model ?? ""
        default: r.route.effort ?? ""
        }
    }

    private func fail(_ e: Error) async {
        await model.handle(e)
        switch e {
        case RemoteError.routeExpired: message = "That route expired — tap Route again."; route = nil
        case RemoteError.rateLimited: message = "Slow down — too many requests."
        case RemoteError.refused: message = "The Mac refused this one."
        case RemoteError.http(let c): message = "Failed (\(c))"
        default: message = "Could not reach the Mac (offline?)"
        }
    }

    private func doRoute() async {
        let t = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let s = model.session else { return }
        busy = true; message = nil; defer { busy = false }
        do { route = try await s.route(text: t) } catch { await fail(error) }
    }

    private func setSlot(_ key: String, _ value: String) async {
        guard let id = route?.routeId, let s = model.session else { return }
        do { route = try await s.setSlot(routeId: id, slot: key, value: value) }
        catch RemoteError.routeExpired { message = "That route expired — tap Route again."; route = nil }
        catch RemoteError.http, RemoteError.refused { message = "That choice is not available." }
        catch { await fail(error) }
    }

    private func run(confirmed: Bool) async {
        guard let id = route?.routeId, let s = model.session else { return }
        busy = true; message = nil; defer { busy = false }
        do {
            let out = try await s.run(routeId: id, background: background, confirmed: confirmed)
            if out.needsConfirm == true { confirmReason = out.reason ?? "risky"; return }
            dismiss()
            if let pane = out.pane { model.selectedTab = "hub"; model.openPane = PaneRoute(id: pane, title: "New pane") }
            else { model.show(out.background.map { "Builder \($0) started." } ?? "Started.") }
            await model.refresh()
        } catch { await fail(error) }
    }
}
