import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct TrueActivityBundle: WidgetBundle {
    var body: some Widget { PaneActivityWidget() }
}

/// Amber = state ("needs you"). Blue = the one interactive button. No green.
private let amber = Color(red: 0.910, green: 0.635, blue: 0.235)

struct PaneActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PaneActivityAttributes.self) { ctx in
            VStack(alignment: .leading, spacing: 8) {
                header(ctx)
                Text(ctx.state.question).font(.subheadline).lineLimit(2)
                if let tool = ctx.state.tool, !tool.isEmpty {
                    Text(tool).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                buttons(ctx)
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.35))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(ctx.attributes.name).font(.headline).lineLimit(1) }
                DynamicIslandExpandedRegion(.trailing) { Circle().fill(amber).frame(width: 8, height: 8) }
                DynamicIslandExpandedRegion(.center) { Text(ctx.state.question).font(.caption).lineLimit(2) }
                DynamicIslandExpandedRegion(.bottom) { buttons(ctx) }
            } compactLeading: {
                Text(ctx.attributes.name).font(.caption2).lineLimit(1)
            } compactTrailing: {
                Circle().fill(amber).frame(width: 8, height: 8)
            } minimal: {
                Circle().fill(amber).frame(width: 8, height: 8)
            }
        }
    }

    private func header(_ ctx: ActivityViewContext<PaneActivityAttributes>) -> some View {
        HStack(spacing: 6) {
            Circle().fill(amber).frame(width: 8, height: 8)
            Text(ctx.attributes.name).font(.headline).lineLimit(1)
            Spacer()
            Text(ctx.state.status == "sent" ? "Sent" : "Needs you").font(.caption).foregroundStyle(amber)
        }
    }

    @ViewBuilder
    private func buttons(_ ctx: ActivityViewContext<PaneActivityAttributes>) -> some View {
        if ctx.state.status == "needsYou" {
            HStack(spacing: 10) {
                Button(intent: ApprovePaneIntent(paneId: ctx.attributes.paneId)) { Text("Approve").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.blue)
                Button(intent: DenyPaneIntent(paneId: ctx.attributes.paneId)) { Text("Deny").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).tint(.gray)
            }
        }
    }
}
