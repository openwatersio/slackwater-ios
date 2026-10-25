import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ArtworkError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func fail(_ message: String) throws -> Never {
    throw ArtworkError(message: message)
}

func load(_ url: URL) throws -> CGImage {
    guard FileManager.default.fileExists(atPath: url.path) else {
        try fail("Missing capture: \(url.lastPathComponent)")
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        try fail("Unreadable capture: \(url.lastPathComponent)")
    }
    return image
}

let background = NSColor(srgbRed: 0.035, green: 0.106, blue: 0.176, alpha: 1)
let ink = NSColor(srgbRed: 0.953, green: 0.961, blue: 0.933, alpha: 1)
let secondary = NSColor(srgbRed: 0.741, green: 0.812, blue: 0.702, alpha: 1)

func render(width: Int, height: Int, title: String, subtitle: String,
            images: [CGImage], output: URL) throws {
    let w = CGFloat(width), h = CGFloat(height)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        try fail("Cannot allocate artwork")
    }
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }
    context.setFillColor(background.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let margin = w * 0.06
    let titleSize = min(w * 0.085, 132)
    let titleHeight = titleSize * 2.5
    let titleTop = h * 0.055
    func text(_ string: String, size: CGFloat, weight: NSFont.Weight,
              color: NSColor, top: CGFloat, height: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]
        NSAttributedString(string: string, attributes: attributes).draw(
            in: CGRect(x: margin, y: h - top - height, width: w - margin * 2, height: height))
    }
    text(title, size: titleSize, weight: .semibold, color: ink,
         top: titleTop, height: titleHeight)
    let subtitleTop = titleTop + titleHeight + h * 0.012
    let subtitleHeight = min(w * 0.07, 90) * CGFloat(subtitle.components(separatedBy: "\n").count)
    text(subtitle, size: min(w * 0.032, 47), weight: .regular, color: secondary,
         top: subtitleTop, height: subtitleHeight)
    var top = subtitleTop + subtitleHeight + h * 0.025
    let gap = h * 0.025
    let available = h - top - gap
    let totalNativeHeight = images.reduce(CGFloat.zero) { $0 + CGFloat($1.height) }
    let widthScale = images.map { (w - margin * 2) / CGFloat($0.width) }.min()!
    let scale = min(1, widthScale, (available - gap * CGFloat(images.count - 1)) / totalNativeHeight)
    guard scale > 0 else { try fail("Artwork has no room for captures") }
    for image in images {
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (w - size.width) / 2, y: h - top - size.height,
                                      width: size.width, height: size.height))
        top += size.height + gap
    }
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        try fail("Cannot write \(output.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { try fail("PNG export failed") }
}

do {
    let args = CommandLine.arguments
    guard args.count == 4 else { try fail("Usage: swift scripts/appstore-artwork.swift <raw-phone-or-ipad-dir> <raw-watch-dir> <new-output-dir>") }
    let raw = URL(fileURLWithPath: args[1]), watch = URL(fileURLWithPath: args[2])
    let output = URL(fileURLWithPath: args[3])
    let names = ["01-currents-slack.png", "02-tide-rising.png", "03-scrubber.png", "04-nearby.png", "05-map.png", "widgets.png"]
    let captures = try names.map { try load(raw.appendingPathComponent($0)) }
    let wrist = try load(watch.appendingPathComponent("02-tide.png"))
    let width = captures[0].width, height = captures[0].height
    let accepted = [(1206, 2622), (1179, 2556), (1320, 2868), (1290, 2796), (1260, 2736), (2064, 2752), (2048, 2732)]
    guard accepted.contains(where: { $0 == width && $1 == height }) else { try fail("Unsupported portrait capture size: \(width)x\(height)") }
    guard captures.prefix(5).allSatisfy({ $0.width == width && $0.height == height }) else {
        try fail("Phone or iPad captures have mixed dimensions")
    }
    guard [(422, 514), (410, 502)].contains(where: { $0 == wrist.width && $1 == wrist.height }) else {
        try fail("Unsupported Watch capture size")
    }
    guard !FileManager.default.fileExists(atPath: output.path) else { try fail("Output directory already exists; use a new directory") }
    let frames: [(String, String, String, [CGImage])] = [
        ("01-currents.png", "Find the next\nslack window.", "Current predictions · US & Canada", [captures[0]]),
        ("02-tides.png", "Tides worldwide.\nWithout signal.", "Free predictions · Every date", [captures[1]]),
        ("03-widgets-watch.png", "The tide,\nat a glance.", "Free home-screen widgets\nFree Watch app. No phone needed.", [captures[5], wrist]),
        ("04-night.png", "Move through\nthe day and night.", "Sun, moon and tides on one timeline", [captures[2]]),
        ("05-nearby.png", "Your places.\nOne quick look.", "Tides and currents near you", [captures[3]]),
        ("06-map.png", "Find your\nnext place.", "Tides worldwide · Currents in US & Canada", [captures[4]]),
    ]
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, title, subtitle, images) in frames {
        try render(width: width, height: height, title: title, subtitle: subtitle,
                   images: images, output: output.appendingPathComponent(name))
    }
    print("Exported six \(width)x\(height) screenshots to \(output.path)")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
