// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpikeRunner",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "SpikeRunner", path: "Sources/SpikeRunner")]
)
