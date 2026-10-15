import SwiftUI
import AppKit

/// Plain words for a peer job's status, in the same voice as the rest of the Hub.
extension PeerStatus {
    var pillLabel: String {
        switch self {
        case .queued: return "Sending"
        case .accepted: return "Accepted"
        case .working: return "Working"
        case .needsYou: return "Needs them"
        case .idle: return "Idle"
        case .done: return "Done"
        case .failed: return "Failed"
        case .declined: return "Declined"
        }
    }
    var isLoud: Bool { self == .working || self == .failed || self == .needsYou }
}

private func peerElapsed(_ from: Date, to: Date? = nil) -> String {
    hubElapsed((to ?? Date()).timeIntervalSince(from))
}

/// Hub groups "Sent to peers" and "From peers". Hidden when there is nothing to show.
struct PeerJobsSection: View {
    @State private var sent: [SentJob] = []
    @State private var inbound: [InboundJob] = []
    @State private var sentDetail: SentJob?
    @State private var inboundDetail: InboundJob?

    var body: some View {
        Group {
            if !sent.isEmpty || !inbound.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !inbound.isEmpty {
                            label("From peers")
                            ForEach(inbound) { j in inboundRow(j) }
                        }
                        if !sent.isEmpty {
                            label("Sent to peers")
                            ForEach(sent) { j in sentRow(j) }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
                .frame(maxHeight: 230)
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .peersChanged)) { _ in reload() }
        .sheet(item: $sentDetail) { SentJobSheet(job: $0) }
        .sheet(item: $inboundDetail) { InboundJobSheet(job: $0) { inboundDetail = nil; reload() } }
    }

    private func reload() {
        let e = RemoteAccess.shared.peers
        let cutoff = Date().addingTimeInterval(-3 * 86400)
        sent = e.sentJobs().filter { !$0.status.isFinal || $0.updated > cutoff }.prefix(8).map { $0 }
        inbound = e.inboundJobs().filter { !$0.status.isFinal || ($0.finished ?? .distantPast) > cutoff }.prefix(8).map { $0 }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.callout.weight(.medium)).foregroundStyle(Theme.hubSecondary).padding(.horizontal, 4).padding(.top, 6)
    }

    private func pill(_ s: PeerStatus) -> some View {
        Text(s.pillLabel).font(.callout.weight(s.isLoud ? .semibold : .regular))
            .foregroundStyle(s.isLoud ? Theme.text : Theme.hubSecondary).lineLimit(1)
    }

    private func sentRow(_ j: SentJob) -> some View {
        HubRowFrame {
            HStack(spacing: 12) {
                Image(systemName: "paperplane").frame(width: 32).foregroundStyle(Theme.hubSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(j.title).font(.body).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)
                    Text("\(j.peerLabel) · \(peerElapsed(j.created, to: j.status.isFinal ? j.updated : nil))")
                        .font(.callout).foregroundStyle(Theme.hubSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                pill(j.status)
            }
        }
        .onTapGesture { sentDetail = j }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(j.title), sent to \(j.peerLabel), \(j.status.pillLabel)")
        .accessibilityAddTraits(.isButton)
    }

    private func inboundRow(_ j: InboundJob) -> some View {
        HubRowFrame {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down").frame(width: 32).foregroundStyle(Theme.hubSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(j.req.title).font(.body).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)
                    Text("\(j.peerLabel) · \(peerElapsed(j.received, to: j.finished))")
                        .font(.callout).foregroundStyle(Theme.hubSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if !j.flags.isEmpty {
                    Label("\(j.flags.count)", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(Theme.text).help(j.flags.joined(separator: "\n"))
                }
                if j.status == .queued && j.inboundMode == .ask {
                    Button("Decline") { RemoteAccess.shared.peers.decline(j.id) }.buttonStyle(.plain).foregroundStyle(Theme.hubSecondary)
                    Button("Accept") { RemoteAccess.shared.peers.accept(j.id) }.buttonStyle(.plain).fontWeight(.semibold)
                } else {
                    pill(j.status)
                }
            }
        }
        .onTapGesture { inboundDetail = j }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(j.req.title), from \(j.peerLabel), \(j.status.pillLabel)")
        .accessibilityAddTraits(.isButton)
    }
}

/// What came back from the friend: result text, the branch, and the one command to fetch it.
struct SentJobSheet: View {
    let job: SentJob
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let live = RemoteAccess.shared.peers.result(jobId: job.jobId) ?? job
        VStack(alignment: .leading, spacing: 12) {
            Text(live.title).font(.title3.weight(.semibold))
            Text("\(live.peerLabel) · \(live.status.pillLabel)\(live.note.isEmpty ? "" : " · \(live.note)")")
                .font(.callout).foregroundStyle(.secondary)
            if let branch = live.branch {
                let cmd = PeerNaming.fetchCommand(branch: branch)
                Text(cmd).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Button(copied ? "Copied" : "Copy fetch command") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cmd, forType: .string); copied = true
                }
            }
            ScrollView {
                Text(live.result?.isEmpty == false ? live.result! : "No result yet.")
                    .font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160)
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20).frame(width: 520, height: 420)
    }
}

/// The receiver's view of one job. In ask mode this is the Accept sheet, with the screening flags up top.
struct InboundJobSheet: View {
    let job: InboundJob
    let onDone: () -> Void

    var body: some View {
        let waiting = job.status == .queued && job.inboundMode == .ask
        VStack(alignment: .leading, spacing: 12) {
            Text(job.req.title).font(.title3.weight(.semibold))
            Text("From \(job.peerLabel) · \(job.req.repo) · \(job.status.pillLabel)").font(.callout).foregroundStyle(.secondary)
            if !job.flags.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Looks like it may be trying to steer Claude", systemImage: "exclamationmark.triangle").font(.callout.weight(.semibold))
                    ForEach(job.flags, id: \.self) { Text("• \($0)").font(.callout) }
                }
            }
            ScrollView {
                Text(String(job.req.brief.prefix(4000))).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160)
            HStack {
                Spacer()
                if waiting {
                    Button("Decline") { RemoteAccess.shared.peers.decline(job.id); onDone() }
                    Button("Accept") { RemoteAccess.shared.peers.accept(job.id); onDone() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Close") { onDone() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20).frame(width: 520, height: 420)
    }
}

@MainActor
final class PeersWindow {
    static let shared = PeersWindow()
    private var window: NSWindow?

    func show() {
        RemoteAccess.shared.reloadDevices()
        RemoteAccess.shared.refreshTailnet()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Peers"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: PeersView())
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct PeersView: View {
    @State private var remote = RemoteAccess.shared
    @State private var mode = PeerInboundMode.current
    @State private var invite: (url: String?, code: String)?
    @State private var links: [PeerLink] = []
    @State private var devices: [PairedDevice] = []
    @State private var addURL = ""
    @State private var addCode = ""
    @State private var addLabel = ""
    @State private var addNote: String?
    @State private var adding = false

    var body: some View {
        ScrollView { content }
            .frame(width: 460, height: 640, alignment: .topLeading)
            .onAppear(perform: reload)
            .onReceive(NotificationCenter.default.publisher(for: .peersChanged)) { _ in reload() }
    }

    private func reload() {
        let e = remote.peers
        links = e.peerLinks(); devices = e.peerDevices()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !remote.enabled {
                Text("Remote Access is off. Peers only work while it is on.").font(.callout).foregroundStyle(.secondary)
                Button("Turn on Remote Access") { remote.setEnabled(true) }
                Divider()
            }
            Text("Jobs from peers").font(.headline)
            Picker("", selection: Binding(get: { mode }, set: { mode = $0; PeerInboundMode.current = $0 })) {
                Text("Run at once, no prompts").tag(PeerInboundMode.bypass)
                Text("Run on auto").tag(PeerInboundMode.auto)
                Text("Ask me first").tag(PeerInboundMode.ask)
            }
            .pickerStyle(.radioGroup).labelsHidden()
            Text("Applies to jobs a paired friend sends this Mac.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Invite a peer").font(.headline)
            if let invite {
                Text(invite.url ?? "Waiting for this Mac's Tailscale address…")
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text(invite.code).font(.system(size: 28, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                Text("Share the Mac on Tailscale, then give them the address and this code. One use, 5 minutes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(invite == nil ? "Show a code" : "New code") { invite = remote.peers.invite() }
            Divider()
            Text("Add a peer").font(.headline)
            TextField("https://their-mac.tailnet.ts.net:8444", text: $addURL).textFieldStyle(.roundedBorder)
            HStack {
                TextField("Code", text: $addCode).textFieldStyle(.roundedBorder).frame(width: 110)
                TextField("What you call them", text: $addLabel).textFieldStyle(.roundedBorder)
            }
            HStack {
                Button(adding ? "Pairing…" : "Add") { add() }
                    .disabled(adding || addURL.isEmpty || addCode.isEmpty || addLabel.isEmpty)
                if let addNote { Text(addNote).font(.callout).foregroundStyle(.secondary) }
            }
            Divider()
            Text("You can send to").font(.headline)
            if links.isEmpty { Text("Nobody yet.").foregroundStyle(.secondary) }
            ForEach(links, id: \.label) { l in
                HStack {
                    VStack(alignment: .leading) { Text(l.label); Text(l.url).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Remove") { remote.peers.removeLink(l.label) }
                }
            }
            Text("Can send to you").font(.headline).padding(.top, 4)
            if devices.isEmpty { Text("Nobody yet.").foregroundStyle(.secondary) }
            ForEach(devices) { d in
                HStack {
                    VStack(alignment: .leading) {
                        Text(d.label)
                        Text("last seen \(d.lastSeen.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revoke", role: .destructive) { remote.peers.revoke(deviceId: d.id); remote.reloadDevices() }
                }
            }
            Divider()
            Button("Stop all peer jobs", role: .destructive) { remote.peers.stopAll() }
            Text("Ends every job running for a peer and declines the waiting ones.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 460, alignment: .topLeading)
    }

    private func add() {
        adding = true; addNote = nil
        let (u, c, l) = (addURL, addCode, addLabel)
        let engine = remote.peers
        Task.detached {
            let r = engine.pairAsSender(url: u, code: c, label: l)
            await MainActor.run {
                adding = false
                switch r {
                case .success: addNote = "Added \(l)."; addURL = ""; addCode = ""; addLabel = ""
                case .failure(let e): addNote = "\(e)"
                }
                reload()
            }
        }
    }
}
