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

    private func symbol(_ item: InboxItem) -> String {
        if item.kind == "text" { return "doc.on.clipboard" }
        let ext = (item.name as NSString).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "gif", "webp"].contains(ext) { return "photo" }
        if ["zip", "gz", "tar", "tgz"].contains(ext) { return "zipper" }
        return "doc"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(inbox ?? []) { item in
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
                    if let inbox, inbox.isEmpty { Text("Copy something on the Mac or drop a file in True to see it here.") }
                }
                Section("To your Mac") {
                    PhotosPicker(selection: $photo, matching: .images) {
                        TileRow(symbol: "photo.badge.plus", title: "Photo") { if pending == "photo" { ProgressView() } }
                    }.tint(.primary)
                    Button { importing = true } label: {
                        TileRow(symbol: "doc.badge.plus", title: "File") { if pending == "file" { ProgressView() } }
                    }.tint(.primary)
                    Button { Task { await pasteFromPhone() } } label: {
                        TileRow(symbol: "doc.on.clipboard", title: "Paste", detail: "Send what's on this phone's clipboard") { if pending == "paste" { ProgressView() } }
                    }.tint(.primary)
                }
                Section("Clipboard") {
                    TextField("Text for your Mac's clipboard", text: $clip, axis: .vertical).lineLimit(2...5)
                    HStack {
                        Spacer()
                        if pending == "clip" { ProgressView() } else { Button("Send") { Task { await sendClip() } }.buttonStyle(.borderless).disabled(clip.isEmpty) }
                    }
                }
            }
            .navigationTitle("Send")
            .toolbar { StartWorkButton() }
            .refreshable { await load() }
            .task { await load() }
            .sensoryFeedback(.success, trigger: sent)
            .modifier(SendPickers(photo: $photo, importing: $importing, exported: $exported, preview: $preview,
                                  onPhoto: { item in Task { await sendPhoto(item) } }, onFile: { result in Task { await sendFile(result) } }))
        }
    }

    private func load() async {
        do { inbox = try await model.session?.inbox() } catch { await model.handle(error); if inbox == nil { inbox = [] } }
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
