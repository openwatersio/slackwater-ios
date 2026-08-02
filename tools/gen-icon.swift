// Slackwater — GPL v3. App-icon generator: three candidates in the app's
// design language (navy field, signed current curve, slack dot at the zero
// crossing — the moment the app is named for). Run: swift tools/gen-icon.swift <outdir>
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// Palette (Theme.swift / prototype _ds_bundle.css)
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let navy = rgb(0x05122A), navyGlow = rgb(0x0A2140), navyDeep = rgb(0x00183C)
let leaf = rgb(0x88B868), sky = rgb(0xC0D8E4), steel = rgb(0x5888A8)

func makeContext() -> CGContext {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    return ctx
}

func save(_ ctx: CGContext, _ name: String) {
    let img = ctx.makeImage()!
    let url = URL(fileURLWithPath: "\(out)/\(name)") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(name)")
}

/// Radial navy field, glow toward the top — the list canvas.
func field(_ ctx: CGContext) {
    ctx.setFillColor(navy)
    ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    let grad = CGGradient(colorsSpace: nil, colors: [navyGlow, navy] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(grad, startCenter: CGPoint(x: S / 2, y: S * 0.9), startRadius: 0,
                           endCenter: CGPoint(x: S / 2, y: S * 0.9), endRadius: S * 0.95, options: [])
}

/// The signed current curve: one full period across the frame — flood peak at
/// the left quarter, ebb trough at the right quarter, the zero crossing dead
/// centre (where the slack dot lives). CG y-axis is bottom-up.
func curvePoints(zero: CGFloat, amp: CGFloat, x0: CGFloat, x1: CGFloat) -> [CGPoint] {
    stride(from: 0.0, through: 1.0, by: 0.005).map { t in
        let x = x0 + (x1 - x0) * t
        let y = zero - amp * sin(2 * .pi * (t - 0.5))
        return CGPoint(x: x, y: y)
    }
}

func strokeCurve(_ ctx: CGContext, _ pts: [CGPoint], width: CGFloat, color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.beginPath()
    ctx.addLines(between: pts)
    ctx.strokePath()
}

/// Fill between the curve and the zero line, one lobe only — points on the
/// wrong side are dropped (not clamped) so no degenerate strip runs along the
/// zero line across the other half.
func fillLobe(_ ctx: CGContext, _ pts: [CGPoint], zero: CGFloat, above: Bool, top: CGColor, bottom: CGColor) {
    let side = pts.filter { above ? $0.y > zero : $0.y < zero }
    guard side.count > 2 else { return }
    let lobe = [CGPoint(x: side.first!.x, y: zero)] + side + [CGPoint(x: side.last!.x, y: zero)]
    ctx.saveGState()
    ctx.beginPath()
    ctx.addLines(between: lobe)
    ctx.addLine(to: CGPoint(x: lobe.last!.x, y: zero))
    ctx.addLine(to: CGPoint(x: lobe.first!.x, y: zero))
    ctx.closePath()
    ctx.clip()
    let grad = CGGradient(colorsSpace: nil, colors: [top, bottom] as CFArray, locations: [0, 1])!
    let ys = lobe.map(\.y) + [zero]
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: ys.max()!), end: CGPoint(x: 0, y: ys.min()!), options: [])
    ctx.restoreGState()
}

func slackDot(_ ctx: CGContext, at p: CGPoint, r: CGFloat, halo: CGFloat) {
    ctx.setFillColor(rgb(0x88B868, 0.28))
    ctx.fillEllipse(in: CGRect(x: p.x - halo, y: p.y - halo, width: halo * 2, height: halo * 2))
    ctx.setFillColor(leaf)
    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    // navy ring so the dot reads against both lobes
    ctx.setStrokeColor(navy)
    ctx.setLineWidth(r * 0.22)
    ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
}

/// Zero crossing of the drawn curve nearest the frame centre.
func crossing(_ pts: [CGPoint], zero: CGFloat) -> CGPoint {
    var best = pts[0]
    for (a, b) in zip(pts, pts.dropFirst()) where (a.y - zero) * (b.y - zero) <= 0 {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: zero)
        if abs(mid.x - S / 2) < abs(best.x - S / 2) || best.y != zero { best = mid }
    }
    return best
}

// A — signed curve with flood/ebb lobes + slack dot at the crossing.
func candidateA() {
    let ctx = makeContext()
    field(ctx)
    let zero = S * 0.5, amp = S * 0.23
    let pts = curvePoints(zero: zero, amp: amp, x0: -S * 0.06, x1: S * 1.06)
    // faint zero line
    ctx.setStrokeColor(rgb(0xE4F0E4, 0.2))
    ctx.setLineWidth(7)
    ctx.beginPath()
    // Full width: the curve bleeds off both edges, so an inset line reads as
    // unfinished rather than as a deliberate margin.
    ctx.addLines(between: [CGPoint(x: 0, y: zero), CGPoint(x: S, y: zero)])
    ctx.strokePath()
    // Flood above the zero line, ebb below — the app's diverging direction
    // axis. Green is absent here on purpose: it means slack, and slack is the
    // dot at the crossing, not a lobe.
    fillLobe(ctx, pts, zero: zero, above: true, top: rgb(0x4A9FD8, 0.6), bottom: rgb(0x4A9FD8, 0.05))
    fillLobe(ctx, pts, zero: zero, above: false, top: rgb(0xE8A33D, 0.05), bottom: rgb(0xE8A33D, 0.6))
    strokeCurve(ctx, pts, width: 36, color: sky)
    slackDot(ctx, at: crossing(pts, zero: zero), r: 66, halo: 135)
    save(ctx, "icon-candidate-a.png")
}

// B — minimalist: thick curve + dot, no fills (the placeholder, disciplined).
func candidateB() {
    let ctx = makeContext()
    field(ctx)
    let zero = S * 0.5, amp = S * 0.21
    let pts = curvePoints(zero: zero, amp: amp, x0: S * 0.05, x1: S * 0.95)
    strokeCurve(ctx, pts, width: 62, color: sky)
    slackDot(ctx, at: crossing(pts, zero: zero), r: 82, halo: 155)
    save(ctx, "icon-candidate-b.png")
}

// C — go-window: curve + slack dot ringed by a leaf arc (the transit window).
func candidateC() {
    let ctx = makeContext()
    field(ctx)
    let zero = S * 0.5, amp = S * 0.21
    let pts = curvePoints(zero: zero, amp: amp, x0: -S * 0.06, x1: S * 1.06)
    fillLobe(ctx, pts, zero: zero, above: true, top: rgb(0x88B868, 0.42), bottom: rgb(0x88B868, 0.04))
    fillLobe(ctx, pts, zero: zero, above: false, top: rgb(0x7FB4D8, 0.04), bottom: rgb(0x7FB4D8, 0.42))
    strokeCurve(ctx, pts, width: 32, color: sky)
    let c = crossing(pts, zero: zero)
    slackDot(ctx, at: c, r: 56, halo: 0)
    ctx.setStrokeColor(rgb(0x88B868, 0.85))
    ctx.setLineWidth(24)
    ctx.strokeEllipse(in: CGRect(x: c.x - 160, y: c.y - 160, width: 320, height: 320))
    save(ctx, "icon-candidate-c.png")
}

candidateA()
candidateB()
candidateC()
