import XCTest

/// Shared plumbing for the source-text linter tests (TypeScaleTests,
/// ColourAndFormTests, HeroChromeTests): `#filePath` of this file sits in
/// SlackwaterTests/, so the repo root is one level up and the app sources
/// live under Slackwater/. One walk, one file set — the per-test copies this
/// replaces had identical semantics (FileManager.enumerator over Slackwater/,
/// `.swift` only, no exclusions) and drifted only in how they spelled it.
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // SlackwaterTests/
    .deletingLastPathComponent()   // repo root

/// Every Swift file under Slackwater/ as (name, source). Repo-wide, not
/// file-scoped, and deliberately so: the last time this project guarded a
/// retired token one file at a time, the survivor was in the file nobody
/// thought to check. The count floor keeps a scan that silently found no
/// files from passing forever.
func appSources() throws -> [(name: String, source: String)] {
    let root = repoRoot.appendingPathComponent("Slackwater")
    let files = try XCTUnwrap(
        FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
        "could not walk \(root.path)")
    var out: [(String, String)] = []
    for case let url as URL in files where url.pathExtension == "swift" {
        out.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
    }
    XCTAssertGreaterThan(out.count, 10, "expected to scan the app's sources")
    return out
}

/// One repo file by path relative to the repo root (e.g.
/// "Slackwater/MapScreen.swift", "project.yml").
func repoSource(_ path: String) throws -> String {
    try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
}
