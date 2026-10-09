import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

struct SendView: View {
    @Environment(AppModel.self) private var model
    @State private var inbox: [InboxItem]?
    @State private var clip = ""
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var exported: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("From your Mac") {
                    if let inbox, inbox.isEmpty { Text("Nothing sent from the Mac yet.").foregroundStyle(.secondary) }
                    ForEach(inbox ?? []) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).lineLimit(1)
                                Text(item.preview ?? ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button(item.kind == "text" ? "Copy" : "Save") { Task { await take(item) } }.buttonStyle(.borderless)
                        }
                        .swipeActions { Button("Delete", role: .destructive) { Task { try? await model.session?.deleteInboxItem(id: item.id); await load() } } }
                    }
                }
                Section("To your Mac") {
                    PhotosPicker(selection: $photo, matching: .images) { Label("Photo", systemImage: "photo") }
                    Button { importing = true } label: { Label("File", systemImage: "doc") }
                }
                Section("Clipboard") {
                    TextField("Text for your Mac's clipboard", text: $clip, axis: .vertical).lineLimit(2...5)
                    Button("Send") { Task { await sendClip() } }.disabled(clip.isEmpty)
                }
            }
            .navigationTitle("Send")
            .toolbar { StartWorkButton() }
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: photo) { _, item in Task { await sendPhoto(item) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in Task { await sendFile(result) } }
            .sheet(item: $exported) { ShareSheet(items: [$0]) }
        }
    }

    private func load() async {
        do { inbox = try await model.session?.inbox() } catch { await model.handle(error); if inbox == nil { inbox = [] } }
    }

    private func take(_ item: InboxItem) async {
        guard let data = try? await model.session?.inboxData(id: item.id) else { model.show("Couldn't fetch that."); return }
        if item.kind == "text" { UIPasteboard.general.string = String(decoding: data, as: UTF8.self); model.show("Copied.") }
        else {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
            try? data.write(to: url); exported = url
        }
    }

    private func sendClip() async {
        do { try await model.session?.clip(text: clip); clip = ""; model.show("Sent to your Mac.") } catch { await model.handle(error); model.show("Couldn't send.") }
    }

    private func sendPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        await drop(data, "Photo-\(Int(Date().timeIntervalSince1970)).jpg"); photo = nil
    }

    private func sendFile(_ result: Result<URL, Error>) async {
        guard case .success(let url) = result, url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { model.show("Couldn't read that file."); return }
        await drop(data, url.lastPathComponent)
    }

    private func drop(_ data: Data, _ name: String) async {
        do { _ = try await model.session?.drop(data, filename: name); model.show("Sent \(name).") } catch { await model.handle(error); model.show("Couldn't send.") }
    }
}
