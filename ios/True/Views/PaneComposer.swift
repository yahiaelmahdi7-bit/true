import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// In-flight state and the send/react flow for the pane composer. The draft itself lives in AppModel
/// (per pane, in memory) so it survives leaving and re-entering the pane.
@MainActor @Observable
final class PaneComposer {
    /// nil until /api/tabs answers; the Hub row is the fallback.
    var claude: Bool?
    var inFlight = false
    /// The one-slot "last sent" buffer, so a failed send can put the words back.
    private(set) var lastSent = ""

    func send(_ intent: PaneInputIntent, paneId: String, draft: Binding<String>, model: AppModel, onGone: @escaping () -> Void) {
        guard !inFlight, let session = model.session else { return }
        var text = ""
        var refs: [PaneAttachmentRef] = []
        if intent == .prompt {
            let items = model.attachments(for: paneId)
            text = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard AttachmentPlan.canSend(text: text, attachments: items.map(\.planStatus)) else { return }
            refs = items.compactMap(\.ref)
            lastSent = text
            draft.wrappedValue = ""          // optimistic: the field clears at once
        }
        inFlight = true
        Task { @MainActor in
            defer { inFlight = false }
            @MainActor func restore() {
                guard intent == .prompt else { return }
                let now = draft.wrappedValue
                draft.wrappedValue = now.isEmpty ? lastSent : lastSent + "\n" + now
            }
            do {
                let outcome = try await session.paneInput(id: paneId, intent: intent, text: text, attachments: refs)
                let sentIds = Set(model.attachments(for: paneId).filter { $0.ref != nil }.map(\.id))
                @MainActor func clearChips() { model.paneAttachments[paneId]?.removeAll { sentIds.contains($0.id) } }
                switch outcome.reaction(for: intent) {
                case .nothing: clearChips()
                case .toast(let t): clearChips(); model.show(t)
                case .restore(let t): restore(); model.show(t)
                case .popPane(let t): model.show(t); onGone()
                }
            } catch RemoteError.paneGone {
                model.show("Pane is gone"); onGone()
            } catch RemoteError.unauthorized {
                await model.unpair()
            } catch {
                restore()
                model.show("Couldn't reach the Mac — your text is still here")
            }
        }
    }
}

/// Native prompt composer docked above the keyboard. Glass on controls only; blue = interactive.
struct ComposerBar: View {
    @Binding var draft: String
    let composer: PaneComposer
    let isClaude: Bool
    var focused: FocusState<Bool>.Binding
    let paneId: String
    let attachments: [PaneAttachment]
    let onKeys: () -> Void
    let onSend: () -> Void
    let onKey: ([UInt8]) -> Void
    let onIntent: (PaneInputIntent) -> Void
    @Environment(AppModel.self) private var model
    @ScaledMetric private var hit = 44
    @State private var pickingPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pickingFiles = false
    @State private var takingPhoto = false

    private var canSend: Bool {
        !composer.inFlight && AttachmentPlan.canSend(text: draft, attachments: attachments.map(\.planStatus))
    }

    var body: some View {
        VStack(spacing: 8) {
            keyRow
            if !attachments.isEmpty { chipRow }
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: onKeys) { Label("Keys", systemImage: "terminal").labelStyle(.iconOnly).frame(width: hit, height: hit) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityLabel("Keys")
                    .accessibilityHint("Type straight into the terminal")
                if !composer.inFlight { attachMenu }
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused(focused)
                    .submitLabel(.send)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(minHeight: hit)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityLabel("Prompt")
                Button(action: onSend) {
                    ZStack {
                        if composer.inFlight { ProgressView().tint(.white) }
                        else { Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundStyle(.white) }
                    }
                    .frame(width: hit, height: hit)
                    .background(Circle().fill(Color.accentColor))
                    .opacity(canSend || composer.inFlight ? 1 : 0.35)
                }
                .disabled(!canSend)
                .accessibilityLabel(composer.inFlight ? "Sending" : "Send")
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    private var attachMenu: some View {
        Menu {
            Button { pickingPhotos = true } label: { Label("Photo library", systemImage: "photo.on.rectangle") }
            if CameraPicker.available { Button { takingPhoto = true } label: { Label("Take photo", systemImage: "camera") } }
            Button { pickingFiles = true } label: { Label("Files", systemImage: "folder") }
        } label: { Image(systemName: "plus").font(.body.weight(.semibold)).frame(width: hit, height: hit) }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .accessibilityLabel("Attach")
            .photosPicker(isPresented: $pickingPhotos, selection: $photoItems,
                          maxSelectionCount: max(1, AttachmentPlan.room(current: attachments.count)), matching: .any(of: [.images, .videos]))
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await load(items) }
            }
            .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls { model.attachFile(url, pane: paneId) }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { model.attachCamera($0, pane: paneId) }.ignoresSafeArea()
            }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        for (i, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { model.show("Couldn't read that photo"); continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            model.attachPicked(data, ext: ext, index: model.attachments(for: paneId).count + i + 1, pane: paneId)
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { chip($0) }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(_ a: PaneAttachment) -> some View {
        let failed: Bool = { if case .failed = a.status { true } else { false } }()
        return HStack(spacing: 6) {
            if let t = a.thumbnail { Image(uiImage: t).resizable().scaledToFill().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6)) }
            else { Image(systemName: "doc").frame(width: 28, height: 28) }
            Text(failed ? "Couldn't upload" : a.label).font(.footnote).lineLimit(1).frame(maxWidth: 110, alignment: .leading)
            if a.status == .uploading { ProgressView().controlSize(.small) }
            Button { model.removeAttachment(a.id, pane: paneId) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 32, height: 32)
            }.accessibilityLabel("Remove \(a.label)")
        }
        .padding(.leading, 8)
        .foregroundStyle(failed ? Color.orange : Color.primary)
        .background(.thinMaterial, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { if failed { model.upload(a.id, pane: paneId) } }
        .accessibilityElement(children: .contain)
    }

    private var keyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                key("esc", label: "Escape") { onKey([0x1b]) }
                key(symbol: "arrow.up", label: "Up") { onKey([0x1b, 0x5b, 0x41]) }
                key(symbol: "arrow.down", label: "Down") { onKey([0x1b, 0x5b, 0x42]) }
                key(symbol: "return", label: "Return") { onIntent(.submitOnly) }
                key("⌃C", label: "Control C") { onKey([0x03]) }
                if isClaude {
                    key("Approve", label: "Approve", tint: .accentColor) { onIntent(.approve) }
                    key("Deny", label: "Deny") { onIntent(.deny) }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func key(_ title: String? = nil, symbol: String? = nil, label: String, tint: Color? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let symbol { Image(systemName: symbol) } else { Text(title ?? "") }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12).frame(minWidth: hit, minHeight: hit)
        }
        .buttonStyle(.glass)
        .tint(tint)
        .accessibilityLabel(label)
    }
}
