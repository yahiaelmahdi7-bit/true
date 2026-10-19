import AppKit
import SwiftUI

extension CloudJob {
    /// Plain words for the status chip, same voice as the rest of the Hub.
    var chipLabel: String {
        switch status {
        case "working": return foremanStatus == "QUEUED" ? "Queued" : "Working"
        case "needsYou": return "Needs you"
        case "done": return "Done"
        default: return "Failed"
        }
    }
    var chipLoud: Bool { isWorking || needsYou || isFailed }
}

struct CloudStatusChip: View {
    let job: CloudJob
    var body: some View {
        Text(job.chipLabel).font(.callout.weight(job.chipLoud ? .semibold : .regular))
            .foregroundStyle(job.chipLoud ? Theme.text : Theme.hubSecondary).lineLimit(1)
    }
}

/// Hub → All: "Cloud" jobs from the factory, newest first, with a Run in cloud button. An unreachable factory
/// shows one quiet line, not an error wall.
struct CloudSection: View {
    /// Project folders the Hub already knows (offered as repo choices).
    var projects: [String] = []
    @State private var store = CloudStore.shared
    @State private var detail: CloudJob?
    @State private var showNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cloud").font(.callout.weight(.semibold)).foregroundStyle(Theme.hubSecondary)
                if store.attention > 0 { Text("\(store.attention) needs you").font(.callout).foregroundStyle(Theme.text) }
                Spacer()
                Button { showNew = true } label: { Label("Run in cloud", systemImage: "icloud.and.arrow.up") }
                    .buttonStyle(.plain).font(.callout).foregroundStyle(Theme.hubSecondary)
            }
            if let e = store.error, store.jobs.isEmpty {
                Text(e).font(.callout).foregroundStyle(Theme.hubSecondary).lineLimit(2)
            } else if store.jobs.isEmpty && store.loaded {
                Text("No cloud jobs yet.").font(.callout).foregroundStyle(Theme.hubSecondary)
            }
            ForEach(store.jobs.prefix(6)) { j in
                Button { detail = j } label: { row(j) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
        .onAppear { store.visible = true; store.start(); Task { await store.refresh() } }
        .onDisappear { store.visible = false }
        .sheet(item: $detail) { CloudJobSheet(job: $0) { detail = nil } }
        .sheet(isPresented: $showNew) { NewCloudJobSheet(projects: projects) { showNew = false } }
    }

    private func row(_ j: CloudJob) -> some View {
        HubRowFrame {
            HStack(spacing: 12) {
                Image(systemName: "icloud").frame(width: 32, height: 32).foregroundStyle(Theme.hubSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(j.title).font(.body).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)
                    Text(j.needsYou ? (j.needsYouReason ?? j.repo) : "\(j.repo) · \(hubElapsed(Date().timeIntervalSince1970 - j.createdAt))")
                        .font(.callout).foregroundStyle(Theme.hubSecondary).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 4)
                CloudStatusChip(job: j)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(j.title), cloud job, \(j.chipLabel)")
        .accessibilityHint("Opens its details")
        .accessibilityAddTraits(.isButton)
    }
}

/// Pick a repo + a prompt → sync the repo to the VPS → create the job.
struct NewCloudJobSheet: View {
    let projects: [String]
    var done: () -> Void
    @State private var repo = ""
    @State private var prompt = ""
    @State private var busy = false
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Run in cloud").font(.headline)
            HStack {
                TextField("Project folder", text: $repo).textFieldStyle(.roundedBorder)
                Menu("Pick…") {
                    ForEach(projects.filter { !$0.isEmpty }, id: \.self) { p in Button((p as NSString).lastPathComponent) { repo = p } }
                    if !projects.isEmpty { Divider() }
                    Button("Choose folder…") { choose() }
                }.fixedSize()
            }
            TextEditor(text: $prompt).font(.body).frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Text("Only committed work is sent; the cloud works on a copy and you review a diff before anything lands here.")
                .font(.caption).foregroundStyle(.secondary)
            if let note { Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(3) }
            HStack {
                Spacer()
                Button("Cancel") { done() }.keyboardShortcut(.cancelAction)
                Button(busy ? "Sending…" : "Send") { Task { await send() } }
                    .keyboardShortcut(.defaultAction).disabled(busy || repo.isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16).frame(width: 480)
    }

    private func choose() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        if p.runModal() == .OK, let u = p.url { repo = u.path }
    }

    private func send() async {
        busy = true; note = "Sending your repo to the cloud…"
        let (path, text, client) = (repo, prompt, CloudStore.shared.client)
        let outcome: Result<CloudSync.Result, Error> = await Task.detached { Result { try CloudSync().sync(localRepo: path) } }.value
        switch outcome {
        case .failure(let e): note = e.localizedDescription; busy = false
        case .success(let r):
            do {
                _ = try await client.create(repo: r.repoName, job: text, title: nil, base: r.sha)
                await CloudStore.shared.refresh()
                done()
            } catch { note = error.localizedDescription; busy = false }
        }
    }
}

/// One job: timeline, the question when it needs you, and the result diff with Land.
struct CloudJobSheet: View {
    let job: CloudJob
    var done: () -> Void
    @State private var detail: CloudJobDetail?
    @State private var events: [CloudEvent] = []
    @State private var answer = ""
    @State private var diff: String?
    @State private var note: String?
    @State private var busy = false
    @State private var landRepo = ""
    @State private var landed: CloudLand.Result?

    private var live: CloudJob { CloudStore.shared.jobs.first { $0.id == job.id } ?? detail?.job ?? job }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cloud job · \(live.repo)").font(.caption).foregroundStyle(.secondary)
                    HStack { Text(live.title).font(.headline).lineLimit(1).truncationMode(.tail); CloudStatusChip(job: live) }
                }
                Spacer()
                if live.isWorking { Button("Stop") { act { _ = try await CloudStore.shared.client.stop(job.id) } } }
                Button("Done") { done() }.keyboardShortcut(.defaultAction)
            }
            if live.needsYou { needsYouBox }
            if live.isFailed, let r = live.reason { Text(r).font(.callout).foregroundStyle(.secondary).lineLimit(3) }
            Text("Timeline").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(events) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(e.type).foregroundStyle(.secondary).frame(width: 110, alignment: .leading).lineLimit(1)
                            Text(e.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.system(.caption, design: .monospaced))
                    }
                    if events.isEmpty { Text("No events yet.").font(.caption).foregroundStyle(.secondary) }
                }
            }.frame(minHeight: 120)
            if live.isDone || live.needsYou || live.isFailed { resultBox }
            if let note { Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled) }
        }
        .padding(16).frame(width: 640, height: 560)
        .task {
            detail = try? await CloudStore.shared.client.detail(job.id)
            while !Task.isCancelled {
                await reloadEvents()
                if CloudStore.shared.jobs.first(where: { $0.id == job.id })?.isWorking != true && !events.isEmpty { break }
                try? await Task.sleep(for: .seconds(3))
            }
            try? await CloudStore.shared.client.markViewed(job.id)
        }
    }

    private var needsYouBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(live.needsYouReason ?? "The job needs an answer to continue.").font(.callout).textSelection(.enabled)
            HStack {
                TextField("Your answer", text: $answer).textFieldStyle(.roundedBorder).onSubmit(sendAnswer)
                Button("Answer", action: sendAnswer).disabled(busy || answer.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    private var resultBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Result").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(diff == nil ? "Show diff" : "Reload diff") { act { diff = try await CloudStore.shared.client.diff(job.id) } }
            }
            if let diff {
                ScrollView([.vertical, .horizontal]) {
                    Text(diff.isEmpty ? "No changes." : diff).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 100, maxHeight: 180)
                if !diff.isEmpty { landRow }
            }
        }
    }

    private var landRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let landed {
                Text("Landed on branch \(landed.branch) in \(landed.path). main is untouched; nothing was pushed.")
                    .font(.callout).textSelection(.enabled)
            } else {
                HStack {
                    TextField("Local repo folder", text: $landRepo).textFieldStyle(.roundedBorder)
                    Button("Land") { land() }.disabled(busy || landRepo.isEmpty)
                }
                Text("Creates a new branch in a sibling folder and commits the diff there. Never touches main, never pushes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sendAnswer() {
        let text = answer
        act { _ = try await CloudStore.shared.client.answer(job.id, text: text); answer = ""; await CloudStore.shared.refresh() }
    }

    private func land() {
        let (repo, d, base, title) = (landRepo, diff ?? "", detail?.baseSha, live.title)
        busy = true
        Task {
            let r: Result<CloudLand.Result, Error> = await Task.detached {
                Result { try CloudLand().land(localRepo: repo, jobID: job.id, title: title, baseSha: base, diff: d) }
            }.value
            switch r {
            case .success(let l): landed = l; note = nil
            case .failure(let e): note = e.localizedDescription
            }
            busy = false
        }
    }

    private func reloadEvents() async {
        if let e = try? await CloudStore.shared.client.events(job.id) { events = e }
    }

    private func act(_ work: @escaping () async throws -> Void) {
        busy = true; note = nil
        Task {
            do { try await work() } catch { note = error.localizedDescription }
            busy = false
        }
    }
}
