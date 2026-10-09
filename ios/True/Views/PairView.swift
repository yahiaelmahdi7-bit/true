import SwiftUI

struct PairView: View {
    @Environment(AppModel.self) private var model
    @State private var address = SharedConfig.baseURL?.absoluteString ?? ""
    @State private var code = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("On your Mac open True → Remote Access, then enter its address and the 6-digit code.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mac address").font(.footnote).foregroundStyle(.secondary)
                        TextField("your-mac.tailnet.ts.net:8444", text: $address)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .padding(12).background(.fill.quaternary, in: .rect(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pairing code").font(.footnote).foregroundStyle(.secondary)
                        ZStack {
                            HStack(spacing: 8) {
                                ForEach(0..<6, id: \.self) { i in
                                    Text(i < code.count ? String(Array(code)[i]) : "")
                                        .font(.title.monospacedDigit().weight(.semibold))
                                        .frame(maxWidth: .infinity).frame(height: 56)
                                        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
                                }
                            }
                            TextField("", text: $code)
                                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                                .focused($codeFocused).opacity(0.011)
                                .onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(6)) }
                                .accessibilityLabel("Pairing code")
                        }
                        .contentShape(.rect).onTapGesture { codeFocused = true }
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.attention) }
                    Button { Task { await pair() } } label: {
                        Group { if busy { ProgressView() } else { Text("Pair") } }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(code.count < 6 || address.isEmpty || busy)
                }
                .padding(20)
            }
            .navigationTitle("Pair this phone")
        }
    }

    private func pair() async {
        busy = true; error = nil
        error = await model.pair(address: address, code: code)
        if error != nil { code = "" }
        busy = false
    }
}
