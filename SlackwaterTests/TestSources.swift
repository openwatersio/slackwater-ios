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

/// One source line with any `//` comment removed — the line as the COMPILER
/// sees it. Source-text linters scan for a token they want banned from the
/// CODE, and a comment saying "deliberately not <token>, because …" is the
/// documentation the next person needs, not an offence. Without this,
/// `testOnlyTheWordmarkShrinks` counted such a comment as a second
/// `minimumScaleFactor` and went red on a file that has none.
///
/// ponytail: a plain `//` split, not a lexer — a `//` inside a string literal
/// (a URL) truncates the line early, hiding anything after it on that line.
/// No banned token in this repo sits after a URL. Reach for a real lexer the
/// first time one does.
func codeOnly(_ line: String) -> String {
    String(line[line.startIndex..<(line.range(of: "//")?.lowerBound ?? line.endIndex)])
}

/// One repo file by path relative to the repo root (e.g.
/// "Slackwater/MapScreen.swift", "project.yml").
func repoSource(_ path: String) throws -> String {
    try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
}
