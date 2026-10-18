// swift-tools-version: 6.0
// Reference harness: fit a CHS station (tides with SlackwaterKit's native
// fitter, currents with the frozen JS artifacts in tools/chs-reference), predict
// the held-out validation window with SlackwaterKit (the app's shipping
// predictor), and score against live IWLS — the M0 spike's methodology.
// Pinned to the same slackwater revision as project.yml.
import PackageDescription

let package = Package(
    name: "FitValidation",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Exact-commit pin: the stack is in prerelease (slackwater#338 stage
        // 4), so no post-rename semver tag exists yet. Becomes `from:` at the
        // deliberate 1.0.0 release.
        .package(url: "https://github.com/openwatersio/slackwater",
                 revision: "bd9f1b2424c1c8abd580499329af3b14c7debe07"),
    ],
    targets: [
        .executableTarget(
            name: "fit-validation",
            dependencies: [.product(name: "SlackwaterKit", package: "slackwater")]),
    ])
