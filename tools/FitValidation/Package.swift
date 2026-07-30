// swift-tools-version: 5.9
// M3 exit-check harness: fit a CHS station with the app's exact JS artifacts
// (Resources/chs-bundle.js + chs-glue.js in JavaScriptCore), predict the
// held-out validation window with TideEngine (the app's shipping predictor),
// and score against live IWLS — the M0 spike's methodology, on the M3 path.
import PackageDescription

let package = Package(
    name: "FitValidation",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sailingnaturali/slackwater-engine", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "fit-validation",
            dependencies: [.product(name: "TideEngine", package: "slackwater-engine")]),
    ])
