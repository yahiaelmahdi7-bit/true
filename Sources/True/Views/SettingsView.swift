import SwiftUI

/// ⌘, — four settings, applied live to every open pane (EmbeddedTerminal.updateNSView).
struct SettingsView: View {
    @AppStorage(TerminalSettings.fontFamilyKey) private var family = TerminalSettings.systemMono
    @AppStorage(TerminalSettings.fontSizeKey) private var size = TerminalSettings.defaultFontSize
    @AppStorage(TerminalSettings.cursorKey) private var cursor = TerminalSettings.Cursor.steadyBlock.rawValue
    @AppStorage(TerminalSettings.scrollbackKey) private var scrollback = TerminalSettings.defaultScrollback

    var body: some View {
        Form {
            Picker("Font", selection: $family) {
                Text("System Mono").tag(TerminalSettings.systemMono)
                Divider()
                ForEach(TerminalSettings.fixedPitchFamilies, id: \.self) { Text($0).tag($0) }
            }
            Stepper(value: $size, in: 9...32, step: 1) { Text("Size: \(Int(size)) pt") }
            Picker("Cursor", selection: $cursor) {
                ForEach(TerminalSettings.Cursor.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Stepper(value: $scrollback, in: 500...100_000, step: 500) {
                Text("Scrollback: \(scrollback.formatted()) lines")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
