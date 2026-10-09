import SwiftUI

struct PairView: View {
    @Environment(AppModel.self) private var model
    @State private var address = SharedConfig.baseURL?.absoluteString ?? ""
    @State private var code = ""
    @State private var error: String?
    @State private var busy = false
    @State private var paired = 0
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TileRow(symbol: "macbook.and.iphone", title: "Open True on your Mac", detail: "Choose Remote Access")
                    TileRow(symbol: "network", title: "Enter its address", detail: "Shown under Remote Access")
                    TileRow(symbol: "number", title: "Type the 6-digit code", detail: "It refreshes every few minutes")
                } header: { Text("Three steps") }

                Section("Mac address") {
                    TextField("your-mac.tailnet.ts.net:8444", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL).textContentType(.URL)
                }

                Section {
                    ZStack {
                        HStack(spacing: 8) {
                            ForEach(0..<6, id: \.self) { i in
                                Text(i < code.count ? String(Array(code)[i]) : "")
                                    .font(.title.monospacedDigit().weight(.semibold))
                                    .frame(maxWidth: .infinity).frame(height: 52)
                                    .background(.fill.quaternary, in: .rect(cornerRadius: 10))
                            }
                        }
                        TextField("", text: $code)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .focused($codeFocused).opacity(0.011)
                            .onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(6)) }
                            .accessibilityLabel("Pairing code")
                    }
                    .contentShape(.rect).onTapGesture { codeFocused = true }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                } header: { Text("Pairing code") } footer: {
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.attention)
                    }
                }
            }
            .navigationTitle("Pair this phone")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                Button { Task { await pair() } } label: {
                    Group { if busy { ProgressView() } else { Text("Pair") } }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                .disabled(code.count < 6 || address.isEmpty || busy)
                .padding(.horizontal, 20).padding(.bottom, 8)
            }
            .sensoryFeedback(.success, trigger: paired)
            .sensoryFeedback(.error, trigger: error)
        }
    }

    private func pair() async {
        busy = true; error = nil
        error = await model.pair(address: address, code: code)
        if error != nil { code = "" } else { paired += 1 }
        busy = false
    }
}
