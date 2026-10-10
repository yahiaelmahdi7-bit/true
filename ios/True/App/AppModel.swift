import SwiftUI
import UIKit
import Observation

extension ShapeStyle where Self == Color {
    /// The ONE accent: Needs you / Failed / unread / danger / offline only.
    /// Warm amber #D97A1F light / #E8A23C dark (mirrors the Attention asset; built in code so it can never resolve to clear).
    static var attention: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.910, green: 0.635, blue: 0.235, alpha: 1) : UIColor(red: 0.851, green: 0.478, blue: 0.122, alpha: 1) })
    }
}

struct PaneRoute: Hashable, Identifiable { let id: String; let title: String }

@MainActor @Observable
final class AppModel {
    var session: RemoteSession?
    var paired = false
    var hub: HubSnapshot?
    var failCount = 0
    var toast: String?
    var openPane: PaneRoute?
    /// Pane composer state, in memory only: unsent drafts and the Compose/Keys choice per pane id.
    var paneDrafts: [String: String] = [:]
    var paneKeysMode: [String: Bool] = [:]
    var showComposer = false
    var selectedTab = "hub"
    /// A `true://pair` link without a code (Mac had none live): PairView prefills the address from it.
    var pendingPairLink: PairLink?
    /// A Mac found over Bluetooth while the Pair screen is up (nil when none is in range).
    var nearbyMac: NearbyPairing.NearbyMac?
    var bluetoothState: BluetoothState = .unknown
    private var scanner: NearbyScanning?
    private var pollTask: Task<Void, Never>?
    private let store = KeychainTokenStore()

    /// `-uiState <name>` launch argument: drives the app into one screen for screenshots.
    let uiState = UserDefaults.standard.string(forKey: "uiState")

    var needsYouCount: Int { hub?.needsYou ?? 0 }
    /// Transient failures show a toolbar pill; after three the Hub swaps to an unavailable view.
    var offline: Bool { failCount >= 3 }

    init() {
        if let url = SharedConfig.baseURL, store.load() != nil { attach(url) }
        if let mock = UserDefaults.standard.string(forKey: "baseURL"), let url = SharedConfig.normalize(mock) {
            SharedConfig.baseURL = url
            attach(url)
            if let code = UserDefaults.standard.string(forKey: "autoPair") {
                Task { _ = await pair(address: mock, code: code) }
            }
        }
        if let s = uiState {
            selectedTab = s.hasPrefix("shots") || s == "viewer" ? "shots" : s == "send" ? "send" : s.hasPrefix("panes") ? "panes" : "hub"
            showComposer = s == "composer" || s == "composer-routed"
        }
    }

    /// Scan only while the Pair screen is showing and the phone is unpaired. Bluetooth permission is asked on first call.
    func startNearbyScan() {
        guard !paired else { return }
        if scanner == nil {
            #if DEBUG
            if let s = uiState, s.hasPrefix("pair-nearby") {
                scanner = FakeNearbyScanner(state: s == "pair-nearby-bt-off" ? .poweredOff : .poweredOn,
                                            mac: s == "pair-nearby-bt-off" ? nil : .init(name: "Yahia's MacBook", address: "yoshii-mac.tail1234.ts.net:8444"))
            }
            #endif
            #if targetEnvironment(simulator)
            // The simulator has no Bluetooth; don't ask for a permission it can never grant.
            if scanner == nil { return }
            #endif
            if scanner == nil { scanner = CoreBluetoothScanner() }
            scanner?.onState = { [weak self] in self?.bluetoothState = $0 }
            scanner?.onMac = { [weak self] in self?.nearbyMac = $0 }
            scanner?.onPaired = { [weak self] in self?.nearbyMac = nil }
        }
        scanner?.start()
    }

    func stopNearbyScan() {
        scanner?.stop()
        nearbyMac = nil
    }

    private func attach(_ url: URL) {
        session = RemoteSession(baseURL: url, store: store)
        paired = store.load() != nil
        if paired { startPolling() }
    }

    /// Returns nil on success, otherwise the sentence to show under the Pair button.
    func pair(address: String, code: String) async -> String? {
        guard let url = SharedConfig.normalize(address) else { return "That address doesn't look right." }
        let s = RemoteSession(baseURL: url, store: store)
        do {
            try await s.pair(code: code)
            SharedConfig.baseURL = url
            session = s; paired = true; hub = nil; failCount = 0
            stopNearbyScan()
            startPolling()
            if UserDefaults.standard.string(forKey: "autoPair") == nil { Background.requestAuthorization() }
            return nil
        } catch RemoteError.pairingFailed(let m) { return m
        } catch RemoteError.rateLimited { return "Too many tries — wait a minute."
        } catch { return "Couldn't reach the Mac." }
    }

    func unpair() async {
        pollTask?.cancel()
        await session?.unpair()
        paired = false; hub = nil; failCount = 0
    }

    /// Single funnel for errors: 401 means the token is gone, so go back to pairing.
    func handle(_ error: Error) async {
        if case RemoteError.unauthorized = error { await unpair() }
    }

    func startPolling() {
        pollTask?.cancel()
        guard let session else { return }
        pollTask = Task { [weak self] in
            var last: HubSnapshot?
            var backoff: Duration?
            while !Task.isCancelled {
                do {
                    let snap = try await session.hub()
                    guard let self else { return }
                    if HubPoller.needsYouRose(from: last, to: snap) { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
                    last = snap; backoff = nil
                    self.hub = snap; self.failCount = 0
                    try await Task.sleep(for: .seconds(10))
                } catch RemoteError.unauthorized {
                    await self?.unpair(); return
                } catch is CancellationError { return
                } catch {
                    backoff = HubPoller.nextBackoff(after: backoff)
                    self?.failCount += 1
                    try? await Task.sleep(for: backoff ?? HubPoller.minBackoff)
                }
            }
        }
    }

    /// Mac → phone clipboard: if the Mac shared a newer copy, put it on this phone's pasteboard (opt-out in Send).
    /// Writing the pasteboard shows no system banner; only reading does. An item older than 10 minutes that we
    /// have never applied before (first run after pairing) is remembered, not applied.
    func applyMacClipboard(_ known: [InboxItem]? = nil) async {
        let d = UserDefaults.standard
        guard d.object(forKey: "autoClipboard") as? Bool ?? true, let session else { return }
        var all = known
        if all == nil { all = try? await session.inbox() }
        guard let items = all,
              let item = items.first(where: { $0.source == "clipboardShare" }), item.kind == "text" else { return }
        let last = d.string(forKey: "lastAppliedClipId")
        guard item.id != last else { return }
        let stale = item.created.map { Date().timeIntervalSince1970 - $0 > 600 } ?? false
        if last == nil && stale { d.set(item.id, forKey: "lastAppliedClipId"); return }
        guard let data = try? await session.inboxData(id: item.id) else { return }
        UIPasteboard.general.string = String(decoding: data, as: UTF8.self)
        d.set(item.id, forKey: "lastAppliedClipId")
        show("Clipboard from your Mac")
    }

    func refresh() async {
        guard let session else { return }
        do { hub = try await session.hub(); failCount = 0 } catch { await handle(error); failCount += 1 }
    }

    func show(_ message: String) {
        toast = message
        UIAccessibility.post(notification: .announcement, argument: message)
        Task { try? await Task.sleep(for: .seconds(2.4)); if toast == message { toast = nil } }
    }

    /// Wake/Sleep from a swipe: the Mac routes the sentence, same as typing it in the composer.
    func command(_ text: String) async {
        guard let session else { return }
        do {
            let r = try await session.route(text: text)
            guard let id = r.routeId, r.runnable else { show("Nothing to run for that."); return }
            let out = try await session.run(routeId: id)
            show(out.needsConfirm == true ? "Needs confirming — use Start work." : "Done.")
            await refresh()
        } catch { await handle(error); show("Couldn't do that (Mac offline?)") }
    }

    func handle(url: URL) {
        if url.scheme == "true", url.host == "pair" {
            guard let link = PairLink(url: url) else { show("That's not a True pairing code"); return }
            if paired { show("Already paired with your Mac"); return }
            guard let code = link.code else { pendingPairLink = link; return }
            Task { if let err = await pair(address: link.address, code: code) { show(err) } }
            return
        }
        guard url.scheme == "true", url.host == "pane" else { return }
        let id = url.lastPathComponent
        if !id.isEmpty, id != "/" { selectedTab = "hub"; openPane = PaneRoute(id: id, title: "Pane") }
    }
}
