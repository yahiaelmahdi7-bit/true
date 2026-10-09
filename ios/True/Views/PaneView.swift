import SwiftUI
import SwiftTerm

struct PaneView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let route: PaneRoute
    @State private var controller = PaneController()
    @State private var keyboardUp = false

    private var row: HubRow? { model.hub?.projects.flatMap(\.rows).first { $0.pane == route.id } }
    private var asleep: Bool { row?.statusKey == "asleep" }

    var body: some View {
        TerminalRepresentable(controller: controller)
            .background(Color.black)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle(route.title).navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(row?.status ?? "")
            .toolbarVisibility(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { Task { await model.command(asleep ? "wake \(route.title)" : "sleep \(route.title)") } } label: {
                            asleep ? Label("Wake", systemImage: "sunrise") : Label("Sleep", systemImage: "moon.zzz")
                        }
                        Button { UIPasteboard.general.string = route.title; model.show("Copied name") } label: { Label("Copy name", systemImage: "doc.on.doc") }
                        if let cwd = row?.cwd { Button { UIPasteboard.general.string = cwd; model.show("Copied path") } label: { Label("Copy path", systemImage: "folder") } }
                    } label: { Label("Pane actions", systemImage: "ellipsis.circle") }
                }
            }
            .overlay(alignment: .bottom) {
                if let s = controller.status {
                    Label(s, systemImage: s.hasPrefix("Reconnecting") ? "arrow.triangle.2.circlepath" : "xmark.circle")
                        .font(.footnote.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule).padding(.bottom, 12)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !keyboardUp {
                    Button { _ = controller.terminal.becomeFirstResponder() } label: { Label("Show keyboard", systemImage: "keyboard").labelStyle(.iconOnly).frame(width: 44, height: 44) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
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

    /// Key row above the keyboard. A scrolling row of glass buttons, not a UIToolbar: iOS 26 gives
    /// every bar item a minimum-width capsule plus spacing, and seven of them overflow a phone.
    private func makeAccessory() -> UIView {
        let host = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 56), inputViewStyle: .keyboard)
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        let row = UIStackView()
        row.axis = .horizontal; row.spacing = 8; row.alignment = .center
        func button(_ title: String?, _ symbol: String?, _ label: String, _ action: @escaping (PaneController) -> Void) -> UIButton {
            var cfg = UIButton.Configuration.glass()
            cfg.title = title
            if let symbol { cfg.image = UIImage(systemName: symbol) }
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
            let b = UIButton(configuration: cfg, primaryAction: UIAction { [weak self] _ in if let self { action(self) } })
            b.accessibilityLabel = label
            b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            b.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            return b
        }
        [
            button("esc", nil, "Escape") { $0.send([0x1b]) },
            button("tab", nil, "Tab") { $0.send([0x09]) },
            button("⌃C", nil, "Control C") { $0.send([0x03]) },
            button(nil, "arrow.up", "Up") { $0.send([0x1b, 0x5b, 0x41]) },
            button(nil, "arrow.down", "Down") { $0.send([0x1b, 0x5b, 0x42]) },
            button(nil, "return", "Return") { $0.send([0x0d]) },
            button(nil, "doc.on.clipboard", "Paste") { if let s = UIPasteboard.general.string { $0.send(Array(s.utf8)) } },
        ].forEach(row.addArrangedSubview)
        host.addSubview(scroll); scroll.addSubview(row)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: host.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        return host
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
                    terminal.font = UIFont.monospacedSystemFont(ofSize: max(9, min(14, terminal.bounds.width / (CGFloat(c) * 0.6))), weight: .regular)
                case .gone: status = "This pane was closed on the Mac."; try? await Task.sleep(for: .seconds(1.2)); onGone(); return
                case .closed(let err):
                    if case .unauthorized = err { await model.unpair(); return }
                    _ = try? await session.tabs()   // like app.js: a 401 here clears the token and the poller returns to pairing
                    status = "Reconnecting"
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
