// Slackwater — GPL v3. Shared plumbing for the render tests: draw a SwiftUI
// view off-screen and ask whether anything landed on it.
//
// What this target can and cannot see, because the boundary is not obvious:
//
//   * INK works. `ImageRenderer` hands back a real bitmap of any pure-SwiftUI
//     view, which is enough to catch the blank-chart failure mode. It runs no
//     `onAppear` and no `.task`, and it draws no `UIViewRepresentable` — a
//     MapLibre header or a `TimelineScrubber` comes out empty — so it is only
//     ever pointed at drawing leaves like `TimelineCanvas`.
//   * SIZE works: host the view in a `UIHostingController` and ask
//     `sizeThatFits` — the probe for "how tall does this get at
//     accessibility5".
//   * The RENDERED TEXT and the PER-ELEMENT FRAMES do not. A `_UIHostingView`
//     in this target builds no subviews and an empty accessibility tree
//     (`accessibilityElements` is empty, laid out, in a key window, after a
//     run-loop turn) — SwiftUI populates it only for a live assistive client,
//     and no test-only switch turns that on. So "this view says X" and "this
//     control sits below that one" are questions only the UI target can
//     answer; a unit test that walks for them silently finds nothing and
//     passes vacuously. Reach for a size probe or ink instead.
import SwiftUI
import UIKit
@testable import Slackwater

/// The share of an image's pixels that differ from its most common colour —
/// "is anything drawn here". The same measure the UI suite takes off a device
/// screenshot, over an `ImageRenderer` bitmap instead.
///
/// The UI target's 0.05 threshold does NOT carry over, and reusing it would be
/// worse than no test at all: it was calibrated against a device screenshot
/// whose "blank" was 0.008 — a strip element holding only the centerline, the
/// riding dot and the ft axis, SwiftUI overlays drawn ON TOP of the canvas. An
/// `ImageRenderer` shot of `TimelineCanvas` alone has no overlays and the whole
/// 228-hour span of day chrome. A completely blank chart would sail past 0.05
/// here, and a drawn one sits under it. `drawnStripInk` is the threshold
/// measured against the real floor; see it for the numbers.
func inkFraction(_ image: UIImage) -> Double {
    guard let cg = image.cgImage else { return 0 }
    let w = cg.width, h = cg.height
    guard w > 0, h > 0 else { return 0 }
    var px = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return 0 }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var counts: [UInt32: Int] = [:]
    for i in stride(from: 0, to: px.count, by: 4) {
        counts[UInt32(px[i]) << 16 | UInt32(px[i + 1]) << 8 | UInt32(px[i + 2]), default: 0] += 1
    }
    guard let bg = counts.max(by: { $0.value < $1.value })?.key else { return 0 }
    let r = Int(bg >> 16), g = Int((bg >> 8) & 0xFF), b = Int(bg & 0xFF)
    var ink = 0
    for i in stride(from: 0, to: px.count, by: 4)
    where max(abs(Int(px[i]) - r), abs(Int(px[i + 1]) - g), abs(Int(px[i + 2]) - b)) > 24 {
        ink += 1
    }
    return Double(ink) / Double(w * h)
}

/// The share of an image's pixels that are COPPER — red well ahead of blue,
/// and green held down.
///
/// `inkFraction` cannot see the eclipse: the umbra replaces lit moon with
/// copper rather than adding to it, so the count of not-background pixels
/// barely moves (measured 0.388 clean against 0.389 eclipsed on the glyph).
///
/// Warmth alone is not enough either, and this cost a red test: the strip's
/// sun dots (`SN.sun` 0xF0C860) and sunrise labels are warm too. What
/// separates them is green — the sun is a bright yellow (g 200 against r 240),
/// the umbra a dark copper (g 42 against r 107). Hence the second clause.
func copperFraction(_ image: UIImage) -> Double {
    guard let cg = image.cgImage else { return 0 }
    let w = cg.width, h = cg.height
    guard w > 0, h > 0 else { return 0 }
    var px = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return 0 }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var warm = 0
    for i in stride(from: 0, to: px.count, by: 4)
    where Int(px[i]) - Int(px[i + 2]) > 40 && Double(px[i + 1]) < Double(px[i]) * 0.75 {
        warm += 1
    }
    return Double(warm) / Double(w * h)
}

/// The share of pixels that differ between two renders of the same thing.
///
/// The measure for "did this mark draw at all" when a colour threshold cannot
/// answer it. Both of the eclipse's marks defeat a threshold, for opposite
/// reasons: the penumbral wash over a near-white disc lands as a warm grey
/// (r-b 32, under `copperFraction`'s bar), and the strip's band over a
/// near-black canvas is fainter still. Rendering the SAME data twice, once
/// with the mark and once without, leaves the mark as the only difference.
func differingFraction(_ a: UIImage, _ b: UIImage) -> Double {
    guard let ca = a.cgImage, let cb = b.cgImage,
          ca.width == cb.width, ca.height == cb.height else { return 0 }
    let w = ca.width, h = ca.height
    guard w > 0, h > 0 else { return 0 }
    func pixels(_ cg: CGImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return px }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return px
    }
    let pa = pixels(ca), pb = pixels(cb)
    var differing = 0
    for i in stride(from: 0, to: pa.count, by: 4)
    where max(abs(Int(pa[i]) - Int(pb[i])),
              abs(Int(pa[i + 1]) - Int(pb[i + 1])),
              abs(Int(pa[i + 2]) - Int(pb[i + 2]))) > 4 {
        differing += 1
    }
    return Double(differing) / Double(w * h)
}

/// The timeline strip's drawn layer, as a bitmap. `TimelineCanvas` is the whole
/// picture — curve and fill, day chrome, event bands, gutter times — and it is
/// a pure SwiftUI `Canvas`, so it is the part of the strip a renderer can see;
/// `TimelineScrubStrip` wraps it in a `UIViewRepresentable` scroll view that an
/// off-screen render hands back empty.
///
/// Rendered at the strip's full 228-hour width so the measure covers the same
/// span the app draws, not just the viewport a phone opens on.
@MainActor
func stripImage(_ data: TimelineData, imperial: Bool = true, now: Date = appNow()) -> UIImage? {
    let geo = TimelineGeo(data: data)
    let renderer = ImageRenderer(content:
        TimelineCanvas(data: data, geo: geo, imperial: imperial, speedUnit: "kn", now: now)
            .frame(width: data.totalWidth, height: geo.height)
            .background(SN.canvas))
    return renderer.uiImage
}

/// A timeline of the same window with no track at all — the floor every ink
/// threshold is measured against. Day chrome (night bands, day labels, sun
/// dots) still draws, which is exactly why the floor is not zero, and why each
/// test asserts on it rather than trusting the number below to stay true.
@MainActor
func blankStripInk(tz: TimeZone, now: Date = appNow()) -> Double {
    let blank = TimelineData.build(tide: nil, current: nil, now: now, anchor: todayLocal(tz))
    return stripImage(blank).map(inkFraction) ?? 0
}

/// "Something is on this strip beyond its day chrome." Measured over
/// `ImageRenderer` at 1×, full 228-hour width, on a 396pt canvas — the height
/// `TimelineGeo` gives a single-track strip: a 160pt lead pad, a 150pt plot,
/// and the time, day and moon rows under it. Every number here scales with
/// that height, because the ink is a FRACTION of the bitmap and the pad is
/// empty canvas — the lead and its pills are SwiftUI overlays, drawn above
/// this bitmap, not into it. A geometry change moves all six numbers, so
/// re-measure rather than nudging the threshold.
///
///     no track (day chrome only)   0.028
///     online gate (fetched speeds) 0.075   ← the lowest drawn shape
///     derived gate (schematic ±1)  0.090
///     Boston tide                  0.097
///     Avonmouth tide               0.102
///     Friday Harbor tide           0.115
///
/// 0.046 sits in the gap, with ~1.6× of margin either side. The online gate
/// sets the low end: its fetched curve spends the window near zero, hugging
/// the middle of a plot the tide curves fill top to bottom.
let drawnStripInk = 0.046
