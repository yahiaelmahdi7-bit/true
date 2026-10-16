import SwiftUI
import WebKit

/// Local dev servers running in True's panes on the Mac. Tap one to share it over Tailscale and open it here.
struct SitesView: View {
    @Environment(AppModel.self) private var model
    @State private var sites: [RemoteSite]?
    @State private var open: RemoteSite?
    @State private var fix: RemoteSite?
    @State private var busy: Int?

    var body: some View {
        NavigationStack {
            Group {
                if let sites {
                    if sites.isEmpty {
                        ContentUnavailableView("No local servers", systemImage: "network",
                                               description: Text("Start a dev server in a True pane on your Mac and it shows up here."))
                    } else { list(sites) }
                } else { ProgressView() }
            }
            .navigationTitle("Sites")
        }
        .task {
            #if DEBUG
            if let s = model.uiState, s == "sites" { sites = RemoteSite.demo; return }
            #endif
            while !Task.isCancelled {
                await load(refresh: false)
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .sheet(item: $open) { site in SiteWebSheet(site: site) }
        .sheet(item: $fix) { site in HostFixSheet(site: site) { open = site } }
    }

    private func list(_ sites: [RemoteSite]) -> some View {
        List(sites) { site in
            Button { Task { await tap(site) } } label: {
                HStack(spacing: 12) {
                    Image(systemName: site.exposed ? "network" : "network.slash")
                        .foregroundStyle(site.exposed ? Color.green : Color.secondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(site.title?.isEmpty == false ? site.title! : "localhost:\(site.port)").font(.headline)
                        Text([":\(site.port)", site.project, site.pane].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if busy == site.port { ProgressView() }
                    else if site.exposed { Text("Shared").font(.caption).foregroundStyle(.green) }
                }
            }
            .tint(.primary)
            .contextMenu {
                if site.exposed {
                    Button("Stop sharing", systemImage: "xmark.circle") { Task { await setExposed(site, false) } }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load(refresh: true) }
    }

    private func tap(_ site: RemoteSite) async {
        var s = site
        if !site.exposed {
            guard let r = await setExposed(site, true) else { return }
            s = r
        }
        if s.hostFix != nil { fix = s } else if s.url != nil { open = s }
    }

    @discardableResult
    private func setExposed(_ site: RemoteSite, _ on: Bool) async -> RemoteSite? {
        guard let session = model.session else { return nil }
        busy = site.port; defer { busy = nil }
        do {
            let r = try await session.setSiteExposed(port: site.port, on)
            await load(refresh: false)
            return r
        } catch {
            await model.handle(error)
            model.show(on ? "Couldn't share that site" : "Couldn't stop sharing")
            return nil
        }
    }

    private func load(refresh: Bool) async {
        guard let session = model.session else { return }
        do { sites = try await session.sites(refresh: refresh) }
        catch { if !Task.isCancelled { await model.handle(error); if sites == nil { sites = [] } } }
    }
}

/// One-line fix for dev servers that reject the *.ts.net host. We never edit the project; the user pastes it.
private struct HostFixSheet: View {
    let site: RemoteSite
    let openAnyway: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(site.hostFix?.framework ?? "The dev server") blocks this address").font(.title3.bold())
                Text("Add this to the project's config on your Mac, then reload.").foregroundStyle(.secondary)
                Text(site.hostFix?.snippet ?? "").font(.system(.callout, design: .monospaced))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                    .textSelection(.enabled)
                Button { UIPasteboard.general.string = site.hostFix?.snippet } label: {
                    Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                Button("Open anyway") { dismiss(); openAnyway() }.frame(maxWidth: .infinity)
                Spacer()
            }
            .padding()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

private struct SiteWebSheet: View {
    let site: RemoteSite
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var reload = 0

    var body: some View {
        NavigationStack {
            Group {
                if let s = site.url, let url = URL(string: s) {
                    SiteWebView(url: url, reload: reload).ignoresSafeArea(edges: .bottom)
                } else { ContentUnavailableView("No address", systemImage: "network.slash") }
            }
            .navigationTitle(site.title ?? "localhost:\(site.port)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if let s = site.url, let url = URL(string: s) {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Reload", systemImage: "arrow.clockwise") { reload += 1 }
                        ShareLink(item: url)
                        Button("Open in Safari", systemImage: "safari") { openURL(url) }
                    }
                }
            }
        }
    }
}

private struct SiteWebView: UIViewRepresentable {
    let url: URL
    let reload: Int

    final class Coordinator { var lastReload = 0; weak var web: WKWebView?
        @objc func pulled(_ r: UIRefreshControl) { web?.reload(); r.endRefreshing() } }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView()
        let rc = UIRefreshControl()
        rc.addTarget(context.coordinator, action: #selector(Coordinator.pulled), for: .valueChanged)
        w.scrollView.refreshControl = rc
        context.coordinator.web = w
        w.load(URLRequest(url: url))
        return w
    }
    func updateUIView(_ w: WKWebView, context: Context) {
        if context.coordinator.lastReload != reload { context.coordinator.lastReload = reload; w.reload() }
    }
}

#if DEBUG
extension RemoteSite {
    static let demo: [RemoteSite] = [
        RemoteSite(port: 3000, title: "Acme dashboard", pane: "claude", project: "acme-web", command: "next dev", exposed: true, url: "https://mac.tail1234.ts.net:3000/"),
        RemoteSite(port: 5173, title: "Landing page", pane: "zsh", project: "landing", command: "vite", exposed: false),
        RemoteSite(port: 8765, title: nil, pane: "zsh", project: nil, command: "python3 -m http.server", exposed: false),
    ]
}
#endif
