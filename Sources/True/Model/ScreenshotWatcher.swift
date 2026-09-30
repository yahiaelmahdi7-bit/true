import AppKit
import ImageIO
import Observation

/// Watches the screenshot folder so the tab bar can show "a new screenshot landed" and the tray can
/// list the latest few. Event-driven only: one kqueue vnode source on the folder, no timers, and the
/// pasteboard is read once per tray open, never polled.
@MainActor @Observable
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()

    struct Shot: Identifiable, Equatable, Sendable {
        let url: URL
        let date: Date
        var id: String { url.path }
    }

    /// One directory entry, reduced to what selection needs — so `select` is testable without disk.
    struct Entry: Sendable {
        var name: String
        var url: URL
        var date: Date
        var isRegularFile: Bool
        var isScreenCaptureFlag: Bool
    }

    nonisolated static let limit = 9
    static let lastSeenKey = "screenshotTray.lastSeen"

    private(set) var shots: [Shot] = []
    private(set) var fresh = false
    private(set) var folder: URL
    private(set) var unreadable = false
    private(set) var clipboardImage: NSImage?
    private(set) var thumbnails: [String: NSImage] = [:]

    var trayOpen = false {
        didSet { if trayOpen && !oldValue { trayOpened() } }
    }

    private var lastSeen: Date?
    private var source: DispatchSourceFileSystemObject?
    private var watchedFolder: URL?
    private var debounce: Task<Void, Never>?
    private var loading: Set<String> = []

    private init() {
        folder = Self.currentFolder()
        let d = UserDefaults.standard
        if let seen = d.object(forKey: Self.lastSeenKey) as? Date {
            lastSeen = seen
        } else {
            // First ever run: whatever is already on disk is old news, never "fresh".
            let now = Date()
            lastSeen = now
            d.set(now, forKey: Self.lastSeenKey)
        }
    }

    // MARK: - Pure logic

    nonisolated static func isScreenshotName(_ name: String) -> Bool {
        name.hasPrefix("Screenshot ") || name.hasPrefix("Screen Shot ")
    }

    nonisolated static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif"]

    nonisolated static func isImageFile(_ name: String) -> Bool {
        imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Screenshots only, newest first, at most `limit`. macOS writes `.Screenshot…` temp files and
    /// renames them, so hidden names are skipped; the xattr flag covers non-English macOS.
    nonisolated static func select(_ entries: [Entry], limit: Int) -> [Shot] {
        entries
            .filter { e in
                !e.name.hasPrefix(".") && e.isRegularFile && isImageFile(e.name)
                    && (isScreenshotName(e.name) || e.isScreenCaptureFlag)
            }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { Shot(url: $0.url, date: $0.date) }
    }

    /// With no `lastSeen` we cannot tell, so nothing counts as fresh.
    nonisolated static func isFresh(newest: Date?, lastSeen: Date?) -> Bool {
        guard let newest, let lastSeen else { return false }
        return newest > lastSeen
    }

    /// The `location` default: nil/empty → ~/Desktop; `~` expanded; a trailing slash tolerated.
    nonisolated static func folder(fromDefaultsValue value: String?, home: URL) -> URL {
        guard var s = value?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return home.appendingPathComponent("Desktop", isDirectory: true)
        }
        if s == "~" { s = home.path } else if s.hasPrefix("~/") { s = home.path + "/" + s.dropFirst(2) }
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return URL(fileURLWithPath: s, isDirectory: true)
    }

    /// "now", "2m", "1h", "Yesterday", else a short date ("Sep 3").
    nonisolated static func relativeLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        let secs = now.timeIntervalSince(date)
        if secs < 60 { return "now" }
        if secs < 3600 { return "\(Int(secs / 60))m" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(secs / 3600))h" }
        if calendar.date(byAdding: .day, value: -1, to: now).map({ calendar.isDate(date, inSameDayAs: $0) }) == true { return "Yesterday" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }

    // MARK: - Disk (off the main actor)

    nonisolated static func currentFolder() -> URL {
        let value = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return folder(fromDefaultsValue: value, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    nonisolated static func hasScreenCaptureFlag(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }

    /// nil when the folder cannot be listed (privacy denied, or gone).
    nonisolated static func scan(_ folder: URL) -> [Shot]? {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        let entries = urls.compactMap { url -> Entry? in
            let name = url.lastPathComponent
            guard isImageFile(name), let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return Entry(name: name, url: url,
                         date: v.creationDate ?? v.contentModificationDate ?? .distantPast,
                         isRegularFile: v.isRegularFile ?? false,
                         isScreenCaptureFlag: isScreenshotName(name) ? false : hasScreenCaptureFlag(url))
        }
        return select(entries, limit: limit)
    }

    nonisolated static func makeThumbnail(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 240,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    // MARK: - Watching

    /// Launch side effect: one kqueue watch on the screenshot folder. It costs 0% CPU when idle and is
    /// what makes "fresh" possible. It does not scan; the first event or tray open does.
    func start() {
        folder = Self.currentFolder()
        startWatch()
    }

    private func startWatch() {
        source?.cancel()
        source = nil
        watchedFolder = nil
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { unreadable = true; return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        watchedFolder = folder
    }

    private func folderChanged() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.rescan()
        }
    }

    private func trayOpened() {
        let now = Self.currentFolder()
        if now != folder { folder = now }
        if watchedFolder != folder || source == nil { startWatch() }
        clipboardImage = Self.readClipboardImage()
        markSeen()
        Task { await rescan() }
    }

    private static func readClipboardImage() -> NSImage? {
        let pb = NSPasteboard.general
        guard let types = pb.types, types.contains(.png) || types.contains(.tiff) else { return nil }
        return NSImage(pasteboard: pb)
    }

    private func rescan() async {
        let dir = folder
        let result = await Task.detached { Self.scan(dir) }.value
        guard dir == folder else { return }
        apply(result)
    }

    private func apply(_ result: [Shot]?) {
        guard let result else { unreadable = true; shots = []; fresh = false; return }
        unreadable = false
        shots = result
        let live = Set(result.map(thumbKey))
        thumbnails = thumbnails.filter { live.contains($0.key) }
        fresh = trayOpen ? false : Self.isFresh(newest: result.first?.date, lastSeen: lastSeen)
        if trayOpen { markSeen() }
    }

    func markSeen() {
        let seen = max(shots.first?.date ?? .distantPast, Date())
        lastSeen = seen
        UserDefaults.standard.set(seen, forKey: Self.lastSeenKey)
        fresh = false
    }

    // MARK: - Thumbnails

    func thumbKey(_ shot: Shot) -> String { "\(shot.url.path)|\(shot.date.timeIntervalSince1970)" }

    func thumbnail(for shot: Shot) -> NSImage? { thumbnails[thumbKey(shot)] }

    func loadThumbnail(for shot: Shot) async {
        let key = thumbKey(shot)
        guard thumbnails[key] == nil, loading.insert(key).inserted else { return }
        let url = shot.url
        let image = await Task.detached { () -> NSImage? in
            guard let cg = Self.makeThumbnail(url) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        loading.remove(key)
        if let image { thumbnails[key] = image }
    }

    // MARK: - Using a shot

    func paste(_ shot: Shot) { paste(path: TerminalDrop.pastePath(for: shot.url)) }

    func pasteClipboard() {
        guard let image = clipboardImage, let url = TerminalDrop.writePNG(image) else { return }
        paste(path: url.path)
    }

    /// ⌥⌘V: the newest file screenshot, exactly like a tile click. No-op if there is none.
    func pasteLatest() {
        if shots.isEmpty { apply(Self.scan(folder)) }   // nothing scanned yet: one small listing
        guard let shot = shots.first else { return }
        paste(shot)
    }

    private func paste(path: String) {
        markSeen()
        trayOpen = false
        let pane = WorkspaceModel.shared.selectedTab.focusedPane
        guard let view = TerminalRegistry.shared.view(for: pane) else { return }
        view.pasteText(TerminalDrop.pasteText(forPaths: [path]))
        view.window?.makeFirstResponder(view)
        WorkspaceModel.shared.focus(pane: pane)
    }
}
