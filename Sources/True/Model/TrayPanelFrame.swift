import CoreGraphics

/// Pure geometry for the floating screenshot panel. AppKit coordinates: origin bottom-left, so "top" is maxY.
enum TrayPanelFrame {
    /// Pinned to the top-right corner of `visible` (menu bar and Dock already excluded), `inset` from both
    /// edges. A size larger than the room is clamped so the panel never leaves the screen.
    static func topRight(visible: CGRect, size: CGSize, inset: CGFloat) -> CGRect {
        let w = min(size.width, max(0, visible.width - 2 * inset))
        let h = min(size.height, max(0, visible.height - 2 * inset))
        return CGRect(x: visible.maxX - inset - w, y: visible.maxY - inset - h, width: w, height: h)
    }

    /// Zoom: ~55% of the screen width, height from the image's aspect plus `chrome` (toolbar), shrunk
    /// proportionally if it would not fit the visible height.
    static func zoomSize(visible: CGRect, imageSize: CGSize, chrome: CGFloat, inset: CGFloat) -> CGSize {
        let aspect = imageSize.width > 0 && imageSize.height > 0 ? imageSize.height / imageSize.width : 0.625
        var w = (visible.width * 0.55).rounded()
        let maxH = max(0, visible.height - 2 * inset)
        if w * aspect + chrome > maxH { w = max(0, (maxH - chrome) / aspect).rounded() }
        return CGSize(width: w, height: (w * aspect + chrome).rounded())
    }
}
