import Testing
import CoreGraphics
@testable import True

@Suite struct MarkupTests {
    func stroke(_ x: CGFloat) -> Stroke {
        Stroke(mark: .rect(CGRect(x: x, y: 0, width: 10, height: 10)), color: .red, width: 4)
    }

    @Test func addUndoRedo() {
        var d = MarkupDoc()
        #expect(d.isEmpty && !d.canUndo && !d.canRedo)
        d.add(stroke(1)); d.add(stroke(2))
        #expect(d.strokes.count == 2 && d.canUndo && !d.canRedo)
        d.undo()
        #expect(d.strokes == [stroke(1)] && d.canRedo)
        d.redo()
        #expect(d.strokes == [stroke(1), stroke(2)] && !d.canRedo)
    }

    @Test func undoAndRedoOnEmptyAreNoOps() {
        var d = MarkupDoc()
        d.undo(); d.redo()
        #expect(d.isEmpty && !d.canRedo)
    }

    @Test func newMarkAfterUndoDropsRedoStack() {
        var d = MarkupDoc()
        d.add(stroke(1)); d.add(stroke(2))
        d.undo()
        d.add(stroke(3))
        #expect(!d.canRedo)
        #expect(d.strokes == [stroke(1), stroke(3)])
        d.redo()   // nothing to redo: unchanged
        #expect(d.strokes == [stroke(1), stroke(3)])
    }

    @Test func clearEmptiesBothStacks() {
        var d = MarkupDoc()
        d.add(stroke(1)); d.add(stroke(2)); d.undo()
        d.clear()
        #expect(d.isEmpty && !d.canUndo && !d.canRedo)
    }

    @Test func coordinatesStayInPixelSpace() {
        // A 1000x500-pixel image shown at 250x125 points: a tap at (125, 62.5) is pixel (500, 250).
        let p = MarkupDoc.imagePoint(CGPoint(x: 125, y: 62.5), viewSize: CGSize(width: 250, height: 125),
                                     imageSize: CGSize(width: 1000, height: 500))
        #expect(p == CGPoint(x: 500, y: 250))
        // The same view point at a different zoom still maps to the same pixel.
        let q = MarkupDoc.imagePoint(CGPoint(x: 250, y: 125), viewSize: CGSize(width: 500, height: 250),
                                     imageSize: CGSize(width: 1000, height: 500))
        #expect(q == p)
        #expect(MarkupDoc.imagePoint(.zero, viewSize: .zero, imageSize: CGSize(width: 10, height: 10)) == .zero)
        var d = MarkupDoc()
        d.add(Stroke(mark: .arrow(from: p, to: q), color: .blue, width: 4))
        #expect(d.strokes[0].mark == .arrow(from: CGPoint(x: 500, y: 250), to: CGPoint(x: 500, y: 250)))
    }

    @Test func defaultWidthScalesWithImage() {
        #expect(MarkupDoc.defaultWidth(forImage: CGSize(width: 100, height: 100)) == 3)
        #expect(MarkupDoc.defaultWidth(forImage: CGSize(width: 3000, height: 2000)) == 12)
    }
}

@Suite struct TrayPanelFrameTests {
    typealias F = TrayPanelFrame

    @Test func topRightOnPrimaryScreens() {
        // visibleFrame excludes the menu bar: 1440x900 screen, 25 pt menu bar → visible y 0…875.
        let a = F.topRight(visible: CGRect(x: 0, y: 0, width: 1440, height: 875), size: CGSize(width: 200, height: 60), inset: 12)
        #expect(a == CGRect(x: 1228, y: 803, width: 200, height: 60))
        let b = F.topRight(visible: CGRect(x: 0, y: 80, width: 2560, height: 1335), size: CGSize(width: 432, height: 400), inset: 12)
        #expect(b == CGRect(x: 2116, y: 1003, width: 432, height: 400))
        #expect(b.maxX == 2560 - 12 && b.maxY == 1415 - 12)
    }

    @Test func offsetSecondaryScreen() {
        // A display to the right and above the primary: origin is not (0,0).
        let v = CGRect(x: 1440, y: 300, width: 1920, height: 1055)
        let r = F.topRight(visible: v, size: CGSize(width: 300, height: 100), inset: 12)
        #expect(r == CGRect(x: 3360 - 12 - 300, y: 1355 - 12 - 100, width: 300, height: 100))
        #expect(v.contains(r))
        let left = F.topRight(visible: CGRect(x: -1920, y: 0, width: 1920, height: 1080), size: CGSize(width: 300, height: 100), inset: 12)
        #expect(left.maxX == -12)
    }

    @Test func oversizeIsClampedInsideTheScreen() {
        let v = CGRect(x: 0, y: 0, width: 800, height: 600)
        let r = F.topRight(visible: v, size: CGSize(width: 5000, height: 5000), inset: 12)
        #expect(r == CGRect(x: 12, y: 12, width: 776, height: 576))
    }

    @Test func zoomIsAbout55PercentWidthAndFitsHeight() {
        let v = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let s = F.zoomSize(visible: v, imageSize: CGSize(width: 2000, height: 1000), chrome: 44, inset: 12)
        #expect(s.width == 880 && s.height == 484)   // 880 * 0.5 + 44
        // A tall image would overflow: width shrinks so height == visible - 2*inset.
        let t = F.zoomSize(visible: v, imageSize: CGSize(width: 500, height: 2000), chrome: 44, inset: 12)
        #expect(t.height <= 976)
        #expect(t.width < 880)
    }
}
