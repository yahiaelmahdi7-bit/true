import SwiftUI
import SwiftTerm

struct PaneView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let route: PaneRoute
    @State private var controller = PaneController()

    var body: some View {
        TerminalRepresentable(controller: controller)
            .background(Color.black)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle(route.title).navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.hidden, for: .tabBar)
            .overlay(alignment: .bottom) { if let s = controller.status { Text(s).font(.footnote).padding(8).glassEffect().padding() } }
            .task { await controller.run(model: model, paneId: route.id) { dismiss() } }
            .onDisappear { Task { await controller.stop() } }
    }
}

struct TerminalRepresentable: UIViewRepresentable {
    let controller: PaneController
    func makeUIView(context: Context) -> TerminalView { controller.terminal }
    func updateUIView(_ uiView: TerminalView, context: Context) {}
}

@MainActor @Observable
final class PaneController: NSObject, TerminalViewDelegate {
    let terminal: TerminalView
    var status: String?
    private var socket: PaneSocket?
    private var accessory: UIToolbar?

    override init() {
        terminal = TerminalView(frame: .zero)
        super.init()
        terminal.terminalDelegate = self
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = .white
        terminal.backgroundColor = .black
        terminal.inputAccessoryView = makeAccessory()
    }

    private func makeAccessory() -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        func key(_ title: String, _ bytes: [UInt8]) -> UIBarButtonItem {
            UIBarButtonItem(title: title, primaryAction: UIAction { [weak self] _ in self?.send(bytes) })
        }
        let paste = UIBarButtonItem(image: UIImage(systemName: "doc.on.clipboard"), primaryAction: UIAction { [weak self] _ in
            if let s = UIPasteboard.general.string { self?.send(Array(s.utf8)) }
        })
        let flex = UIBarButtonItem.flexibleSpace()
        bar.items = [key("esc", [0x1b]), flex, key("tab", [0x09]), flex, key("⌃C", [0x03]), flex, key("↑", [0x1b, 0x5b, 0x41]), flex, key("↓", [0x1b, 0x5b, 0x42]), flex, paste]
        return bar
    }

    private func send(_ bytes: [UInt8]) {
        guard let socket else { return }
        let data = Data(bytes)
        Task { try? await socket.send(bytes: data) }
    }

    func run(model: AppModel, paneId: String, onGone: @escaping () -> Void) async {
        #if DEBUG
        if model.uiState == "pane" {
            terminal.feed(text: "\u{1b}[1mlead-true\u{1b}[0m ~/Projects/true $ swift test\r\n\u{1b}[32m✔\u{1b}[0m 214 tests passed\r\n\u{1b}[33m?\u{1b}[0m Apply the patch to Sources/True/Remote? (y/n) ")
            _ = terminal.becomeFirstResponder()
            return
        }
        #endif
        guard let session = model.session, let base = Optional(session.baseURL) else { return }
        var backoff: Duration?
        while !Task.isCancelled {
            guard let token = await session.currentToken(), let sock = try? PaneSocket(baseURL: base, paneId: paneId, token: token) else { return }
            socket = sock
            await sock.connect()
            status = nil
            for await event in sock.events {
                switch event {
                case .output(let d): backoff = nil; terminal.feed(byteArray: [UInt8](d)[...])
                case .snapshot(let c, let r):
                    terminal.resize(cols: c, rows: r)
                    terminal.font = UIFont.monospacedSystemFont(ofSize: max(6, min(14, terminal.bounds.width / (CGFloat(c) * 0.6))), weight: .regular)
                case .gone: status = "This pane was closed on the Mac."; try? await Task.sleep(for: .seconds(1.2)); onGone(); return
                case .closed(let err):
                    if case .unauthorized = err { await model.unpair(); return }
                    _ = try? await session.tabs()   // like app.js: a 401 here clears the token and the poller returns to pairing
                    status = "Reconnecting…"
                }
            }
            if Task.isCancelled { return }
            backoff = HubPoller.nextBackoff(after: backoff)
            try? await Task.sleep(for: backoff ?? HubPoller.minBackoff)
        }
    }

    func stop() async { await socket?.close(); socket = nil }

    // MARK: TerminalViewDelegate
    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let d = Data(data)
        Task { @MainActor in if let s = self.socket { try? await s.send(bytes: d) } }
    }
    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: TerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func scrolled(source: TerminalView, position: Double) {}
    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    nonisolated func clipboardCopy(source: TerminalView, content: Data) {
        Task { @MainActor in UIPasteboard.general.string = String(data: content, encoding: .utf8) }
    }
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
