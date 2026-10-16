import SwiftUI

struct ToastView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let t = model.toast {
            let isError = t.hasPrefix("Couldn't") || t.hasPrefix("Could not") || t.hasPrefix("Failed")
            Label {
                Text(t).font(.subheadline.weight(.medium))
            } icon: {
                Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(isError ? AnyShapeStyle(.attention) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.default, value: model.toast)
            .accessibilityElement(children: .combine)
        }
    }
}
