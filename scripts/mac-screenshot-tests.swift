import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct ScreenshotChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func fixture(_ name: String, width: Int, height: Int) -> String {
            let path = directory.appendingPathComponent(name).path
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 10, y: 10, width: width - 20, height: height - 20))
            let output = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL,
                UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(output, context.makeImage()!, nil)
            precondition(CGImageDestinationFinalize(output))
            return path
        }

        func rejects(_ name: String, _ action: () throws -> Void) {
            do {
                try action()
                fatalError("Expected rejection: \(name)")
            } catch { print("Rejected \(name): \(error)") }
        }

        let retina = fixture("retina.png", width: 2560, height: 1600)
        let exported = directory.appendingPathComponent("export.png").path
        try export(retina, to: exported, size: (2560, 1600))
        try verify(exported, size: (2560, 1600))
        try export(retina, to: exported, size: (1280, 800))
        try verify(exported, size: (1280, 800))
        let bytes = try loadImage(exported).dataProvider!.data! as Data
        precondition(
            bytes[0] > 0 && bytes[0] < 30,
            "Transparent corners must flatten onto the dark background.")

        let wrongAspect = fixture("wrong.png", width: 2560, height: 1599)
        rejects("wrong aspect ratio") { try export(wrongAspect, to: exported, size: (2560, 1600)) }
        let small = fixture("small.png", width: 1280, height: 800)
        rejects("upscaling") { try export(small, to: exported, size: (2560, 1600)) }
        rejects("transparent upload") { try verify(retina, size: (2560, 1600)) }
        rejects("wrong export dimensions") { try verify(exported, size: (2560, 1600)) }
        rejects("non-Apple size") { _ = try pixelSize("1920x1200") }
        for (width, height) in acceptedSizes { _ = try pixelSize("\(width)x\(height)") }
        print("Mac screenshot checks passed.")
    }
}
