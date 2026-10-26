import Foundation

/// Run 39 — "On this network": what the Peers window shows and does about other Macs on the same Wi-Fi.
/// The window opens it (`open()`) and closes it (`close()`); nothing is advertised or browsed in between.
/// Timers are injected so tests run without waiting.
typealias PeerLanTimerFactory = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> (@MainActor () -> Void)

@MainActor
final class PeerLanCoordinator: ObservableObject {
    struct Row: Identifiable, Equatable {
        var id: String          // tag, hex
        var name: String
        var paired: Bool
    }
    enum LanState: Equatable { case ok, denied, cantSearch }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var lanState: LanState = .ok

    private struct Entry { var name: String; var ad: PeerLanTXT.Ad; var ids: [String] }
    private var entries: [String: Entry] = [:]
    private var tagOfId: [String: String] = [:]

    let transport: PeerLanTransport
    let engine: PeerEngine
    let timer: PeerLanTimerFactory
    let now: () -> Date
    private var cancelWaiting: (@MainActor () -> Void)?
    private var opened = false
    private var peersObserver: NSObjectProtocol?

    static let waitingSeconds: TimeInterval = 10

    init(transport: PeerLanTransport, engine: PeerEngine, timer: @escaping PeerLanTimerFactory = PeerLanCoordinator.realTimer,
         now: @escaping () -> Date = { Date() }) {
        self.transport = transport; self.engine = engine; self.timer = timer; self.now = now
        transport.onBrowse = { [weak self] ev in self?.handle(ev) }
    }

    static let realTimer: PeerLanTimerFactory = { secs, fire in
        final class Flag: @unchecked Sendable { var live = true }
        let f = Flag()
        DispatchQueue.main.asyncAfter(deadline: .now() + secs) { MainActor.assumeIsolated { if f.live { fire() } } }
        return { f.live = false }
    }

    var isOpen: Bool { opened }

    // MARK: window lifecycle

    /// Idempotent. Starts advertising + browsing with a fresh salt.
    func open() {
        guard !opened else { return }
        opened = true
        let ad = PeerLanTXT.makeAd(mailboxId: engine.identity.mailboxId)
        transport.sync(open: true, name: PeerLanTXT.serviceName(engine.ownName), txt: PeerLanTXT.encode(ad))
        peersObserver = NotificationCenter.default.addObserver(forName: .peersChanged, object: nil, queue: nil) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.rebuild() } }
        }
    }

    /// Idempotent. Stops everything and forgets what it saw.
    func close() {
        guard opened else { return }
        opened = false
        if let o = peersObserver { NotificationCenter.default.removeObserver(o); peersObserver = nil }
        transport.sync(open: false, name: "", txt: [:])
        cancelWaiting?(); cancelWaiting = nil
        entries.removeAll(); tagOfId.removeAll()
        lanState = .ok
        rebuild()
    }

    // MARK: browsing

    func handle(_ ev: PeerLanBrowseEvent) {
        guard opened else { return }
        switch ev {
        case .found(let id, let name, let txt): add(id: id, name: name, txt: txt)
        case .removed(let id): remove(id: id)
        case .state(let st): browseState(st)
        }
    }

    private func add(id: String, name: String, txt: [String: String]) {
        remove(id: id)
        guard let ad = PeerLanTXT.decode(txt) else { return }
        guard !PeerLanTXT.matches(ad, mailboxId: engine.identity.mailboxId) else { return }   // our own row
        let tag = PeerLanTXT.hex(ad.tag)
        if var e = entries[tag] {
            e.ids.append(id); entries[tag] = e
        } else {
            guard entries.count < PeerLanTXT.maxRows else { return }
            entries[tag] = Entry(name: PeerLanLabel.display(name), ad: ad, ids: [id])
        }
        tagOfId[id] = tag
        rebuild()
    }

    private func remove(id: String) {
        guard let tag = tagOfId.removeValue(forKey: id), var e = entries[tag] else { return }
        e.ids.removeAll { $0 == id }
        if e.ids.isEmpty { entries[tag] = nil } else { entries[tag] = e }
        rebuild()
    }

    private func browseState(_ st: PeerLanBrowseState) {
        switch st {
        case .ready: cancelWaiting?(); cancelWaiting = nil; lanState = .ok
        case .denied: cancelWaiting?(); cancelWaiting = nil; lanState = .denied
        case .waiting:
            guard lanState == .ok, cancelWaiting == nil else { return }
            cancelWaiting = timer(Self.waitingSeconds) { [weak self] in
                guard let self else { return }
                self.cancelWaiting = nil
                if self.lanState == .ok { self.lanState = .cantSearch }
            }
        }
    }

    private func rebuild() {
        let mids = engine.peerLinks().map(\.mailboxId)
        rows = entries.map { tag, e in
            Row(id: tag, name: e.name, paired: mids.contains { PeerLanTXT.matches(e.ad, mailboxId: $0) })
        }.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }

    /// First transport handle for a row (several interfaces can carry the same Mac).
    func connectionId(for rowId: String) -> String? { entries[rowId]?.ids.first }
}

/// Names that come from another Mac are never trusted raw.
enum PeerLanLabel {
    /// A name safe to show and to use as a peer label, else "Peer" (same rule as `PeerEngine.handlePairRequest`).
    static func display(_ raw: String) -> String {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || n.count > PeerValidate.maxLabel || PeerValidate.hasBadControl(n) || n.contains("\n") { return "Peer" }
        return n
    }

    /// `display(raw)`, suffixed " 2", " 3"… until it matches no existing label (case-insensitive).
    static func safe(_ raw: String, existing: [String]) -> String {
        let base = display(raw)
        let taken = Set(existing.map { $0.lowercased() })
        var label = base, n = 2
        while taken.contains(label.lowercased()) { label = "\(base) \(n)"; n += 1 }
        return label
    }
}
