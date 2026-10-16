import SwiftUI
import UIKit

/// Owns the socket to True Chrome on the Mac: latest frame, tabs, and input senders.
@Observable @MainActor
final class BrowserModel {
    var frame: UIImage?
    var viewport = CGSize(width: 390, height: 844)
    var tabs = BrowserTabs(tabs: [])
    var failure: String?
    var fps = 0
    var latencyMs = 0

    private var socket: BrowserSocket?
    private var loop: Task<Void, Never>?
    private var frameCount = 0
    private var windowStart = Date()
    private var lastSize = CGSize.zero

    func start(session: RemoteSession?) {
        guard loop == nil, let session else { return }
        loop = Task { [weak self] in
            var backoff = 1.0
            while !Task.isCancelled {
                guard let token = await session.currentToken(), let sock = try? BrowserSocket(baseURL: session.baseURL, token: token) else {
                    try? await Task.sleep(for: .seconds(2)); continue
                }
                await MainActor.run { self?.socket = sock }
                await sock.connect()
                if let s = await self?.lastSize, s != .zero { await self?.sendViewport(s) }
                for await event in sock.events {
                    if Task.isCancelled { break }
                    await self?.apply(event)
                    backoff = 1
                }
                await MainActor.run { self?.socket = nil }
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 10)
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        let s = socket; socket = nil
        Task { await s?.close() }
    }

    private func apply(_ e: BrowserEvent) {
        switch e {
        case .frame(let jpeg, let w, let h, let sent):
            if let img = UIImage(data: jpeg) { frame = img; viewport = CGSize(width: w, height: h); failure = nil }
            frameCount += 1
            let now = Date()
            if now.timeIntervalSince(windowStart) >= 1 {
                fps = frameCount; frameCount = 0; windowStart = now
                latencyMs = max(0, Int(now.timeIntervalSince1970 * 1000 - sent))
            }
        case .tabs(let t): tabs = t
        case .failed(let m): failure = m
        case .closed: break
        }
    }

    func send(_ m: [String: Any]) { let s = socket; Task { await s?.send(m) } }
    func sendViewport(_ size: CGSize) {
        guard size.width > 0 else { return }
        lastSize = size
        send(["t": "viewport", "w": Int(size.width), "h": Int(size.height), "scale": min(UIScreen.main.scale, 2)])
    }
    func nav(_ raw: String) { let t = raw.trimmingCharacters(in: .whitespaces); if !t.isEmpty { send(["t": "nav", "url": t]) } }
    var currentURL: String { tabs.tabs.first(where: \.active)?.url ?? "" }
}

struct BrowserView: View {
    @Environment(AppModel.self) private var model
    @State private var b = BrowserModel()
    @State private var address = ""
    @FocusState private var addressFocused: Bool
    @State private var showTabs = false
    @State private var sites: [RemoteSite] = []
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var pan: CGPoint = .zero
    @State private var lastDrag: CGSize = .zero
    @State private var typing = ""
    @State private var keyboardOn = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geo in
                ZStack {
                    Color(.secondarySystemBackground)
                    if let img = b.frame {
                        Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height).clipped()
                            .scaleEffect(zoom).offset(x: pan.x, y: pan.y)
                            .overlay(alignment: .topTrailing) { debug }
                    } else if let f = b.failure {
                        ContentUnavailableView("Browser unavailable", systemImage: "safari", description: Text(f))
                    } else { ProgressView("Starting browser…") }
                }
                .contentShape(.rect)
                .gesture(SpatialTapGesture().onEnded { v in
                    let p = BrowserInputMapper.normalized(point: v.location, viewSize: geo.size, zoom: zoom, pan: pan)
                    b.send(["t": "tap", "x": p.x, "y": p.y])
                })
                .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { v in
                    let d = CGPoint(x: v.translation.width - lastDrag.width, y: v.translation.height - lastDrag.height)
                    lastDrag = v.translation
                    if zoom > 1.01 { pan.x += d.x; pan.y += d.y }
                    else {
                        let w = BrowserInputMapper.wheelDelta(fingerDelta: d, viewSize: geo.size, viewport: b.viewport)
                        b.send(["t": "scroll", "x": 0.5, "y": 0.5, "dx": w.x, "dy": w.y])
                    }
                }.onEnded { _ in lastDrag = .zero })
                .simultaneousGesture(MagnifyGesture().onChanged { v in zoom = min(4, max(1, baseZoom * v.magnification)) }
                    .onEnded { _ in baseZoom = zoom; if zoom <= 1.01 { pan = .zero } })
                .onChange(of: geo.size, initial: true) { _, s in b.sendViewport(s) }
            }
            .clipped()
            bottomBar
        }
        .overlay(alignment: .bottom) {
            // Hidden field that owns the on-screen keyboard; typed characters are diffed and forwarded.
            TextField("", text: $typing).focused($keyFocused).opacity(0.01).frame(width: 1, height: 1)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .onChange(of: typing) { old, new in
                    if new.count > old.count, new.hasPrefix(old) { b.send(["t": "text", "text": String(new.dropFirst(old.count))]) }
                    else if new.count < old.count { for _ in 0..<(old.count - new.count) { b.send(["t": "key", "key": "Backspace"]) } }
                    if new.count > 40 { typing = "" }
                }
                .onSubmit { b.send(["t": "key", "key": "Enter"]); keyFocused = true }
        }
        .onChange(of: b.currentURL) { _, u in if !addressFocused { address = u } }
        .onChange(of: keyboardOn) { _, on in keyFocused = on; if on { typing = "" } }
        .sheet(isPresented: $showTabs) { tabSwitcher }
        .task {
            #if DEBUG
            if model.uiState == "browser" { b.loadDemo(); return }
            #endif
            b.start(session: model.session)
            if let s = try? await model.session?.sites() { sites = s }
        }
        .onDisappear { b.stop() }
    }

    @ViewBuilder private var debug: some View {
        #if DEBUG
        Text("\(b.fps) fps · \(b.latencyMs) ms").font(.caption2.monospaced()).padding(4)
            .background(.ultraThinMaterial, in: .capsule).padding(6)
        #endif
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Menu {
                if sites.isEmpty { Text("No local servers") }
                ForEach(sites) { s in Button("localhost:\(s.port)\(s.title.map { " · " + $0 } ?? "")") { b.nav("http://localhost:\(s.port)") } }
            } label: { Image(systemName: "network") }
            TextField("Search or enter address", text: $address)
                .focused($addressFocused).textFieldStyle(.roundedBorder)
                .keyboardType(.webSearch).textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { b.nav(address); addressFocused = false }
            Button { showTabs = true } label: {
                Image(systemName: "square.on.square").overlay(alignment: .topTrailing) {
                    Text("\(max(b.tabs.tabs.count, 1))").font(.system(size: 9, weight: .bold)).offset(x: 8, y: -8)
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var bottomBar: some View {
        HStack {
            Button { b.send(["t": "back"]) } label: { Image(systemName: "chevron.backward") }.disabled(!b.tabs.canBack)
            Spacer()
            Button { b.send(["t": "forward"]) } label: { Image(systemName: "chevron.forward") }.disabled(!b.tabs.canForward)
            Spacer()
            Button { b.send(["t": "reload"]) } label: { Image(systemName: "arrow.clockwise") }
            Spacer()
            Button { keyboardOn.toggle() } label: { Image(systemName: keyboardOn ? "keyboard.chevron.compact.down" : "keyboard") }
        }
        .font(.title3).padding(.horizontal, 28).padding(.vertical, 10)
        .background(.bar)
    }

    private var tabSwitcher: some View {
        NavigationStack {
            List {
                ForEach(b.tabs.tabs) { t in
                    Button { b.send(["t": "tab.select", "id": t.id]); showTabs = false } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(t.title.isEmpty ? t.url : t.title).lineLimit(1)
                                Text(t.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if t.active { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }.tint(.primary)
                    .swipeActions { Button("Close", role: .destructive) { b.send(["t": "tab.close", "id": t.id]) } }
                }
            }
            .navigationTitle("Tabs").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { showTabs = false } }
                ToolbarItem(placement: .primaryAction) {
                    Button("New tab", systemImage: "plus") { b.send(["t": "tab.new"]); showTabs = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#if DEBUG
extension BrowserModel {
    /// Screenshot-only state: a drawn page and fake tabs. Real streaming is proven by the macOS live e2e.
    func loadDemo() {
        let size = CGSize(width: 390, height: 700)
        frame = UIGraphicsImageRenderer(size: size).image { c in
            UIColor.systemBackground.setFill(); c.fill(CGRect(origin: .zero, size: size))
            let title = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: UIColor.label]
            "Acme dashboard".draw(at: CGPoint(x: 24, y: 40), withAttributes: title)
            "Revenue this week".draw(at: CGPoint(x: 24, y: 96), withAttributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.secondaryLabel])
            UIColor.systemBlue.withAlphaComponent(0.15).setFill()
            UIBezierPath(roundedRect: CGRect(x: 24, y: 130, width: 342, height: 180), cornerRadius: 16).fill()
            UIColor.systemBlue.setFill()
            for (i, h) in [60, 90, 70, 120, 100, 150, 130].enumerated() {
                UIBezierPath(roundedRect: CGRect(x: 44 + CGFloat(i) * 46, y: 300 - CGFloat(h), width: 30, height: CGFloat(h)), cornerRadius: 6).fill()
            }
            UIColor.systemGreen.setFill()
            UIBezierPath(roundedRect: CGRect(x: 24, y: 340, width: 160, height: 48), cornerRadius: 12).fill()
        }
        tabs = BrowserTabs(tabs: [
            BrowserTab(id: "1", title: "Acme dashboard", url: "http://localhost:3000", active: true),
            BrowserTab(id: "2", title: "Landing page", url: "http://localhost:5173", active: false),
        ], canBack: true, canForward: false)
    }
}
#endif
