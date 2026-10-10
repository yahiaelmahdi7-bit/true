import SwiftUI

/// ⌘, — six settings, applied live to every open pane (EmbeddedTerminal.updateNSView).
struct SettingsView: View {
    @AppStorage(TerminalSettings.fontFamilyKey) private var family = TerminalSettings.systemMono
    @AppStorage(TerminalSettings.fontSizeKey) private var size = TerminalSettings.defaultFontSize
    @AppStorage(TerminalSettings.cursorKey) private var cursor = TerminalSettings.Cursor.steadyBlock.rawValue
    @AppStorage(TerminalSettings.scrollbackKey) private var scrollback = TerminalSettings.defaultScrollback
    @AppStorage(TerminalSettings.colorKey) private var color = TerminalSettings.defaultColor
    @AppStorage(TerminalSettings.overseerKey) private var overseer = true
    @AppStorage(TerminalSettings.watcherKey) private var watcher = true
    @AppStorage(TerminalSettings.jevRoutingKey) private var jevRouting = true
    @AppStorage(NovaSettings.enabledKey) private var novaOn = true
    @AppStorage(NovaSettings.wakeKey) private var novaWake = true
    @AppStorage(NovaSettings.hotkeyKey) private var novaKey = Hotkey.rightOption.rawValue
    @AppStorage(NovaSettings.effortKey) private var novaEffort = "low"

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
            Toggle("Colour in terminals", isOn: $color)
            Toggle("Overseer", isOn: $overseer)
                .help("After each Claude turn in a True pane, Jev reads what was asked and answered and shows a verdict. Off: no calls.")
                .onChange(of: overseer) { _, on in if !on { OverseerStore.shared.clearAll() } }
            Toggle("Watcher", isOn: $watcher)
                .help("Watches your builders, unpushed work and failed sessions, and proposes fixes in the Hub for you to approve. Off: no calls, no runs.")
            Toggle("Jev routing", isOn: $jevRouting)
                .help("The Command bar (⌘K) asks Jev where each line should go. Off: prefix rules and defaults only, no calls.")
            Section("Nova (voice) — takes effect on relaunch") {
                Toggle("Nova", isOn: $novaOn)
                Toggle("Wake word “Nova” (mic always on)", isOn: $novaWake)
                Picker("Push-to-talk", selection: $novaKey) { ForEach(Hotkey.allCases) { Text($0.label).tag($0.rawValue) } }
                Picker("Brain effort", selection: $novaEffort) { Text("low").tag("low"); Text("medium").tag("medium") }
                LabeledContent("Haiku key", value: Vault.has("anthropic", envFallback: ["ANTHROPIC_API_KEY"]) ? "set" : "missing — reflex-only")
                LabeledContent("ElevenLabs key", value: Vault.has("elevenlabs") ? "set" : "none — system voice")
                ForEach([("Microphone", "Privacy_Microphone"), ("Speech Recognition", "Privacy_SpeechRecognition"), ("Accessibility", "Privacy_Accessibility"),
                         ("Screen Recording", "Privacy_ScreenCapture"), ("Automation", "Privacy_Automation")], id: \.0) { n, a in
                    LabeledContent(n) { Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(a)")!) } }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
