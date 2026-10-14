import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI

enum CaptureOutcome { case cancel, copy(AnnotationState), save(AnnotationState), send(AnnotationState) }

// MARK: - The per-screen overlay view

/// One screen's frozen still, dimmed, with the region picker (drag / snap / loupe) and — once a region is
/// chosen — the annotation editor sitting exactly over the chosen pixels.
final class CaptureView: NSView {
    enum Phase { case aiming, dragging, editing }

    let still: CGImage
    /// Window frames in this view's coordinates (top-left), front to back.
    var windows: [CGRect]
    var onOutcome: (CaptureOutcome) -> Void = { _ in }
    var onActivate: () -> Void = {}

    private(set) var phase: Phase = .aiming
    private(set) var selection: CGRect?
    private(set) var state: AnnotationState?
    var cursor: CGPoint?
    var hoverWindow: CGRect?
    var snapOn = true
    private var anchor: CGPoint?
    private var downPoint: CGPoint?
    private var dragged = false
    private var spaceHeld = false
    private var lastPoint: CGPoint = .zero
    private var canvasHost: NSView?
    private var toolbarHost: NSView?

    init(frame: NSRect, still: CGImage, windows: [CGRect]) {
        self.still = still; self.windows = windows
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: phase == .editing ? .arrow : .crosshair) }

    private var imageSize: CGSize { CGSize(width: still.width, height: still.height) }
    private var bounds0: CGRect { CGRect(origin: .zero, size: bounds.size) }

    // MARK: drawing

    override func draw(_ dirty: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext else { return }
        let whole = bounds0
        NSImage(cgImage: still, size: whole.size).draw(in: whole, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let hole = selection ?? hoverWindow
        g.setFillColor(NSColor.black.withAlphaComponent(0.46).cgColor)
        let dim = CGMutablePath(); dim.addRect(whole)
        if let h = hole { dim.addRect(h) }
        g.addPath(dim); g.fillPath(using: .evenOdd)

        if selection == nil, let w = hoverWindow, phase == .aiming {
            let path = CGPath(roundedRect: w.insetBy(dx: 1, dy: 1), cornerWidth: 8, cornerHeight: 8, transform: nil)
            g.setFillColor(NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.16).cgColor); g.addPath(path); g.fillPath()
            g.setStrokeColor(NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1).cgColor); g.setLineWidth(2); g.addPath(path); g.strokePath()
            label(CaptureLogic.sizeLabel(CaptureLogic.pixelRect(w, viewSize: whole.size, imageSize: imageSize)), above: w)
        }
        if let s = selection {
            g.setStrokeColor(NSColor.white.cgColor); g.setLineWidth(1); g.stroke(s.insetBy(dx: -0.5, dy: -0.5))
            if phase == .dragging || phase == .aiming {
                label(CaptureLogic.sizeLabel(CaptureLogic.pixelRect(s, viewSize: whole.size, imageSize: imageSize)), above: s)
            }
        }
        if phase != .editing, let c = cursor { drawLoupe(at: c, in: g) }
    }

    private func label(_ text: String, above r: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        let pill = CGRect(x: r.minX, y: r.minY - sz.height - 12 < 4 ? r.minY + 6 : r.minY - sz.height - 12, width: sz.width + 14, height: sz.height + 6)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        s.draw(at: NSPoint(x: pill.minX + 7, y: pill.minY + 3))
    }

    private func drawLoupe(at c: CGPoint, in g: CGContext) {
        let size: CGFloat = 112, cells = 15
        let o = CaptureLogic.loupeOrigin(cursor: c, size: size, in: bounds0)
        let box = CGRect(origin: o, size: CGSize(width: size, height: size))
        let sx = imageSize.width / bounds.width, sy = imageSize.height / bounds.height
        let px = CGPoint(x: c.x * sx, y: c.y * sy)
        let src = CGRect(x: (px.x - CGFloat(cells) / 2).rounded(), y: (px.y - CGFloat(cells) / 2).rounded(), width: CGFloat(cells), height: CGFloat(cells))
        g.saveGState()
        let clip = NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14)
        clip.addClip()
        NSColor.black.setFill(); box.fill()
        if let piece = still.cropping(to: src.intersection(CGRect(origin: .zero, size: imageSize))) {
            let visible = src.intersection(CGRect(origin: .zero, size: imageSize))
            let k = size / CGFloat(cells)
            let dst = CGRect(x: box.minX + (visible.minX - src.minX) * k, y: box.minY + (visible.minY - src.minY) * k,
                             width: visible.width * k, height: visible.height * k)
            NSGraphicsContext.current?.imageInterpolation = .none
            NSImage(cgImage: piece, size: dst.size).draw(in: dst, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        }
        g.restoreGState()
        let cell = size / CGFloat(cells)
        let mid = CGRect(x: box.minX + cell * CGFloat(cells / 2), y: box.minY + cell * CGFloat(cells / 2), width: cell, height: cell)
        NSColor.white.setStroke(); let m = NSBezierPath(rect: mid); m.lineWidth = 1.5; m.stroke()
        NSColor.black.withAlphaComponent(0.6).setStroke(); let m2 = NSBezierPath(rect: mid.insetBy(dx: -1, dy: -1)); m2.lineWidth = 0.75; m2.stroke()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14); ring.lineWidth = 1.5; ring.stroke()
    }

    // MARK: mouse

    override func mouseMoved(with e: NSEvent) {
        guard phase != .editing else { return }
        let p = convert(e.locationInWindow, from: nil)
        cursor = p
        hoverWindow = snapOn ? CaptureLogic.windowRect(at: p, in: windows) : nil
        onActivate()
        needsDisplay = true
    }

    override func mouseDown(with e: NSEvent) {
        guard phase != .editing else { return }
        let p = convert(e.locationInWindow, from: nil)
        downPoint = p; anchor = p; dragged = false; lastPoint = p
        selection = nil
        phase = .dragging
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        guard phase == .dragging, let a = anchor else { return }
        let p = convert(e.locationInWindow, from: nil)
        cursor = p
        if let d = downPoint, hypot(p.x - d.x, p.y - d.y) > 4 { dragged = true }
        guard dragged else { return }
        if spaceHeld, let s = selection {
            let dx = p.x - lastPoint.x, dy = p.y - lastPoint.y
            let moved = CaptureLogic.moved(s, by: CGSize(width: dx, height: dy), within: bounds0)
            anchor = CGPoint(x: a.x + moved.minX - s.minX, y: a.y + moved.minY - s.minY)
            selection = moved
        } else {
            selection = CaptureLogic.dragRect(from: a, to: p, square: e.modifierFlags.contains(.shift), bounds: bounds0)
        }
        lastPoint = p
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        guard phase == .dragging else { return }
        let p = convert(e.locationInWindow, from: nil)
        if dragged, let s = selection, s.width >= 6, s.height >= 6 {
            beginEditing()
        } else if !dragged, snapOn, let w = CaptureLogic.windowRect(at: p, in: windows) {
            selection = w; beginEditing()
        } else {
            phase = .aiming; selection = nil; hoverWindow = snapOn ? CaptureLogic.windowRect(at: p, in: windows) : nil
        }
        needsDisplay = true
    }

    // MARK: keys (aiming / dragging; the editor takes over after that)

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 53: onOutcome(.cancel)                                   // esc
        case 48: snapOn.toggle(); hoverWindow = snapOn ? cursor.flatMap { CaptureLogic.windowRect(at: $0, in: windows) } : nil; needsDisplay = true
        case 49: spaceHeld = true                                      // space: move instead of resize
        case 3 where !e.modifierFlags.contains(.command):             // F: whole screen
            selection = bounds0; beginEditing()
        case 123, 124, 125, 126:
            guard let s = selection else { return }
            let step: CGFloat = e.modifierFlags.contains(.shift) ? 10 : 1
            let d = e.keyCode == 123 ? CGSize(width: -step, height: 0) : e.keyCode == 124 ? CGSize(width: step, height: 0)
                : e.keyCode == 126 ? CGSize(width: 0, height: -step) : CGSize(width: 0, height: step)
            selection = CaptureLogic.moved(s, by: d, within: bounds0)
            if let a = anchor { anchor = CGPoint(x: a.x + d.width, y: a.y + d.height) }
            needsDisplay = true
        case 36, 76 where selection != nil && phase != .editing: beginEditing()
        default: break
        }
    }

    override func keyUp(with e: NSEvent) { if e.keyCode == 49 { spaceHeld = false } }

    // MARK: editor

    /// Nudge the chosen region while nothing has been drawn yet (arrow keys in the editor).
    func nudgeSelection(_ d: CGSize) -> Bool {
        guard let s = selection, state?.hasMarks == false else { return false }
        selection = CaptureLogic.moved(s, by: d, within: bounds0)
        beginEditing(); return true
    }

    func beginEditing() {
        guard let sel = selection else { return }
        canvasHost?.removeFromSuperview(); toolbarHost?.removeFromSuperview()
        phase = .editing
        let px = CaptureLogic.pixelRect(sel, viewSize: bounds.size, imageSize: imageSize)
        guard let crop = still.cropping(to: px) else { onOutcome(.cancel); return }
        let st = AnnotationState(image: crop)
        state = st

        let canvas = NSHostingView(rootView: CaptureCanvasHost(state: st, onReturn: { [weak self] in self?.onOutcome(.save(st)) },
                                                               onEscape: { [weak self] in self?.onOutcome(.cancel) },
                                                               onArrow: { [weak self] dx, dy in self?.nudgeSelection(CGSize(width: dx, height: dy)) ?? false }))
        canvas.frame = sel
        addSubview(canvas); canvasHost = canvas

        let bar = NSHostingView(rootView: CaptureToolbarHost(state: st, onOutcome: { [weak self] in self?.onOutcome($0) }))
        let size = bar.fittingSize
        bar.frame = CGRect(origin: CaptureLogic.toolbarOrigin(selection: sel, toolbar: size, in: bounds0), size: size)
        addSubview(bar); toolbarHost = bar
        window?.makeFirstResponder(canvas)
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }
}

struct CaptureCanvasHost: View {
    let state: AnnotationState
    let onReturn: () -> Void, onEscape: () -> Void
    let onArrow: (CGFloat, CGFloat) -> Bool
    var body: some View {
        AnnotationCanvas(state: state, corner: 0)
            .annotationKeys(state, onReturn: onReturn, onEscape: onEscape, onArrow: onArrow)
    }
}

struct CaptureToolbarHost: View {
    let state: AnnotationState
    let onOutcome: (CaptureOutcome) -> Void
    var body: some View {
        AnnotationToolbar(state: state, finish: [
            FinishAction(id: "cancel", title: "Cancel", action: { onOutcome(.cancel) }),
            FinishAction(id: "copy", title: "Copy", symbol: "doc.on.doc", shortcut: "c", action: { onOutcome(.copy(state)) }),
            FinishAction(id: "send", title: "Send", symbol: "paperplane", action: { onOutcome(.send(state)) }),
            FinishAction(id: "save", title: "Save", primary: true, shortcut: "s", action: { onOutcome(.save(state)) }),
        ], floating: true)
        .fixedSize()
    }
}

// MARK: - Permission prompt

struct CapturePermissionPrompt: View {
    let openSettings: () -> Void
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.dashed.badge.record").font(.system(size: 16)).foregroundStyle(Theme.hubSecondary)
            Text("True needs Screen Recording to capture.").font(.system(size: 13)).foregroundStyle(Theme.text)
            Button(action: openSettings) {
                Text("Open Settings").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 12).frame(height: 26).background(.white, in: .capsule)
            }.buttonStyle(.plain)
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.hubSecondary).frame(width: 24, height: 24) }
                .buttonStyle(.plain).help("Close")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(white: 0.11), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
        .fixedSize()
    }
}

// MARK: - Controller

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CaptureController {
    static let shared = CaptureController()
    private var panels: [CapturePanel] = []
    private var prompt: NSPanel?
    private(set) var busy = false

    var active: Bool { !panels.isEmpty }

    func start() {
        guard !busy, !active else { return }
        guard CGPreflightScreenCaptureAccess() else { showPrompt(); return }
        busy = true
        Task {
            defer { busy = false }
            do { try await present() } catch { showPrompt() }
        }
    }

    private func present() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var made: [CapturePanel] = []
        let windowList = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let cfg = SCStreamConfiguration()
            cfg.width = Int(screen.frame.width * screen.backingScaleFactor); cfg.height = Int(screen.frame.height * screen.backingScaleFactor)
            cfg.showsCursor = false
            let img = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg)
            let origin = CGDisplayBounds(id).origin
            let frames: [CGRect] = windowList.compactMap { w in
                guard (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                      let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
                return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0).offsetBy(dx: -origin.x, dy: -origin.y)
            }
            let view = CaptureView(frame: CGRect(origin: .zero, size: screen.frame.size), still: img, windows: frames)
            view.onOutcome = { [weak self] in self?.handle($0) }
            let p = CapturePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .screenSaver; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.contentView = view
            p.setFrame(screen.frame, display: false)
            made.append(p)
        }
        guard !made.isEmpty else { throw CocoaError(.fileReadUnknown) }
        panels = made
        let underMouse = made.first { $0.frame.contains(NSEvent.mouseLocation) } ?? made[0]
        for p in made { p.orderFrontRegardless() }
        underMouse.makeKey()
        if let v = underMouse.contentView { underMouse.makeFirstResponder(v) }
    }

    func close() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }

    private func handle(_ outcome: CaptureOutcome) {
        switch outcome {
        case .cancel: close()
        case .copy(let s):
            if let out = s.export() {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(out.png, forType: .png)
                save(out)
            }
            close()
        case .save(let s):
            if let out = s.export() { save(out); TrayPanelController.shared.showToast("Saved to Screenshots") }
            close()
        case .send(let s):
            if let out = s.export() { save(out, thenSend: true) }
            close()
        }
    }

    private func save(_ out: (png: Data, width: Int, height: Int), thenSend: Bool = false) {
        Task {
            guard let e = await ScreenshotWatcher.shared.addCapture(png: out.png, width: out.width, height: out.height) else { return }
            if thenSend { ScreenshotWatcher.shared.send(e) }
        }
    }

    // MARK: permission

    private func showPrompt() {
        close()
        prompt?.orderOut(nil)
        let host = NSHostingView(rootView: CapturePermissionPrompt(openSettings: { [weak self] in
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(u) }
            self?.prompt?.orderOut(nil)
        }, dismiss: { [weak self] in self?.prompt?.orderOut(nil) }))
        let size = host.fittingSize
        let p = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.level = .floating; p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        if let s = NSScreen.main { p.setFrameOrigin(CGPoint(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height - 90)) }
        p.orderFrontRegardless()
        prompt = p
        CGRequestScreenCaptureAccess()   // registers True in the Screen Recording list the first time
    }
}

// MARK: - Global hotkey

/// ⌃⌥⌘A (see `CaptureHotKey`) from any app. Shares the Carbon event target with `ShotsHotKeyRegistrar`, so each
/// handler checks the hot-key id and passes on anything that isn't its own.
@MainActor
final class CaptureHotKeyRegistrar {
    static let shared = CaptureHotKeyRegistrar()
    static let id: UInt32 = 2
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register() {
        guard ref == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard hk.id == CaptureHotKeyRegistrar.id else { return OSStatus(eventNotHandledErr) }
            Task { @MainActor in CaptureController.shared.start() }
            return noErr
        }, 1, &spec, nil, &handler)
        RegisterEventHotKey(CaptureHotKey.carbonKeyCode, CaptureHotKey.carbonModifiers,
                            EventHotKeyID(signature: OSType(0x54524350), id: Self.id),   // 'TRCP'
                            GetApplicationEventTarget(), 0, &ref)
    }
}
