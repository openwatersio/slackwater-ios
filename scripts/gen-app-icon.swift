#!/usr/bin/env swift
// Slackwater — GPL v3. The app icon, drawn from the same tokens the app draws
// with (Palette.swift), so retargeting a colour there and re-running this
// keeps the icon in step instead of leaving a hand-exported PNG behind.
//
// Emits the three appearance variants Xcode's appiconset takes. The artwork
// is one transparent layer for all three: the dot halos are punched
// (destinationOut) rather than painted, so on the default variant the
// gradient shows through the ring and on dark/tinted the system's own
// backdrop does. That is the whole reason the layer is built once.
//
//   swift scripts/gen-app-icon.swift <appiconset-dir> [--glyph]
//
// Checking the result: `xcrun simctl ui <udid> appearance dark` does NOT
// exercise the dark variant. It flips the system UI only; home-screen icon
// appearance is a separate SpringBoard setting that stays on Light, and no
// simctl subcommand reaches it. The tell is that stock icons (Reminders,
// Files) stay white in the "dark" screenshot. Verify dark and tinted by hand
// — long-press the home screen, Edit, Customize, Dark.
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let S: CGFloat = 1024

// MARK: - Palette (mirrors Slackwater/Palette.swift)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let canvas: UInt32 = 0x05122A, canvasGlow: UInt32 = 0x0A2140
let graphLine: UInt32 = 0x38BDF8, graphHigh: UInt32 = 0x2DD4BF, graphLow: UInt32 = 0xFBBF24, foam: UInt32 = 0xE4F0E4
let fillOpacity: CGFloat = 0.5

// MARK: - Geometry

/// Turning points as fractions of the square, two of them deliberately off
/// canvas: the curve has to leave both edges mid-swing or the icon reads as a
/// bump rather than a tide that keeps going. A real tide is not one sinusoid,
/// so each leg gets its own half-cosine — the small dip on the left against
/// the big rise on the right is the neap-into-spring shape.
let turns: [(x: CGFloat, y: CGFloat)] = [
    (-0.05, 0.575), (0.30, 0.720), (0.70, 0.300), (1.30, 0.700),
]
let datumY = 0.720 * S
let lowPt = CGPoint(x: 0.30 * S, y: 0.720 * S)
let highPt = CGPoint(x: 0.70 * S, y: 0.300 * S)

func curveY(_ xf: CGFloat) -> CGFloat {
    for i in 0..<(turns.count - 1) {
        let a = turns[i], b = turns[i + 1]
        guard xf >= a.x, xf <= b.x else { continue }
        let t = (xf - a.x) / (b.x - a.x)
        return (a.y + (b.y - a.y) * (1 - cos(.pi * t)) / 2) * S
    }
    return turns[turns.count - 1].y * S
}

func curvePath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: curveY(0)))
    for px in stride(from: CGFloat(1), through: S, by: 1) {
        p.addLine(to: CGPoint(x: px, y: curveY(px / S)))
    }
    return p
}

// MARK: - Weights
// Sized for a full-bleed 1024 square, not scaled up from the strip: the icon
// is read at 60pt, where the app's 2.5pt line would vanish.
let lineWidth: CGFloat = 21
let dotRadius: CGFloat = 30
let haloGap: CGFloat = 11
let datumWidth: CGFloat = 5

/// The strip's ⤒ turn glyph is off by default: it is legible at 1024 and a
/// smudge under the dot by 120, which is where the icon is actually read.
/// `--glyph` draws it for comparison.
let drawGlyph = CommandLine.arguments.contains("--glyph")

/// How far the water is knocked back on the dark variant. There is no canvas
/// behind it there — the system's own backdrop shows through the alpha — so
/// the light artwork's line and fill glare against it at full strength. Only
/// the water is dimmed: the two turn dots are the reading, and they stay lit.
let darkWaterDim: CGFloat = 0.6

// MARK: - Drawing

/// `opaque` drops the alpha channel: the App Store rejects a primary icon
/// that has one, and only the dark and tinted variants are allowed to.
func context(opaque: Bool = false) -> CGContext {
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: alpha.rawValue)!
    // Flip to y-down so the fractions above read the way they do on screen.
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    return ctx
}

/// Erase a ring around a dot so it separates from the fill it sits on,
/// whatever ends up behind the layer.
func punchHalo(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat) {
    ctx.saveGState()
    ctx.setBlendMode(.destinationOut)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: p.x - r - haloGap, y: p.y - r - haloGap,
                               width: (r + haloGap) * 2, height: (r + haloGap) * 2))
    ctx.restoreGState()
}

func dot(_ ctx: CGContext, _ p: CGPoint, _ hex: UInt32) {
    punchHalo(ctx, p, dotRadius)
    ctx.setFillColor(rgb(hex))
    ctx.fillEllipse(in: CGRect(x: p.x - dotRadius, y: p.y - dotRadius,
                               width: dotRadius * 2, height: dotRadius * 2))
}

/// The ⤒ turn glyph — arrow to bar, "arrives and stops" — hanging under the
/// high the way the strip hangs it, glyph nearest the dot.
func toBarGlyph(_ ctx: CGContext, under p: CGPoint) {
    let w: CGFloat = 15, barHalf: CGFloat = 42
    let barY = p.y + 58, tipY = barY + 22, tailY = tipY + 88
    let head: CGFloat = 28
    ctx.setStrokeColor(rgb(graphHigh))
    ctx.setLineWidth(w)
    ctx.strokeLineSegments(between: [
        CGPoint(x: p.x - barHalf, y: barY), CGPoint(x: p.x + barHalf, y: barY),
        CGPoint(x: p.x, y: tailY), CGPoint(x: p.x, y: tipY),
        CGPoint(x: p.x - head, y: tipY + head), CGPoint(x: p.x, y: tipY),
        CGPoint(x: p.x + head, y: tipY + head), CGPoint(x: p.x, y: tipY),
    ])
}

/// The artwork on transparency: fill, datum rule, curve, turn dots, glyph.
/// `waterDim` scales the line and fill alpha and nothing else.
func artLayer(waterDim: CGFloat = 1) -> CGImage {
    let ctx = context()
    let line = curvePath()

    // Fill: blue at half strength across the crest, clear at chart datum —
    // the water, and the datum is where it stops being water.
    let area = CGMutablePath()
    area.addPath(line)
    area.addLine(to: CGPoint(x: S, y: datumY))
    area.addLine(to: CGPoint(x: 0, y: datumY))
    area.closeSubpath()
    ctx.saveGState()
    ctx.addPath(area)
    ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [rgb(graphLine, fillOpacity * waterDim), rgb(graphLine, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: highPt.y), end: CGPoint(x: 0, y: datumY),
                           options: [.drawsBeforeStartLocation])
    ctx.restoreGState()

    // Chart datum, the reference every height in the app is quoted against.
    ctx.saveGState()
    ctx.setStrokeColor(rgb(foam, 0.35))
    ctx.setLineWidth(datumWidth)
    ctx.setLineDash(phase: 0, lengths: [datumWidth, datumWidth * 3])
    ctx.strokeLineSegments(between: [CGPoint(x: 0, y: datumY), CGPoint(x: S, y: datumY)])
    ctx.restoreGState()

    ctx.setStrokeColor(rgb(graphLine, waterDim))
    ctx.setLineWidth(lineWidth)
    ctx.addPath(line)
    ctx.strokePath()

    if drawGlyph { toBarGlyph(ctx, under: highPt) }
    dot(ctx, highPt, graphHigh)
    dot(ctx, lowPt, graphLow)
    return ctx.makeImage()!
}

/// The default variant: the app's own canvas glow behind the artwork.
func defaultIcon(_ art: CGImage) -> CGImage {
    let ctx = context(opaque: true)
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [rgb(canvasGlow), rgb(canvas)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(grad, startCenter: CGPoint(x: S / 2, y: 0), startRadius: 0,
                           endCenter: CGPoint(x: S / 2, y: 0), endRadius: S,
                           options: [.drawsAfterEndLocation])
    // The seabed side of datum, a shade flatter than the lit water above it.
    ctx.setFillColor(rgb(canvas, 0.45))
    ctx.fill(CGRect(x: 0, y: datumY, width: S, height: S - datumY))
    // `context()` is flipped to y-down for the geometry above; CGImage draws
    // assume y-up, so undo the flip for this one call or the art lands mirrored.
    ctx.saveGState()
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(art, in: CGRect(x: 0, y: 0, width: S, height: S))
    ctx.restoreGState()
    return ctx.makeImage()!
}

/// The tinted variant: greyscale on transparency. iOS maps luminance onto the
/// user's tint, so the only job here is to keep the light/dark ordering the
/// colour version has.
func tintedIcon(_ art: CGImage) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.linearGray)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(art, in: CGRect(x: 0, y: 0, width: S, height: S))
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "failed to write \(url.path)")
}

// MARK: - Self-check
// The curve is the one piece of real logic here: piecewise half-cosines that
// have to pass through every turning point and stay inside the square.
func selfCheck() {
    for t in turns where t.x >= 0 && t.x <= 1 {
        precondition(abs(curveY(t.x) - t.y * S) < 0.5, "curve misses its turn at x=\(t.x)")
    }
    let ys = stride(from: CGFloat(0), through: S, by: 1).map { curveY($0 / S) }
    precondition(ys.min()! >= 0 && ys.max()! <= S, "curve leaves the square")
    precondition(ys.max()! <= datumY + 0.5, "curve dips under datum — the fill would invert")
    precondition(abs(ys.min()! - highPt.y) < 0.5, "the high is not the curve's crest")
}

selfCheck()
let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") }
                 ?? "Slackwater/Assets.xcassets/AppIcon.appiconset")
let art = artLayer()
write(defaultIcon(art), outDir.appendingPathComponent("icon-1024.png"))
write(artLayer(waterDim: darkWaterDim), outDir.appendingPathComponent("icon-1024-dark.png"))
// Tinted greyscales the undimmed artwork: iOS maps luminance onto the user's
// tint, so knocking the water back here would only flatten it against the dots.
write(tintedIcon(art), outDir.appendingPathComponent("icon-1024-tinted.png"))
print("wrote 3 variants to \(outDir.path)")
