import XCTest

final class ProjectTests: XCTestCase {
    func testEverySourceAndResourceBuildsInItsPrimaryTarget() throws {
        let project = try repoProject()
        var membership: [String: Set<String>] = [:]
        func walk(_ files: [[String: Any]], parent: String) {
            for file in files {
                let path = [parent, file["path"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: "/")
                for item in file["target-membership"] as? [Any] ?? [] {
                    if let target = item as? String ?? (item as? [String: Any])?["build-phase"] as? String {
                        membership[target, default: []].insert(path)
                    }
                }
                walk(file["children"] as? [[String: Any]] ?? [], parent: path)
            }
        }
        walk(try XCTUnwrap(project["files"] as? [[String: Any]]), parent: "")
        let targets = try XCTUnwrap(project["targets"] as? [[String: Any]])
        for target in targets {
            let name = try XCTUnwrap(target["name"] as? String)
            let files = try XCTUnwrap(FileManager.default.enumerator(
                at: repoRoot.appendingPathComponent(name), includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]))
            var sources: Set<String> = []
            var resources: Set<String> = []
            for case let url as URL in files {
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                let path = String(url.path.dropFirst(repoRoot.path.count + 1))
                if url.pathExtension == "swift" {
                    sources.insert(path)
                } else if url.lastPathComponent != "Info.plist" && url.pathExtension != "entitlements"
                    && !["Slackwater/Resources/stations.json", "Slackwater/Resources/currents.json"].contains(path) {
                    resources.insert(path)
                }
            }
            XCTAssertFalse(sources.isEmpty, "No Swift sources found for \(name)")
            let compiled = membership["\(name)/compile-sources", default: []]
            XCTAssertTrue(sources.isSubset(of: compiled),
                          "Add target membership for: \(sources.subtracting(compiled).sorted())")
            let bundled = membership["\(name)/resources", default: []]
            let missing = resources.filter { path in
                !bundled.contains { path == $0 || path.hasPrefix($0 + "/") }
            }
            XCTAssertTrue(missing.isEmpty, "Add resource membership for: \(missing.sorted())")
        }
    }

    func testVersionsStaySharedAndPremiumBuildsInBothConfigurations() throws {
        let project = try repoProject()
        let settings = try XCTUnwrap(project["build-settings"] as? [String: Any])
        for config in ["Debug", "Release"] {
            let conditions = try XCTUnwrap(settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=\(config)]"] as? String)
            XCTAssertTrue(conditions.split(separator: " ").contains("PREMIUM_ENABLED"))
        }
        XCTAssertEqual(settings["IPHONEOS_DEPLOYMENT_TARGET"] as? String, "26.0")
        XCTAssertEqual(settings["WATCHOS_DEPLOYMENT_TARGET"] as? String, "26.0")
        let profiles = ["Slackwater": "Slackwater App Store", "SlackwaterWidgets": "Slackwater Widgets App Store",
                        "SlackwaterWatch": "Slackwater Watch App Store", "SlackwaterWatchWidgets": "Slackwater Watch Widgets App Store"]
        for target in try XCTUnwrap(project["targets"] as? [[String: Any]]) {
            let overrides = try XCTUnwrap(target["build-settings"] as? [String: Any])
            let name = try XCTUnwrap(target["name"] as? String)
            if let profile = profiles[name] {
                XCTAssertEqual(overrides["CODE_SIGN_STYLE[config=Release]"] as? String, "Manual", name)
                XCTAssertEqual(overrides["CODE_SIGN_IDENTITY[config=Release]"] as? String, "Apple Distribution", name)
                XCTAssertEqual(overrides["PROVISIONING_PROFILE_SPECIFIER[config=Release]"] as? String, profile, name)
                let plist = try XCTUnwrap(PropertyListSerialization.propertyList(
                    from: Data(repoSource("\(name)/Info.plist").utf8), format: nil) as? [String: Any])
                XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "$(MARKETING_VERSION)", name)
                XCTAssertEqual(plist["CFBundleVersion"] as? String, "$(CURRENT_PROJECT_VERSION)", name)
            }
            XCTAssertFalse(overrides.keys.contains {
                $0 == "MARKETING_VERSION" || $0.hasPrefix("MARKETING_VERSION[")
                    || $0 == "CURRENT_PROJECT_VERSION" || $0.hasPrefix("CURRENT_PROJECT_VERSION[")
            }, "\(target["name"] ?? "target") must inherit the shared version settings")
        }
    }
}
