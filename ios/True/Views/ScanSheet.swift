import SwiftUI
import VisionKit
import AVFoundation

/// Scans the QR on the Mac's Remote Access sheet. Hands the first parseable `true://pair` link back and dismisses.
struct ScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (PairLink) -> Void
    @State private var denied = AVCaptureDevice.authorizationStatus(for: .video) == .denied
    @State private var misread = false
    @State private var scanned = 0

    private var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable && !denied }

    var body: some View {
        NavigationStack {
            Group {
                if canScan {
                    QRScanner(onCode: handle)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) { footer }
                } else {
                    unavailable
                }
            }
            .navigationTitle("Scan").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(role: .close) { dismiss() } } }
            .sensoryFeedback(.success, trigger: scanned)
        }
        .presentationDetents([.large])
        .task { if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined { denied = !(await AVCaptureDevice.requestAccess(for: .video)) } }
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label("Camera isn't available", systemImage: "camera.fill")
        } description: {
            Text(denied ? "True needs the camera to read the code. You can allow it in Settings, or type the address and code instead."
                        : "Type the address and code from your Mac's Remote Access window instead.")
        } actions: {
            if denied {
                Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                    .buttonStyle(.glassProminent)
            }
            if denied { Button("Type it instead") { dismiss() }.buttonStyle(.glass) }
            else { Button("Type it instead") { dismiss() }.buttonStyle(.glassProminent) }
        }
    }

    private var footer: some View {
        Label(misread ? "That's not a True pairing code" : "Point the camera at the code on your Mac",
              systemImage: misread ? "exclamationmark.triangle.fill" : "qrcode.viewfinder")
            .font(.footnote.weight(.medium))
            .foregroundStyle(misread ? AnyShapeStyle(.attention) : AnyShapeStyle(.primary))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 24)
            .animation(.default, value: misread)
    }

    private func handle(_ payload: String) {
        guard let link = PairLink(string: payload) else { misread = true; return }
        scanned += 1
        onScan(link)
        dismiss()
    }

    private struct QRScanner: UIViewControllerRepresentable {
        let onCode: (String) -> Void
        func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }
        func makeUIViewController(context: Context) -> DataScannerViewController {
            let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                               qualityLevel: .balanced, recognizesMultipleItems: false,
                                               isHighlightingEnabled: true)
            vc.delegate = context.coordinator
            try? vc.startScanning()
            return vc
        }
        func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
        static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }

        final class Coordinator: NSObject, DataScannerViewControllerDelegate {
            let onCode: (String) -> Void
            init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
            func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
                for case .barcode(let b) in addedItems { if let s = b.payloadStringValue { onCode(s) } }
            }
        }
    }
}
