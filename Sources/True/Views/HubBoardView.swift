import SwiftUI

/// Colours for the Work board in dark (the main mode, black first) and light. One accent: amber. The rest of the
/// Hub still draws with `Theme` (white on black); everything on this board and in its sheets reads the scheme.
struct HubInk {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    var primary: Color { dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88) }
    var secondary: Color { dark ? Color.white.opacity(0.62) : Color.black.opacity(0.58) }
    var faint: Color { dark ? Color.white.opacity(0.40) : Color.black.opacity(0.40) }
    var tile: Color { dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045) }
    var tileStroke: Color { dark ? Color.white.opacity(0.09) : Color.black.opacity(0.09) }
    var chip: Color { dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07) }
    var accent: Color { dark ? Color(red: 1.0, green: 0.68, blue: 0.30) : Color(red: 0.80, green: 0.42, blue: 0.0) }
    var failed: Color { dark ? Color(red: 1.0, green: 0.42, blue: 0.40) : Color(red: 0.80, green: 0.18, blue: 0.16) }
    /// The loud capsule: inverted, same device as the attention pill.
    var loudFill: Color { dark ? .white : .black }
    var loudText: Color { dark ? .black : .white }
    /// The Hub card's own surface behind the glass.
    var surface: Color { dark ? .black : Color(white: 0.97) }

    func tone(_ t: TriageTone) -> Color {
        switch t {
        case .needsYou: return accent
        case .failed: return failed
        case .working: return primary
        case .done, .idle: return secondary
        }
    }
}

/// A capsule button: loud (inverted) for the tile's one main action, quiet for the rest.
struct HubTileButton: View {
    let label: String
    var loud = true
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let ink = HubInk(scheme)
        Button(action: action) {
            Text(label).font(.callout.weight(.semibold)).lineLimit(1).fixedSize()
                .foregroundStyle(loud ? ink.loudText : ink.primary)
                .padding(.horizontal, 14).frame(height: 28)
                .background(loud ? ink.loudFill : ink.chip, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// One tile. Needs-you tiles carry one main button (failures add "Look"); a Running tile shows where it runs,
/// the live step, time and cost. Tapping the body opens the detail sheet.
struct HubTileView: View {
    let tile: HubTile
    let now: Double
    var running = false
    let onMain: () -> Void
    var onSecondary: () -> Void = {}
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    static let height: CGFloat = 132
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }
    private var newest: Double { tile.items.map(\.at).max() ?? now }

    var body: some View {
        let ink = HubInk(scheme)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if running, let item = tile.items.first { whereChip(item.runsOn, ink) } else {
                    Circle().fill(ink.tone(tile.tone)).frame(width: 7, height: 7)
                    if tile.kind == .failures { Text("Failed").font(.caption.weight(.medium)).foregroundStyle(ink.failed) }
                }
                Spacer(minLength: 4)
                if running, let cost = tile.items.first?.cost { Text(String(format: "$%.2f", cost)).font(.caption.monospacedDigit()).foregroundStyle(ink.secondary) }
                if tile.kind != .more { Text(HubTriage.age(now - newest)).font(.caption.monospacedDigit()).foregroundStyle(ink.secondary) }
            }
            Text(tile.title).font(.headline).foregroundStyle(ink.primary).lineLimit(2).multilineTextAlignment(.leading)
            if !tile.detail.isEmpty {
                Text(tile.detail).font(.callout).foregroundStyle(ink.secondary).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                HubTileButton(label: tile.button, loud: !running && tile.tone != .working, action: onMain)
                if !tile.secondary.isEmpty { HubTileButton(label: tile.secondary, loud: false, action: onSecondary) }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .topLeading)
        .background(hovering ? ink.tile.opacity(1.6) : ink.tile, in: shape)
        .overlay(shape.strokeBorder(ink.tileStroke, lineWidth: 0.5))
        .contentShape(shape)
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.title), \(tile.detail)")
        .accessibilityAction(named: tile.button, onMain)
        .accessibilityAction(named: "Details", onOpen)
    }

    private func whereChip(_ w: HubWhere, _ ink: HubInk) -> some View {
        HStack(spacing: 4) {
            Image(systemName: w.symbol).font(.system(size: 10, weight: .medium))
            Text(w.label).font(.caption.weight(.medium))
        }
        .foregroundStyle(ink.secondary).padding(.horizontal, 8).padding(.vertical, 3)
        .background(ink.chip, in: .capsule)
    }
}

/// The Work view's first screen: Needs you / Running / Done today as tiles. No rows, no backlog.
struct HubBoardView: View {
    let board: HubBoard
    let now: Double
    var onNew: () -> Void = {}
    let onMain: (HubTile) -> Void
    var onSecondary: (HubTile) -> Void = { _ in }
    let onOpenTile: (HubTile) -> Void
    let onItem: (TriageItem) -> Void
    /// Test hook: start with Done today open.
    var doneStartsOpen = false
    @State private var doneOpen = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ink = HubInk(scheme)
        GeometryReader { geo in
            if board.isEmpty {
                VStack(spacing: 14) {
                    Text("Nothing needs you").font(.title3.weight(.medium)).foregroundStyle(ink.primary)
                    HubTileButton(label: "New", action: onNew)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: HubLayout.tileColumns(width: geo.size.width))
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !board.needsYou.isEmpty {
                            band("Needs you", count: board.needsYouCount, ink) {
                                LazyVGrid(columns: cols, spacing: 12) {
                                    ForEach(board.needsYou) { t in
                                        HubTileView(tile: t, now: now, onMain: { onMain(t) }, onSecondary: { onSecondary(t) }, onOpen: { onOpenTile(t) })
                                    }
                                }
                            }
                        }
                        if !board.running.isEmpty {
                            band("Running", count: board.running.count, ink) {
                                LazyVGrid(columns: cols, spacing: 12) {
                                    ForEach(board.running) { t in
                                        HubTileView(tile: t, now: now, running: true, onMain: { onMain(t) }, onOpen: { onOpenTile(t) })
                                    }
                                }
                            }
                        }
                        if !board.done.isEmpty { doneStrip(ink) }
                    }
                    .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear { if doneStartsOpen { doneOpen = true } }
    }

    private func band<C: View>(_ title: String, count: Int, _ ink: HubInk, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(ink.primary)
                Text("\(count)").font(.callout.monospacedDigit()).foregroundStyle(ink.secondary)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// One quiet strip; tap opens the list.
    private func doneStrip(_ ink: HubInk) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(reduceMotion ? nil : .snappy) { doneOpen.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 13)).foregroundStyle(ink.secondary)
                    Text("Done today").font(.callout.weight(.semibold)).foregroundStyle(ink.primary)
                    Text("\(board.done.count)").font(.callout.monospacedDigit()).foregroundStyle(ink.secondary)
                    Text(board.done.prefix(3).map(\.title).joined(separator: " · "))
                        .font(.callout).foregroundStyle(ink.faint).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(ink.secondary)
                        .rotationEffect(.degrees(doneOpen ? 90 : 0))
                }
                .padding(.horizontal, 14).frame(height: 40).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(doneOpen ? "Hides the list" : "Shows what finished today")
            if doneOpen {
                VStack(spacing: 0) {
                    ForEach(board.done) { i in HubMiniRow(item: i, now: now, onAction: onItem) }
                }
                .padding(.bottom, 6)
            }
        }
        .background(ink.tile.opacity(0.7), in: shape)
        .overlay(shape.strokeBorder(ink.tileStroke, lineWidth: 0.5))
    }
}

/// A compact row for sheets and the Done strip: title, project, age, one button, optional dismiss.
struct HubMiniRow: View {
    let item: TriageItem
    let now: Double
    let onAction: (TriageItem) -> Void
    var onDismiss: ((TriageItem) -> Void)?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = HubInk(scheme)
        HStack(spacing: 10) {
            Circle().fill(ink.tone(item.tone)).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.body).foregroundStyle(ink.primary).lineLimit(1).truncationMode(.middle)
                Text([item.project, item.subtitle].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(ink.secondary).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Text(HubTriage.age(now - item.at)).font(.callout.monospacedDigit()).foregroundStyle(ink.secondary)
            if !item.actionLabel.isEmpty {
                HubTileButton(label: item.actionLabel, loud: item.tone == .needsYou || item.tone == .failed) { onAction(item) }
            }
            if let onDismiss {
                Button { onDismiss(item) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(ink.secondary)
                        .frame(width: 24, height: 24).contentShape(.circle)
                }
                .buttonStyle(.plain).help("Dismiss").accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: item.actionLabel) { onAction(item) }
    }
}

/// A tile's detail sheet: what it stands for, each item with its own button, and Dismiss. Everything beyond the
/// tile's one main button lives here.
struct HubTileSheet: View {
    let tile: HubTile
    let now: Double
    let onItem: (TriageItem) -> Void
    var onDismissItem: ((TriageItem) -> Void)?
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    static let width: CGFloat = 520

    var body: some View {
        let ink = HubInk(scheme)
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tile.title).font(.title3.weight(.semibold)).foregroundStyle(ink.primary)
                    if !tile.detail.isEmpty { Text(tile.detail).font(.callout).foregroundStyle(ink.secondary).lineLimit(2) }
                }
                Spacer(minLength: 8)
                HubTileButton(label: "Done", loud: false, action: onClose).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            Divider().overlay(ink.tileStroke)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tile.items) { HubMiniRow(item: $0, now: now, onAction: onItem, onDismiss: onDismissItem) }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: Self.width).frame(minHeight: 200, maxHeight: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background(ink.surface)
    }
}

/// The backlog's own view: a count in the header opens it. Old rows, a Clear button, a way back.
struct HubBacklogView: View {
    let items: [TriageItem]
    let now: Double
    let onItem: (TriageItem) -> Void
    var onDismiss: (TriageItem) -> Void = { _ in }
    var onClear: ([String]) -> Void = { _ in }
    let onBack: () -> Void
    /// Most rows drawn at once; the rest are counted.
    static let cap = 150
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = HubInk(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HubTileButton(label: "Back", loud: false, action: onBack)
                Text("Backlog").font(.callout.weight(.semibold)).foregroundStyle(ink.primary)
                Text("\(items.count)").font(.callout.monospacedDigit()).foregroundStyle(ink.secondary)
                Spacer()
                if !items.isEmpty { HubTileButton(label: "Clear backlog", loud: false) { onClear(items.map(\.id)) } }
            }
            .padding(.horizontal, 20).padding(.bottom, 10)
            if items.isEmpty {
                Text("Nothing older").font(.callout).foregroundStyle(ink.faint).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items.prefix(Self.cap)) { HubMiniRow(item: $0, now: now, onAction: onItem, onDismiss: onDismiss) }
                        if items.count > Self.cap {
                            Text("+ \(items.count - Self.cap) older").font(.callout).foregroundStyle(ink.faint).padding(10)
                        }
                    }
                }
            }
        }
    }
}
