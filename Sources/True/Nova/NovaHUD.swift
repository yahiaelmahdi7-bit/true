import SwiftUI
import AppKit

/// Floating glass HUD: transcript → state chip → one line per tool (ticked/crossed) → pending-gate card.
/// Borderless, non-activating (never steals focus from the pane you're in), hidden while idle.
@MainActor
final class NovaHUDController {
    static let shared = NovaHUDController()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 10),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isFloatingPanel = true; p.level = .floating; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: NovaHUDView(engine: .shared))
            host.sizingOptions = [.intrinsicContentSize]
            p.contentView = host
            panel = p
        }
        guard let p = panel, let screen = NSScreen.main else { return }
        let size = p.contentView?.fittingSize ?? NSSize(width: 340, height: 80)
        p.setFrame(NSRect(x: screen.visibleFrame.maxX - size.width - 16, y: screen.visibleFrame.maxY - size.height - 16,
                          width: 340, height: size.height), display: true)
        p.orderFrontRegardless()
    }
    func hide() { panel?.orderOut(nil) }
}

struct NovaHUDView: View {
    @ObservedObject var engine: NovaEngine
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(engine.state == .waiting ? Color.orange : Theme.text).frame(width: 6, height: 6)
                Text(engine.state.rawValue).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.dimText)
            }
            if !engine.transcript.isEmpty {
                Text(engine.transcript).font(.system(size: 13)).foregroundStyle(Theme.text).lineLimit(3)
            }
            ForEach(engine.lines) { l in
                HStack(spacing: 6) {
                    Text(l.ok == nil ? "·" : (l.ok! ? "✓" : "✗")).foregroundStyle(l.ok == false ? Color.red.opacity(0.8) : Theme.dimText)
                    Text(l.text).foregroundStyle(Theme.text).lineLimit(1)
                }.font(.system(size: 12, design: .monospaced))
            }
            if let p = engine.pending {
                HStack {
                    Text("Go ahead: \(p)?").font(.system(size: 12)).foregroundStyle(Theme.text).lineLimit(8)
                    Spacer(minLength: 8)
                    Button("Cancel") { engine.resolve(false, id: engine.pendingID) }.buttonStyle(.plain).foregroundStyle(Theme.dimText)
                    Button("Approve") { engine.resolve(true, id: engine.pendingID) }.buttonStyle(.plain).foregroundStyle(Theme.text).bold()
                }.font(.system(size: 12))
            }
            if let n = engine.notice {
                Text(n).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.dimText).textSelection(.enabled).lineLimit(3)
            }
        }
        .padding(12).frame(width: 340, alignment: .leading)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
        .onChange(of: engine.state) { _, s in if s == .idle { NovaHUDController.shared.hide() } else { NovaHUDController.shared.show() } }
        .onChange(of: engine.notice) { _, n in if n != nil { NovaHUDController.shared.show() } }
    }
}

/// Mic indicator + one-click mute in the title area.
struct NovaMicPill: View {
    @ObservedObject private var engine = NovaEngine.shared
    var body: some View {
        if engine.running {
            Button { engine.muted.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: engine.muted ? "mic.slash" : "mic.fill").font(.system(size: 10))
                    Text(engine.muted ? "muted" : "nova")
                }.font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(engine.muted ? Theme.dimText : Theme.text)
            }
            .buttonStyle(.plain).help(engine.muted ? "Nova is muted — click to listen" : "Nova is listening for “Nova” — click to mute")
        }
    }
}
