// Renders AppIcon-1024.png from the same geometry as background.svg + foreground.svg.
// Usage: swift render.swift <output.png>
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let px = 1024
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!   // opaque: App Store icons carry no alpha
ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: 1, y: -1)   // SVG coordinates: y down
ctx.setFillColor(CGColor(red: 0x1A / 255, green: 0x1A / 255, blue: 0x18 / 255, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
let amber = (r: CGFloat(0xE8) / 255, g: CGFloat(0xA2) / 255, b: CGFloat(0x3C) / 255)
ctx.setStrokeColor(CGColor(red: amber.r, green: amber.g, blue: amber.b, alpha: 1))
ctx.setLineWidth(96); ctx.setLineCap(.butt); ctx.setLineJoin(.miter)
ctx.move(to: CGPoint(x: 267, y: 332)); ctx.addLine(to: CGPoint(x: 467, y: 512)); ctx.addLine(to: CGPoint(x: 267, y: 692))
ctx.strokePath()
ctx.setFillColor(CGColor(red: amber.r, green: amber.g, blue: amber.b, alpha: 0.6))
ctx.fill(CGRect(x: 607, y: 392, width: 140, height: 240))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
