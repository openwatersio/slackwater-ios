// swift-tools-version: 5.9
// M3 exit-check harness: fit a CHS station with the app's exact JS artifacts
// (Resources/chs-bundle.js + chs-glue.js in JavaScriptCore), predict the
// held-out validation window with SlackwaterKit (the app's shipping predictor),
// and score against live IWLS — the M0 spike's methodology, on the M3 path.
import PackageDescription

let package = Package(
    name: "FitValidation",
    platforms: [.macOS(.v14)],
    dependencies: [
        // The engine's rename branch (openwatersio/neaps#339). On flip day
        // (neaps#338) this becomes the renamed repo URL and a `from:` version.
        .package(url: "https://github.com/openwatersio/neaps",
                 revision: "6d84b3f2ffbf13b1a080779a2e6c10c59b17f5d9"),
    ],
    targets: [
        .executableTarget(
            name: "fit-validation",
            dependencies: [.product(name: "SlackwaterKit", package: "neaps")]),
    ])
