import UIKit
import UniformTypeIdentifiers

/// Share text, images or files from any app straight to the Mac (POST /api/drop with the token from the shared Keychain).
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.font = .preferredFont(forTextStyle: .headline); label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0; label.textAlignment = .center; label.text = "Sending to your Mac…"
        let spinner = UIActivityIndicatorView(style: .medium); spinner.startAnimating()
        let stack = UIStackView(arrangedSubviews: [spinner, label]); stack.axis = .vertical; stack.spacing = 12; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: view.centerXAnchor), stack.centerYAnchor.constraint(equalTo: view.centerYAnchor), stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)])
        Task { await send() }
    }

    private func send() async {
        guard let base = SharedConfig.baseURL else { return finish("Open True and pair this phone first.") }
        let session = RemoteSession(baseURL: base, store: KeychainTokenStore())
        guard await session.isPaired else { return finish("Open True and pair this phone first.") }
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var sent = 0
        do {
            for p in providers {
                guard let (data, name) = await load(p) else { continue }
                _ = try await session.drop(data, filename: name); sent += 1
            }
        } catch RemoteError.unauthorized { return finish("Pairing expired — open True to pair again.")
        } catch { return finish("Couldn't reach your Mac.") }
        finish(sent == 0 ? "Nothing to send." : "Sent \(sent) item\(sent == 1 ? "" : "s") to your Mac.")
    }

    private func load(_ p: NSItemProvider) async -> (Data, String)? {
        if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || p.hasItemConformingToTypeIdentifier(UTType.image.identifier) || p.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            let type = [UTType.fileURL, .image, .data].first { p.hasItemConformingToTypeIdentifier($0.identifier) }!
            return await withCheckedContinuation { cont in
                p.loadFileRepresentation(forTypeIdentifier: type == .fileURL ? UTType.data.identifier : type.identifier) { url, _ in
                    guard let url, let d = try? Data(contentsOf: url) else { return cont.resume(returning: nil) }
                    cont.resume(returning: (d, url.lastPathComponent))
                }
            }
        }
        if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) || p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let id = p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) ? UTType.plainText.identifier : UTType.url.identifier
            let item = try? await p.loadItem(forTypeIdentifier: id)
            let s = (item as? String) ?? (item as? URL)?.absoluteString
            return s.map { (Data($0.utf8), "Shared text.txt") }
        }
        return nil
    }

    private func finish(_ message: String) {
        label.text = message
        UIAccessibility.post(notification: .announcement, argument: message)
        Task { try? await Task.sleep(for: .seconds(1.4)); extensionContext?.completeRequest(returningItems: nil) }
    }
}
