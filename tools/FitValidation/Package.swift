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
        // Exact-commit pin: the stack is in prerelease (slackwater#338 stage
        // 4), so no post-rename semver tag exists yet. Becomes `from:` at the
        // deliberate 1.0.0 release.
        .package(url: "https://github.com/openwatersio/slackwater",
                 revision: "83e439b8c5d0997ae4b5fadef693efdf90637957"),
    ],
    targets: [
        .executableTarget(
            name: "fit-validation",
            dependencies: [.product(name: "SlackwaterKit", package: "slackwater")]),
    ])
