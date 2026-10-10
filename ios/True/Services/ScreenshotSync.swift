import Foundation
import Photos
import UIKit
import Observation

/// Sends screenshots taken on this phone to the Mac's screenshot tray (`POST /api/drop`, the same door as the Send tab).
///
/// Honest limits: iOS does not deliver Photos changes to a backgrounded app and True has no background mode for it,
/// so "auto" means instant while True is open, plus a catch-up the moment it returns to the foreground. Only
/// screenshots newer than the moment the toggle was switched on are sent, oldest first. The share sheet stays the
/// path for everything else.
@MainActor @Observable
final class ScreenshotSync: NSObject, PHPhotoLibraryChangeObserver {
    private weak var model: AppModel?
    private var observing = false
    private var running = false
    private var again = false
    private var seen: Set<String> = []

    func attach(_ model: AppModel) { self.model = model }

    /// Pure planning, forwarded so the rule lives next to its callers (tested in TrueRemoteClientTests).
    nonisolated static func plan(assets: [(id: String, created: Date)], lastSynced: Date?, seen: Set<String>) -> [String] {
        ScreenshotPlan.plan(assets: assets, lastSynced: lastSynced, seen: seen)
    }

    /// Asks for Photos read access (limited counts). Called only when the toggle is first turned on.
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static var hasAccess: Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return s == .authorized || s == .limited
    }

    /// Toggle switched on (or app launched with it on): arm the cursor, start watching, catch up.
    func start() {
        guard Self.hasAccess else { return }
        if SharedConfig.screenshotLastSynced == nil { SharedConfig.screenshotLastSynced = Date() }
        if !observing { PHPhotoLibrary.shared().register(self); observing = true }
        Task { await catchUp() }
    }

    /// Toggle off: stop watching and forget the cursor, so re-enabling never floods the Mac with old shots.
    func stop() {
        if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self); observing = false }
        SharedConfig.screenshotLastSynced = nil
        seen = []
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in await self.catchUp() }
    }

    /// Upload every screenshot newer than the cursor. A failure stops the batch and leaves the cursor so the next try resumes.
    func catchUp() async {
        guard observing, Self.hasAccess, let model, let session = model.session else { return }
        if running { again = true; return }
        running = true
        defer { running = false }
        repeat {
            again = false
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let result = PHAsset.fetchAssets(with: .image, options: opts)
            var assets: [PHAsset] = []
            result.enumerateObjects { a, _, _ in assets.append(a) }
            let ids = Self.plan(assets: assets.compactMap { a in a.creationDate.map { (a.localIdentifier, $0) } },
                                lastSynced: SharedConfig.screenshotLastSynced, seen: seen)
            guard !ids.isEmpty else { continue }
            var sent = 0, failed = false
            for id in ids {
                guard let asset = assets.first(where: { $0.localIdentifier == id }), let created = asset.creationDate else { continue }
                do {
                    guard let (data, ext) = await Self.bytes(of: asset) else { throw CocoaError(.fileReadUnknown) }
                    _ = try await session.drop(data, filename: ScreenshotPlan.filename(created: created, ext: ext))
                    seen.insert(id)
                    SharedConfig.screenshotLastSynced = created
                    sent += 1
                } catch { failed = true; break }
            }
            if UIApplication.shared.applicationState == .active {
                if failed { model.show("Couldn't send screenshot") }
                else if sent > 0 { model.show("Screenshot sent to your Mac") }
            }
            if failed { return }
        } while again
    }

    /// Original bytes; HEIC and friends become JPEG 0.9 so the Mac tray can always read them.
    private static func bytes(of asset: PHAsset) async -> (Data, String)? {
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        opts.version = .current
        let data: Data? = await withCheckedContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, _ in cont.resume(returning: data) }
        }
        guard let data else { return nil }
        switch ScreenshotPlan.format(of: data) {
        case .png: return (data, "png")
        case .jpeg: return (data, "jpg")
        case .other:
            guard let jpg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) else { return nil }
            return (jpg, "jpg")
        }
    }
}
