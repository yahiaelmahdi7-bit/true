import SwiftUI

/// The "fresh screenshot" slot for the tab bar. Nothing shows normally; when a new screenshot lands a
/// tiny thumbnail appears until the tray is opened or a shot is used. The slot's container is always
/// there (1pt wide when empty) so ⇧⌘S has somewhere to anchor the popover.
struct ScreenshotTray: View {
    private let watcher = ScreenshotWatcher.shared
    @State private var appeared = false

    var body: some View {
        @Bindable var w = watcher
        ZStack {
            if watcher.fresh, let shot = watcher.shots.first {
                Button { watcher.trayOpen.toggle() } label: {
                    ShotImage(shot: shot, fill: false)
                        .frame(height: 18)
                        .clipShape(.rect(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("New screenshot — ⇧⌘S")
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.85)
                .onAppear { withAnimation(.easeOut(duration: 0.2)) { appeared = true } }
                .onDisappear { appeared = false }
            }
        }
        .frame(width: watcher.fresh ? nil : 1, height: 18)
        .popover(isPresented: $w.trayOpen, arrowEdge: .bottom) { ScreenshotPopover() }
    }
}

/// A shot's cached thumbnail, generated off the main actor on first sight.
private struct ShotImage: View {
    let shot: ScreenshotWatcher.Shot
    let fill: Bool
    private let watcher = ScreenshotWatcher.shared

    var body: some View {
        Group {
            if let image = watcher.thumbnail(for: shot) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Color.white.opacity(0.06)
            }
        }
        .task(id: watcher.thumbKey(shot)) { await watcher.loadThumbnail(for: shot) }
    }
}

private struct ScreenshotPopover: View {
    private let watcher = ScreenshotWatcher.shared
    private let columns = Array(repeating: GridItem(.fixed(100), spacing: 10, alignment: .top), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if watcher.unreadable {
                unreadable
            } else if watcher.shots.isEmpty && watcher.clipboardImage == nil {
                empty
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    if let image = watcher.clipboardImage {
                        Tile(label: "Clipboard", hairline: 0.2) {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        } action: { watcher.pasteClipboard() }
                    }
                    ForEach(watcher.shots.prefix(watcher.clipboardImage == nil ? 9 : 8)) { shot in
                        FileTile(shot: shot)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(width: 344, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text("Screenshots").font(.callout.weight(.semibold))
            Text(watcher.folder.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button { NSWorkspace.shared.open(watcher.folder) } label: {
                Image(systemName: "folder").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Show in Finder")
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No screenshots yet").font(.callout).foregroundStyle(Theme.text)
            Text(watcher.folder.lastPathComponent).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var unreadable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("True can't read \(watcher.folder.lastPathComponent).").font(.callout).foregroundStyle(Theme.text)
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

/// Thumbnail + relative-time label; the hairline brightens on hover.
private struct Tile<Content: View>: View {
    let label: String
    var hairline: Double
    @ViewBuilder let content: Content
    let action: () -> Void
    @State private var hovering = false

    init(label: String, hairline: Double, @ViewBuilder content: () -> Content, action: @escaping () -> Void) {
        self.label = label; self.hairline = hairline; self.content = content(); self.action = action
    }

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Color.clear.frame(width: 100, height: 68)
                    .overlay { content }
                    .clipShape(.rect(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(hovering ? 0.5 : hairline), lineWidth: 0.5))
                    .contentShape(.rect(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            Text(label).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct FileTile: View {
    let shot: ScreenshotWatcher.Shot
    private let watcher = ScreenshotWatcher.shared

    var body: some View {
        Tile(label: ScreenshotWatcher.relativeLabel(for: shot.date, now: Date(), calendar: .current),
             hairline: 0.2) {
            ShotImage(shot: shot, fill: true)
        } action: { watcher.paste(shot) }
        .onDrag {
            watcher.markSeen()
            return NSItemProvider(contentsOf: shot.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shot.url.path, forType: .string)
            }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([shot.url]) }
            Button("Copy Image") {
                guard let image = NSImage(contentsOf: shot.url) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
        }
    }
}
