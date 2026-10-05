import AppKit
import ImageIO
import UniformTypeIdentifiers

enum CaptureError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self {
        case .invalid(let message): return message
        }
    }
}

let acceptedSizes = [(1280, 800), (1440, 900), (2560, 1600), (2880, 1800)]

func pixelSize(_ text: String) throws -> (Int, Int) {
    let components = text.split(separator: "x")
    let parts = components.compactMap { Int($0) }
    guard components.count == 2, parts.count == 2,
        acceptedSizes.contains(where: { $0 == parts[0] && $1 == parts[1] })
    else {
        throw CaptureError.invalid("Not an Apple-accepted Mac screenshot size: \(text)")
    }
    return (parts[0], parts[1])
}

func loadImage(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw CaptureError.invalid("Cannot read image: \(path)")
    }
    return image
}

func verify(_ path: String, size: (Int, Int)) throws {
    let image = try loadImage(path)
    guard image.width == size.0, image.height == size.1,
        image.colorSpace?.model == .rgb,
        [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo),
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        CGImageSourceGetType(source) as String? == UTType.png.identifier
    else {
        throw CaptureError.invalid("Expected an opaque RGB PNG at \(size.0) × \(size.1): \(path)")
    }
    print("Verified \(image.width) × \(image.height), RGB, no alpha: \(path)")
}

func export(_ source: String, to destination: String, size: (Int, Int)) throws {
    let image = try loadImage(source)
    guard image.width * size.1 == image.height * size.0 else {
        throw CaptureError.invalid(
            "Capture is \(image.width) × \(image.height), not 16:10. Resize the window before capturing."
        )
    }
    guard image.width >= size.0, image.height >= size.1 else {
        throw CaptureError.invalid(
            "Capture is only \(image.width) × \(image.height). Use a Retina display or MAC_PIXELS=1280x800; screenshots are never upscaled."
        )
    }
    guard
        let context = CGContext(
            data: nil, width: size.0, height: size.1,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else {
        throw CaptureError.invalid("Cannot create RGB image context.")
    }
    // macOS rounds the window corners; App Store uploads must have no alpha channel.
    context.setFillColor(CGColor(gray: 0.04, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size.0, height: size.1))
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size.0, height: size.1))
    guard let flattened = context.makeImage(),
        let output = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: destination) as CFURL,
            UTType.png.identifier as CFString, 1, nil)
    else {
        throw CaptureError.invalid("Cannot write PNG: \(destination)")
    }
    CGImageDestinationAddImage(output, flattened, nil)
    guard CGImageDestinationFinalize(output) else {
        throw CaptureError.invalid("Failed to write \(destination)")
    }
}

func slackwaterApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter {
        ["org.openwaters.slackwater", "io.openwaters.slackwater"].contains(
            $0.bundleIdentifier ?? "")
    }
}

#if !SCREENSHOT_TEST
    @main
    struct MacScreenshot {
        static func main() {
            do {
                let args = Array(CommandLine.arguments.dropFirst())
                switch args.first {
                case "app":
                    let apps = slackwaterApps()
                    guard apps.count == 1, let id = apps[0].bundleIdentifier else {
                        throw CaptureError.invalid(
                            "Run exactly one Slackwater app, or specify MAC_BUNDLE_ID.")
                    }
                    print(id)
                case "placement" where args.count == 3:
                    guard let width = Int(args[1]), let height = Int(args[2]),
                        let screen = NSScreen.main,
                        screen.visibleFrame.width >= CGFloat(width),
                        screen.visibleFrame.height >= CGFloat(height)
                    else {
                        throw CaptureError.invalid(
                            "The main display must have room for the requested window outside full screen."
                        )
                    }
                    let top = NSScreen.screens[0].frame.maxY
                    print(
                        "\(Int(screen.visibleFrame.midX) - width / 2),\(Int(top - screen.visibleFrame.midY) - height / 2)"
                    )
                case "window" where args.count == 4:
                    let apps = NSRunningApplication.runningApplications(
                        withBundleIdentifier: args[1])
                    guard apps.count == 1, let width = Int(args[2]), let height = Int(args[3]),
                        let windows = CGWindowListCopyWindowInfo(
                            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                            as? [[String: Any]]
                    else {
                        throw CaptureError.invalid("Cannot find one running Slackwater process.")
                    }
                    let matches = windows.filter { row in
                        guard
                            row[kCGWindowOwnerPID as String] as? Int
                                == Int(apps[0].processIdentifier),
                            row[kCGWindowLayer as String] as? Int == 0,
                            let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                            let rect = CGRect(dictionaryRepresentation: bounds)
                        else { return false }
                        return Int(rect.width) == width && Int(rect.height) == height
                    }
                    guard matches.count == 1, let id = matches[0][kCGWindowNumber as String] as? Int
                    else {
                        throw CaptureError.invalid(
                            "No unique \(width) × \(height) Slackwater window. Close extra windows and retry."
                        )
                    }
                    print(id)
                case "export" where args.count == 4:
                    try export(args[1], to: args[2], size: pixelSize(args[3]))
                case "verify" where args.count == 3: try verify(args[1], size: pixelSize(args[2]))
                case "metadata" where args.count == 2:
                    guard
                        let app = NSRunningApplication.runningApplications(
                            withBundleIdentifier: args[1]
                        ).first,
                        let url = app.bundleURL, let bundle = Bundle(url: url)
                    else {
                        throw CaptureError.invalid("Cannot read the running app's version.")
                    }
                    print(
                        "Slackwater \(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown") (\(bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown"))"
                    )
                    print(
                        "Bundle: \(args[1])\nApp: \(url.path)\nCaptured: \(ISO8601DateFormatter().string(from: Date()))"
                    )
                default: throw CaptureError.invalid("Unknown mac-screenshot helper command.")
                }
            } catch {
                fputs("\(error)\n", stderr)
                exit(1)
            }
        }
    }
#endif
