import SwiftUI

/// Quiet "Restart to update" pill for the tab bar; exists only once the binary on disk is newer than the
/// running one. Never a modal on detection: the dialog appears only after the user clicks, and only if
/// agents are mid-work.
struct RestartPill: View {
    let watcher: BuildFreshnessWatcher

    var body: some View {
        if watcher.offersRestart {
            Button { watcher.requestRestart() } label: {
                Label("Restart to update", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.hubSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Theme.hubCardFill, in: Capsule())
                    .overlay(Capsule().stroke(Theme.hubCardStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("A newer True is built. Restart to use it; your sessions resume.")
            .confirmationDialog(watcher.warning ?? "Restart True?",
                                isPresented: Bindable(watcher).confirming, titleVisibility: .visible) {
                Button("Restart") { watcher.restart() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
