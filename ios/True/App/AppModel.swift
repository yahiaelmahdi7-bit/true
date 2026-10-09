import SwiftUI
import UIKit
import Observation

extension ShapeStyle where Self == Color {
    /// The ONE accent: Needs you / Failed / unread / danger / offline only.
    static var attention: Color { Color("Attention") }
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
    var showComposer = false
    var selectedTab = "hub"
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
            selectedTab = s == "shots" ? "shots" : s == "send" ? "send" : "hub"
            showComposer = s == "composer"
        }
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
            startPolling()
            Background.requestAuthorization()
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
        guard url.scheme == "true", url.host == "pane" else { return }
        let id = url.lastPathComponent
        if !id.isEmpty, id != "/" { selectedTab = "hub"; openPane = PaneRoute(id: id, title: "Pane") }
    }
}
