import SwiftUI
import UIKit

/// One thing the user picked for a pane prompt. Phone state until Send; the Mac only sees it once the
/// prompt is delivered (the upload just parks the file in the tray / Downloads).
struct PaneAttachment: Identifiable {
    enum Status: Equatable {
        case uploading
        case ready(PaneAttachmentRef)
        case failed(String)
    }
    let id = UUID()
    var label: String
    var thumbnail: UIImage?
    var status: Status
    /// Kept only while uploading / failed so a tap can retry; dropped once the Mac has it.
    var payload: Data?

    var planStatus: AttachmentPlan.Status {
        switch status {
        case .uploading: .uploading
        case .ready: .ready
        case .failed: .failed
        }
    }
    var ref: PaneAttachmentRef? { if case .ready(let r) = status { r } else { nil } }
}

extension AppModel {
    func attachments(for pane: String) -> [PaneAttachment] { paneAttachments[pane] ?? [] }

    /// Start uploading `data` as `name`. Returns false (after a toast) when over the count or size cap.
    @discardableResult
    func attach(_ data: Data, name: String, pane: String, thumbnail: UIImage?) -> Bool {
        guard AttachmentPlan.room(current: attachments(for: pane).count) > 0 else { show("Up to 8 attachments"); return false }
        guard AttachmentPlan.withinCap(bytes: data.count) else { show("\(name) is over 200 MB"); return false }
        let item = PaneAttachment(label: name, thumbnail: thumbnail, status: .uploading, payload: data)
        paneAttachments[pane, default: []].append(item)
        upload(item.id, pane: pane)
        return true
    }

    func upload(_ id: UUID, pane: String) {
        guard let item = attachments(for: pane).first(where: { $0.id == id }), let data = item.payload, let session else { return }
        update(id, pane: pane) { $0.status = .uploading }
        Task { @MainActor in
            do {
                let r = try await session.drop(data, filename: item.label)
                guard let ref = PaneAttachmentRef(drop: r) else { throw RemoteError.badResponse }
                update(id, pane: pane) { $0.status = .ready(ref); $0.payload = nil }
            } catch {
                if case RemoteError.unauthorized = error { await unpair() }
                update(id, pane: pane) { $0.status = .failed("Couldn't upload") }
                show("Couldn't upload \(item.label)")
            }
        }
    }

    func removeAttachment(_ id: UUID, pane: String) { paneAttachments[pane]?.removeAll { $0.id == id } }

    /// A tray shot already on the Mac: nothing to upload.
    func attachShot(_ shot: Shot, thumbnail: UIImage?, pane: String) {
        guard AttachmentPlan.room(current: attachments(for: pane).count) > 0 else { show("Up to 8 attachments"); return }
        paneAttachments[pane, default: []].append(PaneAttachment(label: "Screenshot", thumbnail: thumbnail, status: .ready(.shot(id: shot.id))))
    }

    private func update(_ id: UUID, pane: String, _ change: (inout PaneAttachment) -> Void) {
        guard let i = paneAttachments[pane]?.firstIndex(where: { $0.id == id }) else { return }
        change(&paneAttachments[pane]![i])
    }

    /// Turn picked bytes into an attachment: HEIC & friends become JPEG 0.9; PNG/JPEG go as-is; anything that
    /// is not an image (video) goes up untouched with its own extension.
    func attachPicked(_ data: Data, ext: String, index: Int, pane: String) {
        var payload = data
        var thumb: UIImage?
        if let img = UIImage(data: data) {
            thumb = img.preparingThumbnail(of: CGSize(width: 120, height: 120))
            if ScreenshotPlan.needsJPEGConversion(data), let jpg = img.jpegData(compressionQuality: 0.9) { payload = jpg }
        }
        let name = AttachmentPlan.filename(for: .photo(ext: thumb == nil ? ext : "jpg", index: index), now: Date())
        attach(payload, name: name, pane: pane, thumbnail: thumb)
    }

    func attachCamera(_ image: UIImage, pane: String) {
        guard let jpg = image.jpegData(compressionQuality: 0.9) else { show("Couldn't read that photo"); return }
        let n = attachments(for: pane).count + 1
        attach(jpg, name: AttachmentPlan.filename(for: .camera(index: n), now: Date()), pane: pane,
               thumbnail: image.preparingThumbnail(of: CGSize(width: 120, height: 120)))
    }

    func attachFile(_ url: URL, pane: String) {
        guard url.startAccessingSecurityScopedResource() else { show("Couldn't read \(url.lastPathComponent)"); return }
        defer { url.stopAccessingSecurityScopedResource() }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard AttachmentPlan.withinCap(bytes: size) else { show("\(url.lastPathComponent) is over 200 MB"); return }
        guard let data = try? Data(contentsOf: url) else { show("Couldn't read \(url.lastPathComponent)"); return }
        let thumb = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 120, height: 120))
        attach(data, name: AttachmentPlan.filename(for: .file(name: url.lastPathComponent), now: Date()), pane: pane, thumbnail: thumb)
    }
}

/// The system camera, one shot at a time.
struct CameraPicker: UIViewControllerRepresentable {
    let onShot: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onShot(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
