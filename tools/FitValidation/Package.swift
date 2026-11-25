// swift-tools-version: 6.0
// File-input reference harness for the fill and patch pipelines. The frozen
// JavaScript oracle remains their fitter; SlackwaterKit predicts the holdout.
// Pinned to the same slackwater revision as Slackwater.xcodeproj/project.xcproj.
import PackageDescription

let package = Package(
    name: "FitValidation",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Exact-commit pin: the stack is in prerelease (slackwater#338 stage
        // 4), so no post-rename semver tag exists yet. Becomes `from:` at the
        // deliberate 1.0.0 release.
        .package(url: "https://github.com/openwatersio/slackwater",
                 revision: "2d8dc9e3643c92fcfc5a53a1fecd240ec2312c81"),
    ],
    targets: [
        .executableTarget(
            name: "fit-validation",
            dependencies: [.product(name: "SlackwaterKit", package: "slackwater")]),
        .testTarget(name: "FitValidationTests", dependencies: ["fit-validation"]),
    ])
