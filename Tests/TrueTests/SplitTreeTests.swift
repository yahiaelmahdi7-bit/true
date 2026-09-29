import Testing
import Foundation
import CoreGraphics
@testable import True

@Suite struct SplitTreeTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    /// a | (b over c)
    func sample() -> SplitTree {
        SplitTree.leaf(a)
            .inserting(b, beside: a, axis: .horizontal)
            .inserting(c, beside: b, axis: .vertical)
    }

    @Test func insertAndReadingOrder() {
        #expect(sample().leafIDs == [a, b, c])
        #expect(SplitTree.leaf(a).inserting(b, beside: d, axis: .horizontal) == .leaf(a)) // unknown target: no-op
    }

    @Test func removeGivesSpaceToSibling() {
        let t = sample()
        #expect(t.removing(c)?.leafIDs == [a, b])
        #expect(t.removing(a)?.leafIDs == [b, c])
        #expect(SplitTree.leaf(a).removing(a) == nil)
        #expect(t.removing(d) == t)
    }

    @Test func focusMovesByGeometry() {
        let t = sample()
        #expect(t.neighbor(of: a, .right) == b)
        #expect(t.neighbor(of: b, .down) == c)
        #expect(t.neighbor(of: c, .up) == b)
        #expect(t.neighbor(of: c, .left) == a)
        #expect(t.neighbor(of: a, .left) == nil)
        #expect(t.neighbor(of: c, .down) == nil)
    }

    @Test func fractionClamps() {
        #expect(SplitTree.clampFraction(-3) == 0.05)
        #expect(SplitTree.clampFraction(9) == 0.95)
        #expect(SplitTree.clampFraction(.nan) == 0.5)
        let t = sample()   // built once: every call to sample() mints fresh split ids
        guard case .split(let id, _, _, _, _) = t else { Issue.record("expected split"); return }
        guard case .split(_, _, let f, _, _) = t.settingFraction(2, forSplit: id) else { return }
        #expect(f == 0.95)
    }

    @Test(arguments: [
        CGSize(width: 1280, height: 820), CGSize(width: 480, height: 300), CGSize(width: 137, height: 91),
        CGSize(width: 50, height: 20), CGSize(width: 3, height: 3), CGSize(width: 0, height: 0),
    ])
    func layoutInvariants(size: CGSize) {
        let t = sample().inserting(d, beside: a, axis: .vertical)
        let l = t.layout(in: size)
        let container = CGRect(origin: .zero, size: size)
        #expect(l.panes.count == 4)
        var area: CGFloat = 0
        let frames = Array(l.panes.values)
        for (i, r) in frames.enumerated() {
            #expect(r.width >= 0 && r.height >= 0)
            #expect(container.insetBy(dx: -0.001, dy: -0.001).contains(r))
            area += r.width * r.height
            for o in frames[(i + 1)...] { #expect(r.intersection(o).width * r.intersection(o).height < 0.001) }
        }
        for dv in l.dividers { area += dv.frame.width * dv.frame.height }
        // Tiling is exact once every split has room for its divider.
        if size.width >= 4 && size.height >= 4 {
            #expect(abs(area - size.width * size.height) < 0.01)
        }
    }
}
