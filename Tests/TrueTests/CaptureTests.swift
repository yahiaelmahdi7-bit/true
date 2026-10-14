import Testing
import Foundation
import AppKit
@testable import True

/// A busy gradient so pixelate/blur visibly change pixels.
private func busyImage(_ w: Int, _ h: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    for y in 0..<h { for x in 0..<w {
        ctx.setFillColor(CGColor(srgbRed: CGFloat((x * 7) % 256) / 255, green: CGFloat((y * 13) % 256) / 255,
                                 blue: CGFloat((x ^ y) % 2 == 0 ? 1 : 0), alpha: 1))
        ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
    } }
    return ctx.makeImage()!
}

private func pixels(_ img: CGImage) -> [UInt8] {
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}

private func px(_ b: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> [UInt8] { Array(b[(y * w + x) * 4 ..< (y * w + x) * 4 + 4]) }

@Suite struct MarkupModelTests {
    @Test func codableRoundTrip() throws {
        var d = MarkupDoc()
        d.add(Stroke(mark: .arrow(from: .init(x: 1, y: 2), to: .init(x: 30, y: 40)), color: .red, width: 4))
        d.add(Stroke(mark: .text("hi", at: .init(x: 5, y: 6)), color: .blue, width: 18, custom: RGBA(r: 0.1, g: 0.2, b: 0.3)))
        d.add(Stroke(mark: .censor(CGRect(x: 1, y: 1, width: 9, height: 9)), color: .ink, width: 3, censor: .blur))
        d.setCrop(CGRect(x: 0, y: 0, width: 50, height: 40))
        let back = try JSONDecoder().decode(MarkupDoc.self, from: JSONEncoder().encode(d))
        #expect(back.strokes == d.strokes)
        #expect(back.crop == d.crop)
    }

    @Test func stepNumbering() {
        var d = MarkupDoc()
        func step(_ x: CGFloat) { d.add(Stroke(mark: .step(at: .init(x: x, y: 5)), color: .red, width: 4)) }
        #expect(d.nextStepNumber == 1)
        step(1)
        d.add(Stroke(mark: .rect(CGRect(x: 0, y: 0, width: 5, height: 5)), color: .red, width: 4))
        step(20); step(40)
        #expect(d.stepNumber(at: 0) == 1)
        #expect(d.stepNumber(at: 2) == 2)
        #expect(d.stepNumber(at: 3) == 3)
        #expect(d.stepNumber(at: 1) == nil)
        #expect(d.nextStepNumber == 4)
        d.remove(at: 0)
        #expect(d.stepNumber(at: 1) == 1)   // renumbers after delete
    }

    @Test func undoRedoIncludingCrop() {
        var d = MarkupDoc()
        d.add(Stroke(mark: .line(from: .zero, to: .init(x: 5, y: 5)), color: .red, width: 3))
        d.setCrop(CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(d.crop != nil)
        d.undo(); #expect(d.crop == nil); #expect(d.strokes.count == 1)
        d.undo(); #expect(d.strokes.isEmpty)
        d.redo(); d.redo()
        #expect(d.strokes.count == 1 && d.crop != nil)
        d.undo()
        d.add(Stroke(mark: .rect(CGRect(x: 0, y: 0, width: 4, height: 4)), color: .blue, width: 3))
        #expect(!d.canRedo)   // new change drops redo
    }

    @Test func cropClamp() {
        let size = CGSize(width: 100, height: 60)
        #expect(CropMath.clamp(CGRect(x: -10, y: -10, width: 500, height: 500), to: size) == CGRect(x: 0, y: 0, width: 100, height: 60))
        let tiny = CropMath.clamp(CGRect(x: 50, y: 50, width: 1, height: 1), to: size)
        #expect(tiny.width >= CropMath.minSide && tiny.height >= CropMath.minSide)
        #expect(CGRect(origin: .zero, size: size).contains(tiny))
        // dragged backwards
        let back = CropMath.clamp(CGRect(x: 40, y: 30, width: -20, height: -10), to: size)
        #expect(back.minX == 20 && back.minY == 20 && back.width == 20 && back.height == 10)
    }
}

@Suite struct MarkupRenderTests {
    @Test func nativePixelSizeAndAlignment() {
        let base = busyImage(120, 80)
        var d = MarkupDoc()
        d.add(Stroke(mark: .rect(CGRect(x: 10, y: 20, width: 40, height: 30)), color: .red, width: 4, filled: true))
        let out = MarkupRender.render(base: base, doc: d)!
        #expect(out.width == 120 && out.height == 80)
        let p = pixels(out), b = pixels(base)
        // inside the filled rect (top-left origin): solid red; outside: untouched.
        let inside = px(p, 120, 30, 35)
        #expect(inside[1] > 200 || inside[2] > 200 || inside[3] > 200)   // some channel saturated; not the busy base
        #expect(inside != px(b, 120, 30, 35))
        #expect(px(p, 120, 100, 70) == px(b, 120, 100, 70))
        #expect(px(p, 120, 5, 5) == px(b, 120, 5, 5))
    }

    @Test func retinaScaleDoublesSize() {
        let out = MarkupRender.render(base: busyImage(50, 40), doc: MarkupDoc(), scale: 2)!
        #expect(out.width == 100 && out.height == 80)
    }

    @Test(arguments: CensorMode.allCases) func censorOnlyChangesInsideRect(mode: CensorMode) {
        let base = busyImage(100, 80)
        let r = CGRect(x: 30, y: 20, width: 40, height: 30)
        var d = MarkupDoc()
        d.add(Stroke(mark: .censor(r), color: .ink, width: 4, censor: mode))
        let p = pixels(MarkupRender.render(base: base, doc: d)!), b = pixels(base)
        var inChanged = 0
        for y in 0..<80 { for x in 0..<100 {
            let same = px(p, 100, x, y) == px(b, 100, x, y)
            if r.contains(CGPoint(x: x, y: y)) { if !same { inChanged += 1 } }
            else { #expect(same, "pixel \(x),\(y) changed outside the censor rect") }
        } }
        #expect(inChanged > 100)
    }

    @Test func cropOutputSize() {
        var d = MarkupDoc()
        d.setCrop(CGRect(x: 10, y: 10, width: 60, height: 40))
        #expect(MarkupRender.render(base: busyImage(100, 80), doc: d)!.width == 60)
        #expect(MarkupRender.render(base: busyImage(100, 80), doc: d)!.height == 40)
        #expect(MarkupRender.render(base: busyImage(100, 80), doc: d, applyCrop: false)!.width == 100)
    }
}

@Suite struct CaptureLogicTests {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test func squareDrag() {
        let r = CaptureLogic.dragRect(from: .init(x: 100, y: 100), to: .init(x: 160, y: 130), square: true, bounds: bounds)
        #expect(r.width == 60 && r.height == 60)
        let free = CaptureLogic.dragRect(from: .init(x: 100, y: 100), to: .init(x: 60, y: 130), square: false, bounds: bounds)
        #expect(free == CGRect(x: 60, y: 100, width: 40, height: 30))
    }

    @Test func dragClampsToScreen() {
        let r = CaptureLogic.dragRect(from: .init(x: 350, y: 250), to: .init(x: 500, y: 400), square: false, bounds: bounds)
        #expect(r.maxX == 400 && r.maxY == 300)
    }

    @Test func nudgeAndMoveStayOnScreen() {
        let r = CGRect(x: 10, y: 10, width: 50, height: 50)
        #expect(CaptureLogic.moved(r, by: CGSize(width: 1, height: 0), within: bounds).minX == 11)
        let far = CaptureLogic.moved(r, by: CGSize(width: 9999, height: -9999), within: bounds)
        #expect(far.maxX == 400 && far.minY == 0 && far.size == r.size)
    }

    @Test func windowSnapFrontmostWins() {
        let front = CGRect(x: 50, y: 50, width: 100, height: 100), back = CGRect(x: 0, y: 0, width: 300, height: 300)
        #expect(CaptureLogic.windowRect(at: .init(x: 60, y: 60), in: [front, back]) == front)
        #expect(CaptureLogic.windowRect(at: .init(x: 250, y: 250), in: [front, back]) == back)
        #expect(CaptureLogic.windowRect(at: .init(x: 60, y: 60), in: [CGRect(x: 0, y: 0, width: 20, height: 20)]) == nil)
    }

    @Test func pixelRectScalesRetina() {
        let px = CaptureLogic.pixelRect(CGRect(x: 10, y: 10, width: 100, height: 50), viewSize: CGSize(width: 400, height: 300), imageSize: CGSize(width: 800, height: 600))
        #expect(px == CGRect(x: 20, y: 20, width: 200, height: 100))
        #expect(CaptureLogic.sizeLabel(px) == "200 × 100")
    }

    @Test func loupeAndToolbarFlipAtEdges() {
        let l = CaptureLogic.loupeOrigin(cursor: .init(x: 390, y: 290), size: 100, in: bounds)
        #expect(l.x + 100 <= 400 && l.y + 100 <= 300)
        let t = CaptureLogic.toolbarOrigin(selection: CGRect(x: 100, y: 250, width: 100, height: 45), toolbar: CGSize(width: 200, height: 40), in: bounds)
        #expect(t.y + 40 <= 300)
    }
}

@Suite struct CaptureTrayTests {
    func makeStore() throws -> (TrayStore, URL) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("capturetest-\(UUID().uuidString)", isDirectory: true)
        let trash = tmp.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return (TrayStore(root: tmp.appendingPathComponent("tray", isDirectory: true), trash: { _ in nil }), tmp)
    }

    @Test func captureAndMarkupLandInIndex() throws {
        let (store, tmp) = try makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let png = MarkupRender.png(base: busyImage(60, 40), doc: MarkupDoc())!
        let cap = try #require(store.addCapture(png: png, width: 60, height: 40))
        #expect(cap.kind == .original && cap.parent == nil && cap.source == nil)
        let mk = try #require(store.addMarkup(png: png, parent: cap.id, width: 60, height: 40))
        #expect(mk.kind == .markup && mk.parent == cap.id)

        let raw = try Data(contentsOf: store.indexURL)
        let json = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let shots = try #require(json["shots"] as? [[String: Any]])
        #expect(shots.count == 2)
        let m = try #require(shots.first { $0["id"] as? String == mk.id })
        #expect(m["kind"] as? String == "markup")
        #expect(m["parent"] as? String == cap.id)
        #expect(FileManager.default.fileExists(atPath: store.root.appendingPathComponent(mk.file).path))
    }
}

// MARK: - Polish round

@Suite struct SystemShortcutTests {
    @Test func missingEntryMeansMacOSStillOwnsIt() {
        #expect(SystemShortcut.isEnabled(30, in: nil))
        #expect(SystemShortcut.isEnabled(30, in: ["31": ["enabled": false]]))
    }
    @Test func disabledEntryFreesTheShortcut() {
        #expect(!SystemShortcut.isEnabled(30, in: ["30": ["enabled": false, "value": ["type": "standard"]]]))
        #expect(!SystemShortcut.isEnabled(30, in: ["30": ["enabled": NSNumber(value: 0)]]))
    }
    @Test func enabledEntryKeepsMacOSInCharge() {
        #expect(SystemShortcut.isEnabled(30, in: ["30": ["enabled": true]]))
        #expect(SystemShortcut.isEnabled(30, in: ["30": ["enabled": NSNumber(value: 1)]]))
        #expect(SystemShortcut.isEnabled(30, in: ["30": ["value": "x"]]))   // no flag → default on
    }
    @Test func hotkeysAreDistinct() {
        #expect(CaptureHotKey.primary.id != CaptureHotKey.backup.id)
        #expect(CaptureHotKey.all.count == 2)
    }
}

@Suite struct RectHandleTests {
    let r = CGRect(x: 100, y: 100, width: 200, height: 100)
    let bounds = CGRect(x: 0, y: 0, width: 500, height: 400)

    @Test func eightHandlesAtCornersAndMidpoints() {
        #expect(RectHandle.allCases.count == 8)
        #expect(RectHandle.topLeft.point(in: r) == CGPoint(x: 100, y: 100))
        #expect(RectHandle.right.point(in: r) == CGPoint(x: 300, y: 150))
        #expect(RectHandle.bottom.point(in: r) == CGPoint(x: 200, y: 200))
    }
    @Test func hitReachIsGenerous() {
        #expect(RectHandle.hit(CGPoint(x: 108, y: 100), in: r) == .topLeft)   // 8 pt away still grabs
        #expect(RectHandle.hit(CGPoint(x: 200, y: 160), in: r) == nil)
    }
    @Test func cornersAndEdgesResize() {
        #expect(RectHandle.bottomRight.resized(r, to: CGPoint(x: 350, y: 260), bounds: bounds) == CGRect(x: 100, y: 100, width: 250, height: 160))
        #expect(RectHandle.topLeft.resized(r, to: CGPoint(x: 60, y: 80), bounds: bounds) == CGRect(x: 60, y: 80, width: 240, height: 120))
        #expect(RectHandle.right.resized(r, to: CGPoint(x: 400, y: 999), bounds: bounds) == CGRect(x: 100, y: 100, width: 300, height: 100))
        #expect(RectHandle.top.resized(r, to: CGPoint(x: 0, y: 40), bounds: bounds) == CGRect(x: 100, y: 40, width: 200, height: 160))
        #expect(RectHandle.left.resized(r, to: CGPoint(x: 20, y: 0), bounds: bounds) == CGRect(x: 20, y: 100, width: 280, height: 100))
        #expect(RectHandle.bottom.resized(r, to: CGPoint(x: 0, y: 300), bounds: bounds) == CGRect(x: 100, y: 100, width: 200, height: 200))
    }
    @Test func clampsToBounds() {
        let out = RectHandle.bottomRight.resized(r, to: CGPoint(x: 9000, y: -50), bounds: bounds)
        #expect(bounds.contains(out) && out.maxX == 500)
        let tl = RectHandle.topLeft.resized(r, to: CGPoint(x: -80, y: -80), bounds: bounds)
        #expect(tl.minX == 0 && tl.minY == 0)
    }
    @Test func shiftKeepsSquare() {
        let out = RectHandle.bottomRight.resized(r, to: CGPoint(x: 400, y: 160), square: true, bounds: bounds)
        #expect(out.width == out.height && out.minX == 100 && out.minY == 100 && out.width == 300)
        let tl = RectHandle.topLeft.resized(r, to: CGPoint(x: 40, y: 90), square: true, bounds: bounds)
        #expect(tl.width == tl.height && tl.maxX == 300 && tl.maxY == 200)
    }
    @Test func squareStaysInsideBounds() {
        let out = RectHandle.bottomRight.resized(r, to: CGPoint(x: 5000, y: 5000), square: true, bounds: bounds)
        #expect(bounds.contains(out) && out.width == out.height)
    }
    @Test func draggingPastTheOppositeEdgeFlips() {
        let out = RectHandle.right.resized(r, to: CGPoint(x: 40, y: 150), bounds: bounds)
        #expect(out.minX == 40 && out.maxX == 100)
    }
    @Test func neverCollapsesBelowMinimum() {
        let out = RectHandle.right.resized(r, to: CGPoint(x: 100, y: 150), bounds: bounds)
        #expect(out.width >= 8)
    }
}

@Suite struct HighlighterBlendTests {
    private func rendered(_ base: CGColor, mark color: MarkupColor = .amber) -> [UInt8] {
        let ctx = CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        ctx.setFillColor(base); ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        var d = MarkupDoc()
        d.add(Stroke(mark: .highlight([CGPoint(x: 5, y: 20), CGPoint(x: 75, y: 20)]), color: color, width: 4))
        let out = MarkupRender.render(base: ctx.makeImage()!, doc: d)!
        return px(pixels(out), 80, 40, 20)   // A, R, G, B
    }

    @Test func yellowOverDarkStaysYellow() {
        let p = rendered(CGColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 1))
        #expect(p[1] > 80 && p[2] > 70)                  // R and G lifted
        #expect(Int(p[1]) > Int(p[3]) * 2 && Int(p[2]) > Int(p[3]) * 2)   // clearly yellow: R,G ≫ B
    }
    @Test func yellowOverLightStaysYellow() {
        let p = rendered(CGColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1))
        #expect(p[1] > 200 && p[2] > 200 && p[3] < p[1] - 30)
    }
}
