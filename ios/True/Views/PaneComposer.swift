import SwiftUI

/// In-flight state and the send/react flow for the pane composer. The draft itself lives in AppModel
/// (per pane, in memory) so it survives leaving and re-entering the pane.
@MainActor @Observable
final class PaneComposer {
    /// nil until /api/tabs answers; the Hub row is the fallback.
    var claude: Bool?
    var inFlight = false
    /// The one-slot "last sent" buffer, so a failed send can put the words back.
    private(set) var lastSent = ""

    func send(_ intent: PaneInputIntent, paneId: String, draft: Binding<String>, model: AppModel, onGone: @escaping () -> Void) {
        guard !inFlight, let session = model.session else { return }
        var text = ""
        if intent == .prompt {
            text = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            lastSent = text
            draft.wrappedValue = ""          // optimistic: the field clears at once
        }
        inFlight = true
        Task { @MainActor in
            defer { inFlight = false }
            @MainActor func restore() {
                guard intent == .prompt else { return }
                let now = draft.wrappedValue
                draft.wrappedValue = now.isEmpty ? lastSent : lastSent + "\n" + now
            }
            do {
                let outcome = try await session.paneInput(id: paneId, intent: intent, text: text)
                switch outcome.reaction(for: intent) {
                case .nothing: break
                case .toast(let t): model.show(t)
                case .restore(let t): restore(); model.show(t)
                case .popPane(let t): model.show(t); onGone()
                }
            } catch RemoteError.paneGone {
                model.show("Pane is gone"); onGone()
            } catch RemoteError.unauthorized {
                await model.unpair()
            } catch {
                restore()
                model.show("Couldn't reach the Mac — your text is still here")
            }
        }
    }
}

/// Native prompt composer docked above the keyboard. Glass on controls only; blue = interactive.
struct ComposerBar: View {
    @Binding var draft: String
    let composer: PaneComposer
    let isClaude: Bool
    var focused: FocusState<Bool>.Binding
    let onKeys: () -> Void
    let onSend: () -> Void
    let onKey: ([UInt8]) -> Void
    let onIntent: (PaneInputIntent) -> Void
    @ScaledMetric private var hit = 44

    private var canSend: Bool { !composer.inFlight && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            keyRow
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: onKeys) { Label("Keys", systemImage: "terminal").labelStyle(.iconOnly).frame(width: hit, height: hit) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityHint("Type straight into the terminal")
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused(focused)
                    .submitLabel(.send)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(minHeight: hit)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityLabel("Prompt")
                Button(action: onSend) {
                    ZStack {
                        if composer.inFlight { ProgressView().tint(.white) }
                        else { Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundStyle(.white) }
                    }
                    .frame(width: hit, height: hit)
                    .background(Circle().fill(Color.accentColor))
                    .opacity(canSend || composer.inFlight ? 1 : 0.35)
                }
                .disabled(!canSend)
                .accessibilityLabel(composer.inFlight ? "Sending" : "Send")
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    private var keyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                key("esc", label: "Escape") { onKey([0x1b]) }
                key(symbol: "arrow.up", label: "Up") { onKey([0x1b, 0x5b, 0x41]) }
                key(symbol: "arrow.down", label: "Down") { onKey([0x1b, 0x5b, 0x42]) }
                key(symbol: "return", label: "Return") { onIntent(.submitOnly) }
                key("⌃C", label: "Control C") { onKey([0x03]) }
                if isClaude {
                    key("Approve", label: "Approve", tint: .accentColor) { onIntent(.approve) }
                    key("Deny", label: "Deny") { onIntent(.deny) }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func key(_ title: String? = nil, symbol: String? = nil, label: String, tint: Color? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let symbol { Image(systemName: symbol) } else { Text(title ?? "") }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12).frame(minWidth: hit, minHeight: hit)
        }
        .buttonStyle(.glass)
        .tint(tint)
        .accessibilityLabel(label)
    }
}
