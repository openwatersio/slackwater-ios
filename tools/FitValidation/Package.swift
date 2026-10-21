// swift-tools-version: 6.0
// Reference harness: fit a CHS current gate with the frozen JS artifacts
// (tools/chs-reference in JavaScriptCore), predict the held-out validation
// window with SlackwaterKit (the app's shipping predictor), and score against
// live IWLS. Pinned to the same slackwater revision as project.yml.
import PackageDescription

let package = Package(
    name: "FitValidation",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Exact-commit pin: the stack is in prerelease (slackwater#338 stage
        // 4), so no post-rename semver tag exists yet. Becomes `from:` at the
        // deliberate 1.0.0 release.
        .package(url: "https://github.com/openwatersio/slackwater",
                 revision: "661f3afb082e84a45e0b27c5c55ac99ad78268dc"),
    ],
    targets: [
        .executableTarget(
            name: "fit-validation",
            dependencies: [.product(name: "SlackwaterKit", package: "slackwater")]),
    ])
