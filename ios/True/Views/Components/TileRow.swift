import SwiftUI

/// The one structural device: 44pt icon tile + title over detail + optional trailing status.
/// At accessibility sizes the trailing content wraps under the text so the title never truncates.
struct TileRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    var titleStyle: AnyShapeStyle = AnyShapeStyle(.primary)
    var symbolStyle: AnyShapeStyle = AnyShapeStyle(.secondary)
    var truncation: Text.TruncationMode = .middle
    var titleLines = 1
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: stacked ? .top : .center, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(symbolStyle)
                .frame(width: 44, height: 44)
                .background(.fill.quaternary, in: .rect(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            if stacked {
                VStack(alignment: .leading, spacing: 4) { text; trailing }
            } else {
                text
                Spacer(minLength: 8)
                trailing
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(titleStyle)
                .lineLimit(typeSize.isAccessibilitySize ? nil : titleLines)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1).truncationMode(truncation)
            }
        }
    }
}

extension TileRow where Trailing == EmptyView {
    init(symbol: String, title: String, detail: String? = nil, titleStyle: AnyShapeStyle = AnyShapeStyle(.primary),
         symbolStyle: AnyShapeStyle = AnyShapeStyle(.secondary), truncation: Text.TruncationMode = .middle) {
        self.init(symbol: symbol, title: title, detail: detail, titleStyle: titleStyle, symbolStyle: symbolStyle, truncation: truncation, trailing: { EmptyView() })
    }
}
