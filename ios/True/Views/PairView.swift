import SwiftUI

struct PairView: View {
    @Environment(AppModel.self) private var model
    @State private var address = SharedConfig.baseURL?.absoluteString ?? ""
    @State private var code = ""
    @State private var error: String?
    @State private var busy = false
    @State private var paired = 0
    @State private var scanning = false
    @FocusState private var codeFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                if let mac = model.nearbyMac {
                    Section {
                        TileRow(symbol: "macbook.and.iphone", title: "\(mac.name) is nearby", detail: "Scan the code on its screen to pair",
                                symbolStyle: AnyShapeStyle(.tint), titleLines: 2) { EmptyView() }
                        Button("Scan the code") { scanning = true }
                        Button("Type the code") { address = mac.address; codeFocused = true }
                    }
                    .transition(.opacity)
                } else if [.poweredOff, .unauthorized, .unsupported].contains(model.bluetoothState) {
                    Section {
                        Label("Turn on Bluetooth to find your Mac automatically", systemImage: "antenna.radiowaves.left.and.right.slash")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button { scanning = true } label: {
                        TileRow(symbol: "qrcode.viewfinder", title: "Scan the code on your Mac", detail: "Fills the address and code for you") {
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }.tint(.primary)
                }

                Section {
                    TileRow(symbol: "macbook.and.iphone", title: "Open True on your Mac", detail: "Choose Remote Access")
                    TileRow(symbol: "network", title: "Enter its address", detail: "Shown under Remote Access")
                    TileRow(symbol: "number", title: "Type the 6-digit code", detail: "It refreshes every few minutes")
                } header: { Text("Or do it by hand") }

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
            .sheet(isPresented: $scanning) { ScanSheet { link in apply(link) } }
            .task {
                if let l = model.pendingPairLink { address = l.address; model.pendingPairLink = nil }
                #if DEBUG
                if model.uiState == "pair-scan" { scanning = true }
                #endif
            }
            .animation(.default, value: model.nearbyMac)
            .onAppear { if scenePhase == .active { model.startNearbyScan() } }
            .onDisappear { model.stopNearbyScan() }
            .onChange(of: scenePhase) { _, p in
                if p == .active { model.startNearbyScan() } else { model.stopNearbyScan() }
            }
            .sensoryFeedback(.success, trigger: paired)
            .sensoryFeedback(.error, trigger: error)
        }
    }

    private func apply(_ link: PairLink) {
        address = link.address
        if let c = link.code { code = c; Task { await pair() } }
    }

    private func pair() async {
        busy = true; error = nil
        error = await model.pair(address: address, code: code)
        if error != nil { code = "" } else { paired += 1 }
        busy = false
    }
}
