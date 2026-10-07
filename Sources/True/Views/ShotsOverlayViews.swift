import SwiftUI
import AppKit
import ImageIO

/// Behind-window blur of whatever is on the desktop under the overlay.
private struct BackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.material = .fullScreenUI
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct ShotsOverlayRoot: View {
    let controller: ShotsOverlayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var ns
    @State private var pinchBase: Int?

    private var c: ShotsOverlayController { controller }
    private var open: Bool { c.presented }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 16) {
                header
                shots
                DownloadsGlassStrip(controller: c)
            }
            .padding(.top, c.insets.top).padding(.leading, c.insets.leading)
            .padding(.bottom, c.insets.bottom).padding(.trailing, c.insets.trailing)

            if c.viewerID != nil {
                ShotViewer(controller: c, ns: ns, reduceMotion: reduceMotion)
            }
            if c.dropTargeted { dropHighlight }
            toast
        }
        .ignoresSafeArea()
        .opacity(open ? 1 : 0)
        .animation(open ? .easeOut(duration: 0.22) : .easeIn(duration: 0.18), value: open)
        .preferredColorScheme(.dark)
        .dropDestination(for: URL.self) { urls, _ in c.drop(urls) } isTargeted: { c.dropTargeted = $0 }
    }

    // MARK: Pieces

    private var backdrop: some View {
        Group {
            if reduceTransparency { Color(white: 0.06) } else {
                ZStack { BackdropBlur(); Color.black.opacity(0.28) }
            }
        }
        .contentShape(.rect)
        .onTapGesture { c.dismiss() }
    }

    private var header: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                Text("Shots").font(.title3.weight(.semibold))
                Text("\(c.entries.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                ActionButton(symbol: "folder", help: "Show \(c.watcher.folder.lastPathComponent) in Finder", bounceOnHover: true) {
                    NSWorkspace.shared.open(c.watcher.folder)
                }
                ActionButton(symbol: "xmark", help: "Close (Esc)") { c.dismiss() }
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
    }

    @ViewBuilder private var shots: some View {
        if c.entries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "camera.viewfinder").font(.system(size: 34)).foregroundStyle(.secondary)
                Text(c.watcher.unreadable ? "True can't read \(c.watcher.folder.lastPathComponent)" : "No screenshots yet")
                    .font(.title3)
                Text(c.watcher.unreadable ? "Allow access in Privacy Settings." : "New ones in \(c.watcher.folder.lastPathComponent) appear here — or drop images in.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
    }

    private var grid: some View {
        let groups = ShotsOverlayLogic.group(c.entries, now: Date(), calendar: .current)
        let order = Dictionary(uniqueKeysWithValues: c.entries.enumerated().map { ($1.id, $0) })
        let cols = Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .top), count: c.columns)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.title) { g in
                    Section {
                        LazyVGrid(columns: cols, spacing: 18) {
                            ForEach(g.entries) { e in
                                ShotTile(controller: c, entry: e, ns: ns, index: order[e.id] ?? 0, reduceMotion: reduceMotion)
                            }
                        }
                    } header: {
                        Text(g.title).font(.callout.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
            }
            .padding(.vertical, 4).padding(.horizontal, 2)
        }
        .scrollIndicators(.never)
        .simultaneousGesture(MagnifyGesture().onChanged { v in
            let base = pinchBase ?? c.columns
            pinchBase = base
            let n = ShotsOverlayLogic.columns(base: base, pinchScale: v.magnification)
            if n != c.columns { c.setColumns(n, persist: false) }
        }.onEnded { _ in
            pinchBase = nil
            UserDefaults.standard.set(c.columns, forKey: ShotsOverlayLogic.columnsKey)
        })
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
            .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 28, style: .continuous))
            .overlay {
                Label("Drop images to add", systemImage: "square.and.arrow.down")
                    .font(.title3.weight(.medium)).padding(.horizontal, 22).padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
            }
            .padding(14).allowsHitTesting(false).transition(.opacity)
    }

    @ViewBuilder private var toast: some View {
        if let text = c.toast {
            HStack(spacing: 12) {
                Text(text).font(.callout)
                if text == "Removed from tray" {
                    Button("Undo") { c.undoRemove() }.buttonStyle(.glass).controlSize(.small)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, c.insets.bottom + 120)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: 0.2), value: c.toast)
        }
    }
}

// MARK: - Tile

private struct ShotTile: View {
    let controller: ShotsOverlayController
    let entry: TrayEntry
    let ns: Namespace.ID
    let index: Int
    let reduceMotion: Bool
    @State private var hover: CGPoint?

    private var c: ShotsOverlayController { controller }
    private let maxTilt = 6.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let lifted = hover != nil
            let px: Double = Double(hover?.x ?? w / 2), py: Double = Double(hover?.y ?? h / 2)
            let tiltX: Double = -((py / Double(max(h, 1))) - 0.5) * 2 * maxTilt
            let tiltY: Double = ((px / Double(max(w, 1))) - 0.5) * 2 * maxTilt
            Group {
                if c.viewerID == entry.id {
                    Color.clear
                } else {
                    ThumbImage(entry: entry, fill: true)
                        .matchedGeometryEffect(id: entry.id, in: ns)
                }
            }
            .frame(width: w, height: h)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(lifted ? 0.4 : 0.14), lineWidth: 0.5))
            .overlay(alignment: .topTrailing) {
                if entry.kind == .markup {
                    Image(systemName: "pencil.tip").font(.system(size: 10, weight: .bold)).padding(5)
                        .glassEffect(.regular, in: .circle).padding(8)
                }
            }
            .scaleEffect(lifted ? 1.04 : 1)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : tiltX), axis: (1, 0, 0), perspective: 0.6)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : tiltY), axis: (0, 1, 0), perspective: 0.6)
            .shadow(color: .black.opacity(lifted ? 0.45 : 0.18), radius: lifted ? 18 : 6, y: lifted ? 10 : 3)
            .animation(.spring(duration: 0.25, bounce: 0.15), value: lifted)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.8), value: hover?.x)
            .contentShape(.rect)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hover = p; c.hoveredID = entry.id
                case .ended: hover = nil; if c.hoveredID == entry.id { c.hoveredID = nil }
                }
            }
            .onTapGesture { c.openViewer(entry.id) }
            .onDrag { fileProvider(c.watcher.fileURL(for: entry)) }
        }
        .aspectRatio(1.6, contentMode: .fit)
        .scaleEffect(c.presented || reduceMotion ? 1 : 0.9)
        .opacity(c.presented ? 1 : 0)
        .animation(c.presented
                   ? (reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0.18).delay(Double(min(index, 10)) * 0.02))
                   : .easeIn(duration: 0.18), value: c.presented)
        .zIndex(hover != nil ? 1 : 0)
    }
}

// MARK: - Viewer

private struct ShotViewer: View {
    let controller: ShotsOverlayController
    let ns: Namespace.ID
    let reduceMotion: Bool
    @State private var full: CGImage?
    private var c: ShotsOverlayController { controller }

    private var entry: TrayEntry? { c.viewerID.flatMap { id in c.entries.first { $0.id == id } } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).contentShape(.rect).onTapGesture { if !c.markingUp { c.closeViewer() } }
            if let entry {
                VStack(spacing: 16) {
                    Group {
                        if c.markingUp, let full {
                            MarkupEditor(controller: c, watcher: c.watcher, entry: entry, image: full)
                                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        } else {
                            picture(entry)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !c.markingUp { toolbar(entry) }
                }
                .padding(.top, c.insets.top).padding(.horizontal, c.insets.leading + 40)
                .padding(.bottom, c.insets.bottom)
                .task(id: entry.id) {
                    let u = c.watcher.fileURL(for: entry)
                    full = await Task.detached { () -> CGImage? in
                        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
                        return CGImageSourceCreateImageAtIndex(src, 0, nil)
                    }.value
                }
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder private func picture(_ entry: TrayEntry) -> some View {
        let slideEdge: Edge = c.slide >= 0 ? .trailing : .leading
        let content = ZStack {
            if let full {
                Image(decorative: full, scale: 1).resizable().aspectRatio(contentMode: .fit)
            } else {
                ThumbImage(entry: entry, fill: false)
            }
        }
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        .onDrag { fileProvider(c.watcher.fileURL(for: entry)) }
        .id(entry.id)
        if c.detached {
            content.transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: slideEdge).combined(with: .opacity),
                removal: .move(edge: slideEdge == .trailing ? .leading : .trailing).combined(with: .opacity)))
        } else {
            content.matchedGeometryEffect(id: entry.id, in: ns)
        }
    }

    private func toolbar(_ entry: TrayEntry) -> some View {
        let url = c.watcher.fileURL(for: entry)
        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 6) {
                ActionButton(symbol: "chevron.left", help: "Previous (←)") { c.step(-1) }
                    .disabled(c.viewerIndex == 0)
                ActionButton(symbol: "chevron.right", help: "Next (→)") { c.step(1) }
                    .disabled(c.viewerIndex == c.entries.count - 1)
                Divider().frame(height: 18).padding(.horizontal, 4)
                ActionButton(symbol: "paperplane", help: "Send to session", flies: true) { c.send(entry) }
                ActionButton(symbol: "doc.on.doc", doneSymbol: "checkmark", help: "Copy image") {
                    guard let image = NSImage(contentsOf: url) else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
                ActionButton(symbol: "pencil.tip.crop.circle", help: "Mark up") { c.markingUp = true; c.makeKey() }
                ActionButton(symbol: "folder", help: "Show in Finder", bounceOnHover: true) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                ActionButton(symbol: "trash", help: "Remove from tray (the original file stays)") { c.delete(entry) }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
        }
    }
}

// MARK: - Downloads strip

private struct DownloadsGlassStrip: View {
    let controller: ShotsOverlayController
    private var d: DownloadsWatcher { controller.downloads }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Downloads").font(.callout.weight(.semibold))
                    Text("\(d.items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if d.unreadable {
                    Text("True can't read Downloads.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                } else if d.items.isEmpty {
                    Text("No recent downloads").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) { ForEach(d.items) { DownloadChip(controller: controller, item: $0) } }
                    }
                    .scrollIndicators(.never)
                }
                ActionButton(symbol: "folder", help: "Show Downloads in Finder", bounceOnHover: true) {
                    NSWorkspace.shared.open(d.directory)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .frame(height: 64)
            .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        }
        .opacity(controller.presented ? 1 : 0)
        .offset(y: controller.presented ? 0 : 14)
        .animation(.easeOut(duration: 0.28).delay(controller.presented ? 0.08 : 0), value: controller.presented)
    }
}

private struct DownloadChip: View {
    let controller: ShotsOverlayController
    let item: DownloadItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 28, height: 28)
            Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle).frame(maxWidth: 150, alignment: .leading)
            ActionButton(symbol: "paperplane", help: "Send to session", flies: true) { controller.sendPath(item.url) }
            ActionButton(symbol: "link", doneSymbol: "checkmark", help: "Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
        }
        .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 4)
        .background(.white.opacity(hovering ? 0.10 : 0.05), in: .rect(cornerRadius: 14, style: .continuous))
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(duration: 0.2), value: hovering)
        .onHover { hovering = $0 }
        .onDrag { fileProvider(item.url) }
    }
}

// MARK: - Living icon button

/// A glass icon button with a symbol effect: bounce on hover (folder), a done-symbol morph for ~1.2 s
/// (copy → checkmark), or a bounce-then-fly-off (send).
struct ActionButton: View {
    let symbol: String
    var doneSymbol: String?
    let help: String
    var bounceOnHover = false
    var flies = false
    let action: () -> Void
    @State private var done = false
    @State private var bounce = 0
    @State private var gone = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            action()
            if flies && !reduceMotion {
                bounce += 1
                withAnimation(.easeIn(duration: 0.22).delay(0.05)) { gone = true }
            } else if doneSymbol != nil {
                done = true
                Task { try? await Task.sleep(for: .milliseconds(1200)); done = false }
            }
        } label: {
            Image(systemName: done ? (doneSymbol ?? symbol) : symbol)
                .font(.system(size: 14, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: bounce)
                .frame(width: 22, height: 22)
                .offset(x: gone ? 26 : 0, y: gone ? -26 : 0)
                .opacity(gone ? 0 : 1)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .onHover { if $0 && bounceOnHover && !reduceMotion { bounce += 1 } }
        .help(help)
        .accessibilityLabel(help)
    }
}
