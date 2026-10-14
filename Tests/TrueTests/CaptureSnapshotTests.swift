import Testing
import Foundation
import SwiftUI
import AppKit
@testable import True

/// Renders the capture + annotate surfaces to PNGs (no launching True.app).
/// `TRUE_SNAPSHOT_DIR=$PWD/proofs/capture-p1 swift test --filter CaptureSnapshotTests`.
@MainActor
@Suite(.enabled(if: !(ProcessInfo.processInfo.environment["TRUE_SNAPSHOT_DIR"] ?? "").isEmpty,
                "TRUE_SNAPSHOT_DIR not set"))
struct CaptureSnapshotTests {
    private var dir: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["TRUE_SNAPSHOT_DIR"] ?? "/tmp") }

    private func write(_ view: NSView, size: NSSize, _ name: String) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { Issue.record("no rep"); return }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { Issue.record("no png"); return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func snapshot<V: View>(_ name: String, width: CGFloat, height: CGFloat? = nil, @ViewBuilder _ view: () -> V) throws {
        let root = view().frame(width: width, height: height, alignment: .topLeading).environment(\.colorScheme, .dark).background(Theme.background)
        let host = NSHostingView(rootView: root)
        let fitted = host.fittingSize
        try write(host, size: NSSize(width: width, height: height ?? max(fitted.height, 60)), name)
    }

    // MARK: a fake "desktop" so the stills have something real-looking underneath

    private func screenImage(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(CGColor(srgbRed: 0.22, green: 0.25, blue: 0.32, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        func win(_ r: CGRect, _ c: CGColor) {
            ctx.setFillColor(c); ctx.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil)); ctx.fillPath()
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.08)); ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 26))
        }
        win(CGRect(x: 40, y: 40, width: CGFloat(w) * 0.55, height: CGFloat(h) * 0.7), CGColor(srgbRed: 0.16, green: 0.17, blue: 0.21, alpha: 1))
        win(CGRect(x: CGFloat(w) * 0.5, y: CGFloat(h) * 0.3, width: CGFloat(w) * 0.42, height: CGFloat(h) * 0.6), CGColor(srgbRed: 0.2, green: 0.22, blue: 0.3, alpha: 1))
        // text-like bars and a contact-card block (something worth censoring)
        for i in 0..<14 {
            let wd = CGFloat(120 + (i * 53) % 220)
            ctx.setFillColor(CGColor(gray: 1, alpha: i % 3 == 0 ? 0.5 : 0.28))
            ctx.fill(CGRect(x: 70, y: 90 + CGFloat(i) * 22, width: wd, height: 8))
        }
        for i in 0..<5 {
            ctx.setFillColor(CGColor(srgbRed: [0.9, 0.4, 0.3, 0.3, 0.9][i], green: [0.4, 0.8, 0.5, 0.6, 0.8][i], blue: [0.3, 0.9, 0.9, 0.4, 0.2][i], alpha: 1))
            ctx.fill(CGRect(x: CGFloat(w) * 0.55 + CGFloat(i) * 46, y: CGFloat(h) * 0.45, width: 34, height: 90))
        }
        return ctx.makeImage()!
    }

    private let fullActions = [
        FinishAction(id: "cancel", title: "Cancel", action: {}),
        FinishAction(id: "copy", title: "Copy", symbol: "doc.on.doc", shortcut: "c", action: {}),
        FinishAction(id: "send", title: "Send", symbol: "paperplane", action: {}),
        FinishAction(id: "save", title: "Save", primary: true, shortcut: "s", action: {}),
    ]

    private func annotated(_ img: CGImage) -> AnnotationState {
        let st = AnnotationState(image: img)
        let w = st.strokeWidth
        st.doc.add(Stroke(mark: .censor(CGRect(x: 70, y: 126, width: 200, height: 40)), color: .ink, width: w, censor: .pixelate))
        st.doc.add(Stroke(mark: .censor(CGRect(x: 70, y: 214, width: 240, height: 40)), color: .ink, width: w, censor: .blur))
        st.doc.add(Stroke(mark: .highlight([CGPoint(x: 70, y: 302), CGPoint(x: 200, y: 304), CGPoint(x: 330, y: 301)]), color: .amber, width: w))
        st.doc.add(Stroke(mark: .rect(CGRect(x: 520, y: 250, width: 250, height: 130)), color: .red, width: w))
        st.doc.add(Stroke(mark: .arrow(from: CGPoint(x: 430, y: 120), to: CGPoint(x: 560, y: 245)), color: .blue, width: w))
        st.doc.add(Stroke(mark: .step(at: CGPoint(x: 52, y: 135)), color: .red, width: w))
        st.doc.add(Stroke(mark: .step(at: CGPoint(x: 52, y: 223)), color: .red, width: w))
        st.doc.add(Stroke(mark: .text("Check this one", at: CGPoint(x: 440, y: 92)), color: .white, width: 28))
        return st
    }

    // MARK: stills

    @Test func overlayMidDrag() throws {
        let img = screenImage(1200, 760)
        let v = CaptureView(frame: NSRect(x: 0, y: 0, width: 1200, height: 760), still: img, windows: [])
        v.previewDrag(selection: CGRect(x: 300, y: 170, width: 520, height: 330), cursor: CGPoint(x: 820, y: 500))
        try write(v, size: NSSize(width: 1200, height: 760), "01-overlay-mid-drag")
    }

    @Test func windowSnap() throws {
        let img = screenImage(1200, 760)
        let v = CaptureView(frame: NSRect(x: 0, y: 0, width: 1200, height: 760), still: img, windows: [])
        v.hoverWindow = CGRect(x: 600, y: 228, width: 504, height: 456)
        v.cursor = CGPoint(x: 700, y: 400)
        try write(v, size: NSSize(width: 1200, height: 760), "02-window-snap")
    }

    @Test func editorToolbar() throws {
        // The real bar is a glass capsule over the screenshot; glass can't render offscreen, so a dark capsule stands in.
        let st = AnnotationState(image: screenImage(800, 500))
        st.tool = .censor
        try snapshot("03-editor-toolbar", width: 900, height: 120) {
            AnnotationToolbar(state: st, finish: fullActions, floating: false).fixedSize()
                .background(Color(white: 0.12), in: .rect(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
                .padding(24)
        }
    }

    @Test func annotatedSample() throws {
        let img = screenImage(800, 500)
        let doc = annotated(img).doc
        let out = try #require(MarkupRender.render(base: img, doc: doc))
        let ns = NSImageView(image: NSImage(cgImage: out, size: NSSize(width: 800, height: 500)))
        try write(ns, size: NSSize(width: 800, height: 500), "04-annotated-sample")
    }

    @Test func cropMode() throws {
        let st = AnnotationState(image: screenImage(800, 500))
        st.tool = .crop
        st.doc.setCrop(CGRect(x: 120, y: 70, width: 480, height: 300))
        try snapshot("05-crop-mode", width: 800, height: 500) { AnnotationCanvas(state: st, corner: 0) }
    }

    @Test func colourStrokePopover() throws {
        let st = AnnotationState(image: screenImage(100, 100))
        try snapshot("06-colour-stroke-popover", width: 320) { StylePanel(state: st).padding(14).background(Color(white: 0.11)) }
    }

    @Test func permissionPrompt() throws {
        try snapshot("07-permission-prompt", width: 560, height: 90) {
            CapturePermissionPrompt(openSettings: {}, dismiss: {}).padding(20)
        }
    }

    @Test func panelZoomMarkUp() throws {
        let img = screenImage(800, 500)
        try snapshot("08-panel-zoom-mark-up", width: 520, height: 400) {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    IconButton(symbol: "chevron.left", help: "Back to all (Esc)") {}
                    Text("2m ago").font(.caption.monospaced()).foregroundStyle(.secondary).padding(.leading, 2)
                    Spacer()
                    IconButton(symbol: "pencil.tip.crop.circle", help: "Mark up", selected: true) {}
                    IconButton(symbol: "doc.on.doc", help: "Copy image (⌘C)") {}
                    IconButton(symbol: "paperplane", help: "Send to session") {}
                }.padding(.horizontal, 10).frame(height: 40)
                AnnotationToolbar(state: AnnotationState(image: img), finish: Array(fullActions.dropFirst().dropFirst()), floating: false)
                Image(decorative: img, scale: 1).resizable().aspectRatio(contentMode: .fit).padding(8)
            }
        }
    }
}
