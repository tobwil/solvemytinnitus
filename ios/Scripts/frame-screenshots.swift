// Puts simulator screenshots into an iPhone frame (titanium edge, black bezel, side buttons, soft shadow).
// Usage: swift Scripts/frame-screenshots.swift <input-dir> <output-dir> [scale]
// Input: 1206×2622 PNGs from `xcrun simctl io <device> screenshot` (iPhone 17/18 Pro).
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: frame-screenshots.swift <input-dir> <output-dir> [scale]")
    exit(1)
}
let inDir = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
let scale = args.count > 3 ? CGFloat(Double(args[3]) ?? 0.5) : 0.5
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func frame(_ url: URL) throws {
    guard let src = NSImage(contentsOf: url),
          let shot = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let sw = CGFloat(shot.width), sh = CGFloat(shot.height)
    let bezel: CGFloat = 40, edge: CGFloat = 12, pad: CGFloat = 120
    let screenRadius: CGFloat = 168
    let bodyW = sw + 2 * (bezel + edge), bodyH = sh + 2 * (bezel + edge)
    let W = Int((bodyW + 2 * pad) * scale), H = Int((bodyH + 2 * pad) * scale)

    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high
    let body = CGRect(x: pad, y: pad, width: bodyW, height: bodyH)
    let bodyRadius = screenRadius + bezel + edge

    // side buttons (drawn first, partly hidden behind the body)
    let button = CGColor(srgbRed: 0.56, green: 0.57, blue: 0.59, alpha: 1)
    ctx.setFillColor(button)
    let top = body.maxY // CoreGraphics origin is bottom-left
    for (y, h) in [(430.0, 110.0), (620.0, 200.0), (860.0, 200.0)] { // action, volume up, volume down
        ctx.addPath(rounded(CGRect(x: body.minX - 9, y: top - CGFloat(y) - CGFloat(h), width: 14, height: CGFloat(h)), 6))
    }
    ctx.addPath(rounded(CGRect(x: body.maxX - 5, y: top - 760 - 300, width: 14, height: 300), 6)) // side button
    ctx.addPath(rounded(CGRect(x: body.maxX - 5, y: top - 1520 - 170, width: 10, height: 170), 5)) // camera control
    ctx.fillPath()

    // soft shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -36), blur: 90, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
    ctx.addPath(rounded(body, bodyRadius))
    ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.2, blue: 0.21, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // titanium edge: vertical gradient
    ctx.saveGState()
    ctx.addPath(rounded(body, bodyRadius))
    ctx.clip()
    let titanium = CGGradient(colorsSpace: cs, colors: [
        CGColor(srgbRed: 0.80, green: 0.81, blue: 0.83, alpha: 1),
        CGColor(srgbRed: 0.52, green: 0.53, blue: 0.56, alpha: 1),
        CGColor(srgbRed: 0.74, green: 0.75, blue: 0.77, alpha: 1),
    ] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(titanium, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    ctx.restoreGState()

    // black bezel
    let inner = body.insetBy(dx: edge, dy: edge)
    ctx.addPath(rounded(inner, bodyRadius - edge))
    ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1))
    ctx.fillPath()

    // screen
    let screen = inner.insetBy(dx: bezel, dy: bezel)
    ctx.saveGState()
    ctx.addPath(rounded(screen, screenRadius))
    ctx.clip()
    ctx.draw(shot, in: screen)
    ctx.restoreGState()

    // Dynamic Island (not part of simulator screenshots): 126 × 37 pt, 11 pt below the top edge
    let k = sw / 402
    let island = CGRect(x: screen.midX - 63 * k, y: screen.maxY - (11 + 37) * k, width: 126 * k, height: 37 * k)
    ctx.addPath(rounded(island, 18.5 * k))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()

    guard let out = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: out)
    let dest = outDir.appendingPathComponent(url.lastPathComponent)
    try rep.representation(using: .png, properties: [:])?.write(to: dest)
    print("framed \(url.lastPathComponent) → \(W)×\(H)")
}

let files = try FileManager.default.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
for f in files { try frame(f) }
