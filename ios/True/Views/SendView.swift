import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

private struct SendPickers: ViewModifier {
    @Binding var photo: PhotosPickerItem?
    @Binding var importing: Bool
    @Binding var exported: URL?
    @Binding var preview: URL?
    let onPhoto: (PhotosPickerItem?) -> Void
    let onFile: (Result<URL, Error>) -> Void
    func body(content: Content) -> some View {
        content
            .onChange(of: photo) { _, item in onPhoto(item) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], onCompletion: onFile)
            .sheet(item: $exported) { ShareSheet(items: [$0]) }
            .quickLookPreview($preview)
    }
}

struct SendView: View {
    @Environment(AppModel.self) private var model
    @State private var inbox: [InboxItem]?
    @State private var clip = ""
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var exported: URL?
    @State private var preview: URL?
    @State private var pending: String?
    @State private var sent = 0
    @AppStorage("autoClipboard") private var autoClipboard = true
    @AppStorage("autoScreenshots") private var autoScreenshots = false
    @AppStorage("onDuty") private var onDuty = false

    /// The Mac's shared clipboard item, else the newest text item.
    private var macClip: InboxItem? {
        inbox?.first { $0.source == "clipboardShare" } ?? inbox?.first { $0.kind == "text" }
    }

    private func symbol(_ item: InboxItem) -> String {
        if item.kind == "text" { return "doc.on.clipboard" }
        let ext = (item.name as NSString).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "gif", "webp"].contains(ext) { return "photo" }
        if ["zip", "gz", "tar", "tgz"].contains(ext) { return "zipper" }
        return "doc"
    }

    /// Turning it on asks for Photos access; if that is refused the switch falls back to off.
    private var screenshotBinding: Binding<Bool> {
        Binding(get: { autoScreenshots }, set: { on in
            guard on else { autoScreenshots = false; return }
            Task {
                if await ScreenshotSync.requestAccess() { autoScreenshots = true }
                else { autoScreenshots = false; model.show("Allow Photos access in Settings") }
            }
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let macClip {
                        TileRow(symbol: "doc.on.clipboard", title: macClip.preview ?? "Clipboard",
                                detail: macClip.created.map { "Mac · \(Date(timeIntervalSince1970: $0).formatted(.relative(presentation: .named)))" } ?? "From your Mac", titleLines: 2) {
                            if pending == macClip.id { ProgressView() }
                            else { Button("Copy") { Task { await take(macClip) } }.buttonStyle(.borderless) }
                        }
                        .lineLimit(2)
                    } else if inbox != nil {
                        TileRow(symbol: "doc.on.clipboard", title: "Nothing from your Mac yet",
                                detail: "Turn on sharing in Remote Access.")
                    }
                    Button { Task { await pasteFromPhone() } } label: {
                        TileRow(symbol: "iphone.and.arrow.forward", title: "Send phone clipboard", detail: "Puts what you copied here on the Mac") { if pending == "paste" { ProgressView() } }
                    }.tint(.primary)
                    Toggle("Copy Mac clipboard automatically", isOn: $autoClipboard).tint(.accentColor)
                } header: { Text("Clipboard") } footer: {
                    Text("When True opens, the newest text copied on your Mac goes straight to this phone's clipboard.")
                }
                Section {
                    Toggle("Send phone screenshots automatically", isOn: screenshotBinding).tint(.accentColor)
                } header: { Text("Screenshots") } footer: {
                    Text("While True is open, screenshots you take on this phone go straight to your Mac's screenshot tray.")
                }
                Section {
                    Toggle("Stay on duty", isOn: $onDuty).tint(.accentColor)
                } header: { Text("Lock screen") } footer: {
                    Text("True stays awake in the background so a pane that needs you reaches your lock screen within seconds. Uses some battery.")
                }
                Section {
                    ForEach((inbox ?? []).filter { $0.id != macClip?.id }) { item in
                        TileRow(symbol: symbol(item), title: item.kind == "text" ? "Clipboard" : item.name,
                                detail: item.preview ?? ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)) {
                            if pending == item.id { ProgressView() }
                            else { Button(item.kind == "text" ? "Copy" : "Save") { Task { await take(item) } }.buttonStyle(.borderless) }
                        }
                        .contentShape(.rect)
                        .onTapGesture { if item.kind != "text" { Task { await quickLook(item) } } }
                        .swipeActions { Button("Delete", role: .destructive) { Task { try? await model.session?.deleteInboxItem(id: item.id); await load() } } }
                    }
                } header: { Text("From your Mac") } footer: {
                    if let inbox, inbox.isEmpty { Text("Drop a file in True on the Mac to see it here.") }
                }
                Section("To your Mac") {
                    PhotosPicker(selection: $photo, matching: .images) {
                        TileRow(symbol: "photo.badge.plus", title: "Photo") { if pending == "photo" { ProgressView() } }
                    }.tint(.primary)
                    Button { importing = true } label: {
                        TileRow(symbol: "doc.badge.plus", title: "File") { if pending == "file" { ProgressView() } }
                    }.tint(.primary)
                }
                Section("Type for your Mac") {
                    TextField("Text for your Mac's clipboard", text: $clip, axis: .vertical).lineLimit(2...5)
                    HStack {
                        Spacer()
                        if pending == "clip" { ProgressView() } else { Button("Send") { Task { await sendClip() } }.buttonStyle(.borderless).disabled(clip.isEmpty) }
                    }
                }
            }
            .navigationTitle("Send")
            .toolbar { StartWorkButton() }
            .onChange(of: onDuty) { _, on in if on { Background.requestAuthorization() } }
            .refreshable { await load() }
            .task { await load() }
            .sensoryFeedback(.success, trigger: sent)
            .modifier(SendPickers(photo: $photo, importing: $importing, exported: $exported, preview: $preview,
                                  onPhoto: { item in Task { await sendPhoto(item) } }, onFile: { result in Task { await sendFile(result) } }))
        }
    }

    private func load() async {
        do { inbox = try await model.session?.inbox(); await model.applyMacClipboard(inbox) } catch { await model.handle(error); if inbox == nil { inbox = [] } }
    }

    private func fileURL(_ item: InboxItem) async -> URL? {
        guard let data = try? await model.session?.inboxData(id: item.id) else { model.show("Couldn't fetch that."); return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
        try? data.write(to: url)
        return url
    }

    private func quickLook(_ item: InboxItem) async {
        pending = item.id; defer { pending = nil }
        preview = await fileURL(item)
    }

    private func take(_ item: InboxItem) async {
        pending = item.id; defer { pending = nil }
        if item.kind == "text" {
            guard let data = try? await model.session?.inboxData(id: item.id) else { model.show("Couldn't fetch that."); return }
            UIPasteboard.general.string = String(decoding: data, as: UTF8.self); model.show("Copied"); sent += 1
        } else { exported = await fileURL(item) }
    }

    private func sendText(_ text: String, as key: String) async -> Bool {
        pending = key; defer { pending = nil }
        do { try await model.session?.clip(text: text); model.show("Sent to your Mac"); sent += 1; return true }
        catch { await model.handle(error); model.show("Couldn't send"); return false }
    }

    private func sendClip() async { if await sendText(clip, as: "clip") { clip = "" } }

    private func pasteFromPhone() async {
        guard let s = UIPasteboard.general.string, !s.isEmpty else { model.show("Couldn't paste — clipboard is empty"); return }
        _ = await sendText(s, as: "paste")
    }

    private func sendPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        pending = "photo"
        guard let data = try? await item.loadTransferable(type: Data.self) else { pending = nil; model.show("Couldn't read that photo"); photo = nil; return }
        await drop(data, "Photo-\(Int(Date().timeIntervalSince1970)).jpg", key: "photo"); photo = nil
    }

    private func sendFile(_ result: Result<URL, Error>) async {
        guard case .success(let url) = result, url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        pending = "file"
        guard let data = try? Data(contentsOf: url) else { pending = nil; model.show("Couldn't read that file"); return }
        await drop(data, url.lastPathComponent, key: "file")
    }

    private func drop(_ data: Data, _ name: String, key: String) async {
        pending = key; defer { pending = nil }
        do { _ = try await model.session?.drop(data, filename: name); model.show("Sent to your Mac"); sent += 1 }
        catch { await model.handle(error); model.show("Couldn't send") }
    }
}
