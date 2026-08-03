# SF and Dynamic Type Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire the three bundled font families for SF under Dynamic Type, and make the station card reflow so it stays readable from the smallest setting to the largest accessibility size.

**Architecture:** Six tasks in dependency order. Tasks 1–2 are a mechanical collapse of 119 ad-hoc `(size, weight)` call sites onto ~10 semantic Dynamic Type styles, guarded by a repo-wide source scan. Task 3 extracts the card shell that four hand-rolled variants currently duplicate. Task 4 puts `ViewThatFits` in that one shell with three progressively-reduced tiers. Task 5 scales the things that sit *beside* text and would otherwise stay frozen. Task 6 is verification across the size range on both devices.

**Tech Stack:** SwiftUI, XCTest, XcodeGen (`project.yml` → `.xcodeproj`), `./scripts/test.sh`.

Spec: `docs/superpowers/specs/2026-08-02-sf-and-dynamic-type-design.md`

## Global Constraints

- **Branch:** `type/sf-and-dynamic-type`. Never commit to `main` in this repo — it is branch-and-PR on every machine (`CONTRIBUTING.md`).
- **Run `xcodegen generate` after any `git switch` and after any `project.yml` edit.** Skipping it produces "Build input file cannot be found" while the test reporter cheerfully says `0 passed, 0 failed`.
- **Run `./scripts/test.sh` in the FOREGROUND.** It takes ~20 minutes. Do not background it and end your turn — four implementers have already stalled that way. If your harness times out, say so in your report and hand the run back rather than guessing.
- **No size floor.** Do not add a minimum point size anywhere. Dynamic Type is the mechanism; a floor contradicts it.
- **No `Font.custom` and no `Font.system(size:)` with a literal.** Every font is a semantic style (`.body`, `.caption`, …), optionally with `.weight()`, `.monospaced()`, `.monospacedDigit()`. The one sanctioned exception is `@ScaledMetric` in Task 5, which scales a *non-text* dimension.
- **`minimumScaleFactor` comes off six sites and stays on one.** `SlackwaterApp.swift:658` (the wordmark) keeps its `0.6`. Read the comment above it before touching it. Do not go hunting for these sites opportunistically — each task says which, if any, it removes. Where a task's own mandated code omits `lineLimit`/`minimumScaleFactor` (the shell's name treatment in Task 3), that omission *is* the instruction and overrides this line; Task 4 depends on the name being free to wrap.
- **Colour is untouched.** This branch changes type and layout only. Do not alter any `SN.*` token, any hex literal, or any glyph tone binding — those are `ColourAndFormTests`' territory and it will fail loudly.
- **Copy is untouched, with exactly one exception.** No user-visible string changes anywhere *except* `SettingsView.swift`'s font attribution — see Task 1 Step 7b. Retiring the fonts makes that sentence false, and a false licence statement is not something to preserve for consistency's sake.
- **Line numbers in this plan are from before Task 1 and drift as you go.** Every task that cites one also gives you a `grep` that finds it. Trust the grep, never the number.

---

## File Structure

| File | Responsibility after this plan |
|---|---|
| `Slackwater/Theme.swift` | Colour tokens + `MonoLabel`. The `Font` extension is **deleted**. |
| `Slackwater/StationCard.swift` | **New.** The shared card shell: chrome, identity block, tier selection. |
| `Slackwater/SlackwaterApp.swift` | Card variants become thin callers of the shell. List chrome, FAB spacer. |
| `Slackwater/StationGlyph.swift` | Unchanged shape logic; gains no size opinion (callers scale it). |
| `Slackwater/MapHeader.swift` | Semantic styles, no `minimumScaleFactor`. |
| `Slackwater/{Current,Tide,Chs,DerivedGate}DetailView.swift`, `TimelineStrip.swift`, `OfflineDownloads.swift`, `SettingsView.swift` | Semantic styles only. |
| `SlackwaterTests/TypeScaleTests.swift` | **New.** Repo-wide guard + tier-content assertions. |
| `project.yml` | `UIAppFonts` block **deleted**. |
| `Slackwater/Resources/Fonts/` | **Deleted** (8 `.ttf` files). |

---

### Task 1: Collapse the type scale onto semantic styles

The app spells fonts 119 times using **41 distinct `(size, weight)` combinations** — nine different `geist` sizes from 9 to 17 alone. Most of that spread encodes nothing; it is per-screen eyeball tuning. This task collapses it and makes regression impossible with a source-text guard.

**Files:**
- Modify: `Slackwater/Theme.swift:80-100` (delete `Font` extension), `Slackwater/Theme.swift:103-114` (`MonoLabel`)
- Modify: `Slackwater/SlackwaterApp.swift` (49 sites), `CurrentDetailView.swift` (19), `TimelineStrip.swift` (13), `DerivedGateDetailView.swift` (12), `TideDetailView.swift` (10), `OfflineDownloads.swift` (6), `ChsDetailView.swift` (4), `SettingsView.swift` (3), `MapHeader.swift` (1)
- Modify: `project.yml:40-48` (delete `UIAppFonts`)
- Delete: `Slackwater/Resources/Fonts/*.ttf` (8 files)
- Test: `SlackwaterTests/TypeScaleTests.swift` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `MonoLabel(text:color:tracking:)` — the `size:` parameter is **removed**. Later tasks and all 29 existing call sites use the 3-parameter form.

#### The mapping table

Apply exactly this. Where two old sizes map to one style, that merge is intentional.

**`.fraunces(…)` — display and station names:**

| Old | New |
|---|---|
| `.fraunces(42)` | `.largeTitle` |
| `.fraunces(36, .semibold)` | `.largeTitle.weight(.semibold)` |
| `.fraunces(34)` | `.largeTitle` |
| `.fraunces(30, .medium)` | `.title.weight(.medium)` |
| `.fraunces(27, .semibold)` | `.title.weight(.semibold)` |
| `.fraunces(26, .semibold)` | `.title.weight(.semibold)` |
| `.fraunces(24, .semibold)` | `.title2.weight(.semibold)` |
| `.fraunces(23, .semibold)` | `.title2.weight(.semibold)` |
| `.fraunces(22)` | `.title2` |
| `.fraunces(20, .semibold)` | `.title3.weight(.semibold)` |
| `.fraunces(19)` | `.title3` |
| `.fraunces(19, .semibold)` | `.title3.weight(.semibold)` |
| `.fraunces(17)` | `.body` |
| `.fraunces(15)` | `.subheadline` |
| `.fraunces(15, .semibold)` | `.subheadline.weight(.semibold)` |
| `.fraunces(11, .semibold)` | `.caption2.weight(.semibold)` |
| `.fraunces(10, .semibold)` | `.caption2.weight(.semibold)` |

**`.geist(…)` — body sans:**

| Old | New |
|---|---|
| `.geist(17)` | `.body` |
| `.geist(17, .semibold)` | `.body.weight(.semibold)` |
| `.geist(16)` | `.callout` |
| `.geist(16, .medium)` | `.callout.weight(.medium)` |
| `.geist(15)` | `.subheadline` |
| `.geist(15, .medium)` | `.subheadline.weight(.medium)` |
| `.geist(15, .semibold)` | `.subheadline.weight(.semibold)` |
| `.geist(14)` | `.footnote` |
| `.geist(13)` | `.footnote` |
| `.geist(13, .semibold)` | `.footnote.weight(.semibold)` |
| `.geist(12)` | `.caption` |
| `.geist(12, .medium)` | `.caption.weight(.medium)` |
| `.geist(12, .semibold)` | `.caption.weight(.semibold)` |
| `.geist(11)` | `.caption2` |
| `.geist(10)` | `.caption2` |
| `.geist(9)` | `.caption2` |

**`.geistMono(…)` — mono labels:**

| Old | New |
|---|---|
| `.geistMono(14)` | `.footnote.monospaced()` |
| `.geistMono(12, .medium)` | `.caption.monospaced().weight(.medium)` |
| `.geistMono(11)` | `.caption2.monospaced()` |
| `.geistMono(11, .medium)` | `.caption2.monospaced().weight(.medium)` |
| `.geistMono(10, .medium)` | `.caption2.monospaced().weight(.medium)` |
| `.geistMono(9, .medium)` | `.caption2.monospaced().weight(.medium)` |
| `.geistMono(8)` | `.caption2.monospaced()` |

- [ ] **Step 1: Write the failing guard test**

Create `SlackwaterTests/TypeScaleTests.swift`. This mirrors `ColourAndFormTests.testNoSourceFileSpellsARetiredColour` — the same repo-walk shape, because that pattern already caught a retired token hiding in a file nobody thought to grep.

```swift
import XCTest
@testable import Slackwater

final class TypeScaleTests: XCTestCase {

    /// Repo-wide, not file-scoped, and deliberately so: the last time this
    /// project guarded a retired token one file at a time, the survivor was in
    /// the file nobody thought to check.
    func testNoSourceFileSpellsARetiredFont() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SlackwaterTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Slackwater")
        let retired = [".fraunces(", ".geist(", ".geistMono(",
                       "Fraunces-", "Geist-", "GeistMono-"]
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
            "could not walk \(root.path)")
        var scanned = 0
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            scanned += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in source.components(separatedBy: .newlines).enumerated() {
                for token in retired where line.contains(token) {
                    offenders.append("\(url.lastPathComponent):\(n + 1): \(token)")
                }
            }
        }
        // A scan that silently found no files would pass forever.
        XCTAssertGreaterThan(scanned, 10, "expected to scan the app's sources, walked \(scanned) files")
        XCTAssertTrue(offenders.isEmpty,
                      "retired font reference still in source:\n" + offenders.joined(separator: "\n"))
    }

    /// The bundled families must not come back via Info.plist either.
    func testNoBundledFontsDeclared() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let projectYml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertFalse(projectYml.contains("UIAppFonts"),
                       "UIAppFonts must be gone — bundled fonts are retired")
        XCTAssertFalse(projectYml.contains(".ttf"),
                       "no .ttf should be referenced from project.yml")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd /Users/clarkbw/src/sailingnaturali/slackwater-ios
xcodegen generate
./scripts/test.sh 2>&1 | tail -40
```

Expected: `testNoSourceFileSpellsARetiredFont` FAILS listing ~119 offenders; `testNoBundledFontsDeclared` FAILS on `UIAppFonts`. Every other test passes. If anything else fails, stop and report — the baseline is supposed to be green.

- [ ] **Step 3: Change `MonoLabel` to drop its size parameter**

In `Slackwater/Theme.swift`, replace lines 103–114:

```swift
/// The uppercase mono section-label role. Sizes 9/10/11 used to be passed per
/// call site; under Dynamic Type they all collapse to `.caption2` and scale
/// with the reader's setting instead.
struct MonoLabel: View {
    let text: String
    var color: Color = SN.leaf
    var tracking: CGFloat = 1.6
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.monospaced().weight(.medium))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}
```

- [ ] **Step 4: Delete the `Font` extension**

Delete `Slackwater/Theme.swift` lines 80–100 entirely (the `extension Font { … }` block).

- [ ] **Step 5: Fix the 13 `MonoLabel` call sites that pass `size:`**

```bash
grep -rn "MonoLabel(" Slackwater/ --include="*.swift" | grep "size:"
```

Remove the `size:` argument from each. Leave `color:` and `tracking:` alone. Example — `MapHeader.swift:68`:

```swift
// before
MonoLabel(text: region, size: 9, color: SN.foam.opacity(0.8), tracking: 1.5)
// after
MonoLabel(text: region, color: SN.foam.opacity(0.8), tracking: 1.5)
```

- [ ] **Step 6: Apply the mapping table to all 119 sites**

Work file by file, largest first. After each file:

```bash
grep -c "\.fraunces(\|\.geist(\|\.geistMono(" Slackwater/<file>.swift
```

should print `0`. Do not hand-tune any size — if a combination is not in the table, stop and report it rather than inventing a mapping.

- [ ] **Step 7: Delete the bundled fonts and their declaration**

```bash
git rm -r Slackwater/Resources/Fonts/
```

Then delete lines 40–48 of `project.yml` (the `UIAppFonts:` key and its eight entries). Keep the surrounding Info.plist keys intact.

The directory also holds `OFL-Fraunces.txt` and `OFL-Geist.txt`. Those go with the fonts — a licence file for a font you no longer ship is dead weight.

- [ ] **Step 7b: Remove the now-false font attribution**

Deleting the fonts makes a shipping sentence untrue. In `SettingsView.swift`:

```bash
grep -n "SIL Open Font License" Slackwater/SettingsView.swift
```

Delete that entire `Text(...)` line:

```swift
Text("Fonts: Fraunces, Geist and Geist Mono, used under the SIL Open Font License 1.1.")
```

Delete the line only — leave the surrounding attribution section and every other statement in it alone. No replacement text: the app now uses the system font, and Apple's system font carries no attribution requirement. This is the **only** user-visible copy change permitted in this plan.

Then confirm nothing else in the app still claims to use them:

```bash
grep -rn "Fraunces\|Geist" Slackwater/ --include="*.swift"
```

Comments describing the *prototype's* original design (e.g. `MapHeader.swift:61`, `Theme.swift:2`, `SlackwaterApp.swift:960`) are history, not claims — leave them. Only user-facing strings matter here.

- [ ] **Step 8: Regenerate and run the suite**

```bash
xcodegen generate
./scripts/test.sh 2>&1 | tail -40
```

Expected: everything passes, including both new tests. A build error naming a missing font symbol means a call site was missed — the grep in Step 6 finds it.

- [ ] **Step 9: Commit**

```bash
git add -A Slackwater project.yml SlackwaterTests/TypeScaleTests.swift
git commit -m "type: collapse 41 ad-hoc font sizes onto semantic Dynamic Type styles

119 call sites across 10 files. The three bundled families retire with
their .ttf files and UIAppFonts declaration. A repo-wide source guard
keeps them from coming back."
```

---

### Task 2: Monospaced digits on numeric readings

There are currently **zero** uses of `.monospacedDigit()` in the app. A column of readings whose glyph widths shift as the digits change is measurably harder to scan, and this app is mostly columns of readings.

**Files:**
- Modify: `Slackwater/SlackwaterApp.swift`, `CurrentDetailView.swift`, `TideDetailView.swift`, `DerivedGateDetailView.swift`, `ChsDetailView.swift`, `TimelineStrip.swift`, `MapHeader.swift`
- Test: `SlackwaterTests/TypeScaleTests.swift` (extend)

**Interfaces:**
- Consumes: the semantic styles from Task 1.
- Produces: nothing later tasks depend on.

**Which `Text` gets it:** any whose content is produced by `formatHeight`, `formatSpeed`, `formatNm`, `cardTime`, `dayLine`, or a bare interpolated number. **Not** station names, regions, phase words, or prose messages.

- [ ] **Step 1: Write the failing test**

Append to `SlackwaterTests/TypeScaleTests.swift`:

```swift
extension TypeScaleTests {
    /// Every formatter that produces a number feeds a Text that must not
    /// jitter as digits change. Asserted on source text because SwiftUI
    /// exposes no way to read a resolved Font back off a view.
    func testNumericFormattersAreMonospacedDigit() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Slackwater")
        let formatters = ["formatHeight(", "formatSpeed(", "formatNm(", "cardTime("]
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var checked = 0
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            let lines = source.components(separatedBy: .newlines)
            for (n, line) in lines.enumerated() where formatters.contains(where: line.contains) {
                guard line.contains("Text(") else { continue }
                checked += 1
                // The .font() modifier may sit on this line or the next few.
                let window = lines[n..<min(n + 4, lines.count)].joined(separator: "\n")
                if !window.contains("monospacedDigit()") {
                    offenders.append("\(url.lastPathComponent):\(n + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertGreaterThan(checked, 5, "expected to find numeric Text sites, found \(checked)")
        XCTAssertTrue(offenders.isEmpty,
                      "numeric reading without .monospacedDigit():\n" + offenders.joined(separator: "\n"))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
./scripts/test.sh 2>&1 | tail -40
```

Expected: FAILS listing every numeric `Text` site. Note the count — you need it in Step 4.

- [ ] **Step 3: Add `.monospacedDigit()` at each site the failure names**

It chains onto the existing font:

```swift
// before
Text(formatHeight(state.height, imperial: imperial)).font(.largeTitle)
// after
Text(formatHeight(state.height, imperial: imperial)).font(.largeTitle.monospacedDigit())
```

For the concatenated hero pair (value + unit), put it on the **value** only — the unit is letters:

```swift
(Text(formatHeight(state.height, imperial: imperial))
    .font(.largeTitle.monospacedDigit())
 + Text(" \(heightUnit(imperial: imperial))")
    .font(.body))
```

- [ ] **Step 4: Run the suite**

```bash
./scripts/test.sh 2>&1 | tail -40
```

Expected: all pass. If the guard still names a site, the `.font()` modifier is more than 4 lines below the `Text(` — move it closer rather than widening the test window.

- [ ] **Step 5: Commit**

```bash
git add Slackwater SlackwaterTests/TypeScaleTests.swift
git commit -m "type: monospaced digits on every numeric reading"
```

---

### Task 3: Extract the shared card shell

Four card layouts each hand-roll identical chrome: `.padding(.horizontal, 20)`, `.padding(.vertical, 16)`, `.frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)`, `SN.cardFill`, a 24pt continuous corner, and a `Color(hex: 0x001432, opacity: 0.24)` shadow. `StationCardView` and `CurrentCardView` go further and share the *whole* skeleton, differing in exactly three places.

This task is a **pure refactor: no visual change at any text size.** Task 4 needs one shell to put `ViewThatFits` in; applying it to four hand-rolled layouts would be four chances to get the shed order wrong.

**Files:**
- Create: `Slackwater/StationCard.swift`
- Modify: `Slackwater/SlackwaterApp.swift` — `StationCardView` (1063–1129), `ChsPendingCard` (1177–1228), `ChsGateCardView.fittedCard` (1267–…), `CurrentCardView` (1348–1440)
- Test: `SlackwaterTests/TypeScaleTests.swift` (extend)

**Interfaces:**
- Consumes: `StationGlyph(kind:tone:size:)`, `SN.cardFill`, `SN.foam`, `formatNm(_:)` — all existing.
- Produces:

```swift
struct StationCard<Trailing: View, Badge: View>: View {
    let glyphKind: StationGlyph.GlyphKind
    let glyphTone: StationGlyph.Tone
    let name: String
    let region: String
    var km: Double? = nil
    /// The next-extreme line, or a pending message. Nil renders nothing.
    var detail: String? = nil
    var opacity: Double = 1
    @ViewBuilder var badge: () -> Badge      // ProvisionalBadge, or EmptyView
    @ViewBuilder var trailing: () -> Trailing // reading block, pill, or EmptyView
}
```

- [ ] **Step 1: Write the failing test**

Append to `SlackwaterTests/TypeScaleTests.swift`:

```swift
extension TypeScaleTests {
    /// The chrome lived in four places and drifted. One shell owns it now;
    /// this fails if a variant grows its own copy back.
    func testCardChromeLivesInExactlyOnePlace() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Slackwater")
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var sites: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains("minHeight: 96") {
                sites.append("\(url.lastPathComponent):\(n + 1)")
            }
        }
        XCTAssertEqual(sites.count, 1, "card chrome must exist once, found: \(sites)")
        XCTAssertTrue(sites[0].hasPrefix("StationCard.swift:"),
                      "chrome must live in StationCard.swift, found \(sites[0])")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
./scripts/test.sh 2>&1 | tail -30
```

Expected: FAILS reporting 4 sites, all in `SlackwaterApp.swift`.

- [ ] **Step 3: Create the shell**

```swift
import SwiftUI

/// The one card shell. Four variants used to hand-roll this chrome; they
/// drifted, and Task 4's ViewThatFits needs a single place to live.
///
/// Slots, not subclasses: `badge` is the optional ProvisionalBadge beside the
/// region, `trailing` is the reading block (a big value, a phase pill, or
/// nothing at all for a pending card).
struct StationCard<Trailing: View, Badge: View>: View {
    let glyphKind: StationGlyph.GlyphKind
    let glyphTone: StationGlyph.Tone
    let name: String
    let region: String
    var km: Double? = nil
    var detail: String? = nil
    var opacity: Double = 1
    @ViewBuilder var badge: () -> Badge
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                StationGlyph(kind: glyphKind, tone: glyphTone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 7) {
                        badge()
                        Text(region)
                            .font(.footnote)
                            .foregroundStyle(SN.foam.opacity(0.78))
                    }
                    if let km {
                        Text(formatNm(km))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SN.foam.opacity(0.7))
                    }
                    if let detail {
                        Text(detail)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SN.foam.opacity(0.92))
                            .padding(.top, 10)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) { trailing() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(SN.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: 0x001432, opacity: 0.24), radius: 12, y: 10)
        .opacity(opacity)
    }
}

extension StationCard where Badge == EmptyView {
    init(glyphKind: StationGlyph.GlyphKind, glyphTone: StationGlyph.Tone,
         name: String, region: String, km: Double? = nil, detail: String? = nil,
         opacity: Double = 1, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(glyphKind: glyphKind, glyphTone: glyphTone, name: name, region: region,
                  km: km, detail: detail, opacity: opacity,
                  badge: { EmptyView() }, trailing: trailing)
    }
}
```

**Note the two deliberate changes carried in from Task 1's table:** the name is `.title2.weight(.semibold)` (was `.fraunces(23, .semibold)`) and carries **no** `lineLimit`/`minimumScaleFactor` — Task 4 depends on it being free to wrap. The `ChsPendingCard`'s message becomes the `detail` slot.

- [ ] **Step 4: Convert `StationCardView`**

Replace its `body` (`SlackwaterApp.swift:1079-1128`) with:

```swift
    var body: some View {
        StationCard(glyphKind: .tide, glyphTone: Self.glyphTone(state),
                    name: record.name, region: record.region, km: km,
                    detail: state?.next.map { next in
                        "\(next.kind == .high ? "High" : "Low") \(formatHeight(next.height, imperial: imperial)) \(heightUnit(imperial: imperial)) · \(cardTime(next.time, record.tz))"
                    }) {
            if let state {
                (Text(formatHeight(state.height, imperial: imperial))
                    .font(.largeTitle.monospacedDigit())
                 + Text(" \(heightUnit(imperial: imperial))")
                    .font(.body))
                    .foregroundStyle(.white)
                HStack(spacing: 4) {
                    Text(state.rising ? "▲" : "▼").font(.caption2)
                    Text(state.rising ? "Rising" : "Falling").font(.caption2)
                }
                .foregroundStyle(SN.foam.opacity(0.9))
            }
        }
        .task { if state == nil { state = record.cardState(at: appNow()) } }
    }
```

- [ ] **Step 5: Convert `CurrentCardView`**

Replace its `body` (`SlackwaterApp.swift:1378-1440`) with:

```swift
    var body: some View {
        StationCard(glyphKind: .current, glyphTone: Self.glyphTone(state),
                    name: record.name, region: record.region, km: km,
                    detail: state?.next.map { nextLine($0) },
                    badge: { if provisional != nil { ProvisionalBadge() } }) {
            if let state {
                let phase = currentPhase(signed: state.signed)
                if phase == .slack {
                    // SN.go, not a neutral chip — see the matching
                    // comment on ChsGateCardView's phase pill.
                    Text("SLACK")
                        .font(.caption2.monospaced().weight(.medium)).tracking(1)
                        .foregroundStyle(SN.navyDeep)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(SN.go, in: Capsule())
                } else {
                    (Text(tilde + formatSpeed(abs(state.signed), unit: speedUnit))
                        .font(.largeTitle.monospacedDigit())
                     + Text(" \(speedUnitLabel(speedUnit))")
                        .font(.body))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        CompassArrow(deg: record.setDegrees(signed: state.signed)).font(.caption2)
                        Text(phaseWord(phase)).font(.caption2)
                    }
                    .foregroundStyle(SN.foam.opacity(0.9))
                }
            }
        }
        .task { if state == nil { state = record.cardState(at: appNow()) } }
    }
```

`badge:` needs a `@ViewBuilder` closure that may produce nothing — the `if` with no `else` is valid inside one.

- [ ] **Step 6: Convert `ChsPendingCard`**

Replace its `body` (`SlackwaterApp.swift:1189-1227`) with:

```swift
    var body: some View {
        StationCard(glyphKind: kind, glyphTone: .unknown,
                    name: name, region: region, km: km,
                    detail: message,
                    opacity: 0.82,  // visibly quieter than a station with numbers
                    trailing: { EmptyView() })
            // Named per station (M53). "Some card on screen says 'Canadian tidal
            // predictions'" was a unique locator at 21 Canadian stations and is
            // meaningless at 1,097 — every undownloaded station says it, so a test
            // waiting for THIS station's copy to go never sees it go.
            .accessibilityIdentifier("chs-pending-\(id)")
    }
```

- [ ] **Step 7: Convert `ChsGateCardView.fittedCard`**

Read the existing `fittedCard` body (from `SlackwaterApp.swift:1267`) and convert it the same way: `glyphKind: .current`, `glyphTone: Self.glyphTone(state?.phase)`, the gate's name and region, its "Slack · time" string as `detail`, and its phase pill as the `trailing` slot. Keep the pill's existing colours and copy exactly — this is a refactor, not a redesign.

- [ ] **Step 8: Run the suite**

```bash
xcodegen generate
./scripts/test.sh 2>&1 | tail -40
```

Expected: all pass, including `testCardChromeLivesInExactlyOnePlace`. `ChsQueueTests` and `ChsCurrentGateTests` exercise the pending cards by accessibility identifier — if they fail, the identifier moved.

- [ ] **Step 9: Commit**

```bash
git add Slackwater SlackwaterTests/TypeScaleTests.swift
git commit -m "refactor: one card shell instead of four copies of the chrome

Pure refactor, no visual change. Task 4 needs a single place to put
ViewThatFits; four hand-rolled layouts would be four chances to get the
shed order wrong."
```

---

### Task 4: Three tiers, chosen by measured fit

At accessibility sizes there is no horizontal room for identity-left and state-right. Names truncate from `AccessibilityL`, "Falling" hyphenates to "Fall-/ing", and on iPad a single card fills the whole sidebar. `ViewThatFits` measures available space, so it answers **width as well as type size** — which matters because the iPad's ~320pt sidebar truncates names *at default text size* today, and a `dynamicTypeSize` threshold would never catch that.

**Files:**
- Modify: `Slackwater/StationCard.swift`
- Modify: `Slackwater/SlackwaterApp.swift:1006` and `Slackwater/MapHeader.swift:67` (remove `minimumScaleFactor`)
- Test: `SlackwaterTests/TypeScaleTests.swift` (extend)

**Interfaces:**
- Consumes: `StationCard` from Task 3.
- Produces: `CardTier` (`.full`, `.reduced`, `.essential`) with `CardTier.fields -> [CardField]`, and `StationCard.content(for: CardTier)`. `CardTier` and `CardField` are **top-level** types, not nested in `StationCard` — nesting them inside a generic would force every assertion to spell `StationCard<EmptyView, EmptyView>.Tier`, and the tiers have nothing to do with the shell's generic parameters.

**The tiers and the shed order:**

| Tier | Shows |
|---|---|
| **Full** | glyph · name · region · distance · detail · trailing |
| **Reduced** | glyph · name · region · trailing |
| **Essential** | glyph · name · trailing |

Distance and the detail line go **together**, at the single Full→Reduced step. Distance goes because the list's own grouping already answers "which of these is near me"; the detail line goes because "when" is the detail view's entire job, one tap away. **Region never sheds** — it is the only thing separating "Victoria" from "Victoria Harbour" from "Victoria Inner Harbour", and for two identically-named stations it is the *only* differentiator there is.

*Corrected twice during Task 4, both times by evidence rather than argument:*

1. An earlier wording claimed distance sheds "first" and the detail line "second". No tier had one without the other, so the precedence was never implemented.
2. The tier table originally had a third **Essential** tier dropping region. It was self-contradictory — its own doc comment called region "load-bearing at every size" — and it broke two things at once: `ProvisionalBadge` (which sits beside region) vanished at accessibility sizes, and `testM50MatchingStationChooser` failed on the iPad sidebar at *default* text size, because that test's two "Discovery Island" stations are told apart solely by their region strings (`"3.0 nm NE"` / `"6.6 nm SSE"` — NOAA formats a subordinate current station's region as a bearing). Essential is deleted; region, name, glyph and the reading are unconditional.

Note for anyone reading the fix history: the first diagnosis of that failure was that the tiers shed *distance*, misled by region strings that look like distances. `formatNm` never appends a compass point and would have read `"0.0 nm"` for that test's coordinate. Confirm which field produces an asserted string before theorising about the design.

- [ ] **Step 1: Write the failing test**

```swift
extension TypeScaleTests {
    /// ViewThatFits gives no supported way to ask which candidate it chose, so
    /// the split is: unit-test what each tier CONTAINS, screenshot which one
    /// gets PICKED. Do not try to unit-test the picker — that road ends in a
    /// weakened test, which is how this project's colour guard went wrong four
    /// times before it was restructured.
    func testTiersShedInTheSpecifiedOrder() {
        XCTAssertEqual(CardTier.full.fields,
                       [.glyph, .name, .region, .distance, .detail, .trailing])
        XCTAssertEqual(CardTier.reduced.fields,
                       [.glyph, .name, .region, .trailing])
        XCTAssertEqual(CardTier.essential.fields,
                       [.glyph, .name, .trailing])
    }

    /// The two properties the shed order has to keep, stated as tests so a
    /// future reorder has to argue with them.
    func testEveryTierKeepsNameAndTrailing() {
        for tier in CardTier.allCases {
            XCTAssertTrue(tier.fields.contains(.name), "\(tier) dropped the name")
            XCTAssertTrue(tier.fields.contains(.trailing), "\(tier) dropped the reading")
        }
    }

    func testRegionOutlivesDistanceAndDetail() {
        let reduced = CardTier.reduced.fields
        XCTAssertTrue(reduced.contains(.region), "region must survive into reduced")
        XCTAssertFalse(reduced.contains(.distance), "distance sheds before region")
        XCTAssertFalse(reduced.contains(.detail), "detail sheds before region")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
./scripts/test.sh 2>&1 | tail -30
```

Expected: compile error — `Tier` does not exist.

- [ ] **Step 3: Add the tier model to `StationCard.swift`**

Top-level types, not nested in the generic `StationCard`:

```swift
enum CardField { case glyph, name, region, distance, detail, trailing }

/// Shed order: distance, then detail, then nothing more — region and the
/// reading are load-bearing at every size. Asserted in TypeScaleTests.
///
/// Distance goes first because the list's own grouping already answers "which
/// of these is near me". The detail line goes second because "when" is the
/// detail view's whole job, one tap away. Region survives longest because it
/// is the only thing separating "Victoria" from "Victoria Harbour" from
/// "Victoria Inner Harbour" — a truncated ambiguous name is worse than a
/// missing one.
enum CardTier: CaseIterable {
    case full, reduced, essential

    var fields: [CardField] {
        switch self {
        case .full:      [.glyph, .name, .region, .distance, .detail, .trailing]
        case .reduced:   [.glyph, .name, .region, .trailing]
        case .essential: [.glyph, .name, .trailing]
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
./scripts/test.sh 2>&1 | tail -30
```

Expected: the three new tests pass.

- [ ] **Step 5: Make the body render a tier, then wrap it in `ViewThatFits`**

Replace `StationCard`'s `body` with a tier-parameterised builder plus the selector:

```swift
    @ViewBuilder
    func content(for tier: CardTier) -> some View {
        let fields = tier.fields
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                StationGlyph(kind: glyphKind, tone: glyphTone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    if fields.contains(.region) {
                        HStack(spacing: 7) {
                            badge()
                            Text(region)
                                .font(.footnote)
                                .foregroundStyle(SN.foam.opacity(0.78))
                        }
                    }
                    if fields.contains(.distance), let km {
                        Text(formatNm(km))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SN.foam.opacity(0.7))
                    }
                    if fields.contains(.detail), let detail {
                        Text(detail)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SN.foam.opacity(0.92))
                            .padding(.top, 10)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) { trailing() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(SN.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: 0x001432, opacity: 0.24), radius: 12, y: 10)
        .opacity(opacity)
    }

    var body: some View {
        // Which candidate wins is verified by screenshot (Task 6), not by unit
        // test — ViewThatFits exposes no way to ask. The tiers' CONTENTS are
        // unit-tested in TypeScaleTests.
        ViewThatFits(in: .horizontal) {
            content(for: .full)
            content(for: .reduced)
            content(for: .essential)
        }
    }
```

- [ ] **Step 6: Remove the two remaining `minimumScaleFactor` sites**

`SlackwaterApp.swift:1006` (map tile station name) and `MapHeader.swift:67` (map header station name): delete the `.minimumScaleFactor(…)` line and the `.lineLimit(1)` directly above it, so the name wraps.

**Do not touch `SlackwaterApp.swift:658`.** That is the wordmark, and the comment above it records why it must never wrap: in the 320pt iPad sidebar it shares a row with two 34pt buttons and would break as "Slackwat/er". It is a fixed-width constraint with no reflow available — the one case where shrinking beats wrapping.

- [ ] **Step 7: Add the wordmark guard**

```swift
extension TypeScaleTests {
    /// The wordmark's minimumScaleFactor is load-bearing: it shares the 320pt
    /// iPad sidebar row with two 34pt buttons and would break as "Slackwat/er".
    /// Every other name wraps instead of shrinking. This fails in both
    /// directions — a blanket removal, or a fresh one creeping back in.
    func testOnlyTheWordmarkShrinks() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Slackwater")
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var sites: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains("minimumScaleFactor") {
                sites.append("\(url.lastPathComponent):\(n + 1)")
            }
        }
        XCTAssertEqual(sites.count, 1,
                       "exactly one minimumScaleFactor should remain (the wordmark), found: \(sites)")
        XCTAssertTrue(sites[0].hasPrefix("SlackwaterApp.swift:"),
                      "the survivor must be the wordmark, found \(sites[0])")
    }
}
```

- [ ] **Step 8: Run the suite**

```bash
./scripts/test.sh 2>&1 | tail -40
```

Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add Slackwater SlackwaterTests/TypeScaleTests.swift
git commit -m "type: card sheds facts by measured fit, not by a size threshold

ViewThatFits responds to width as well as type size, which also fixes the
iPad sidebar truncating names at DEFAULT text size. Shed order: distance,
then the next-extreme line; region and the reading survive everywhere."
```

---

### Task 5: Scale what sits beside the text

Three things stay frozen while the type grows, and each one breaks the layout in its own way.

**Files:**
- Modify: `Slackwater/StationCard.swift` (glyph), `Slackwater/SlackwaterApp.swift:335` (FAB spacer), `Slackwater/SlackwaterApp.swift:993` (map tile glyph)
- Test: `SlackwaterTests/TypeScaleTests.swift` (extend)

**Interfaces:**
- Consumes: `StationCard` from Tasks 3–4, `StationGlyph(kind:tone:size:)`.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing test**

```swift
extension TypeScaleTests {
    /// Anything sized in points beside scaling text has to scale too, or it
    /// becomes a 24pt mark next to 40pt type. @ScaledMetric is the sanctioned
    /// exception to "no literal sizes" — it scales a non-text dimension.
    func testGlyphAndFabClearanceScale() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Slackwater")
        let card = try String(contentsOf: root.appendingPathComponent("StationCard.swift"), encoding: .utf8)
        XCTAssertTrue(card.contains("@ScaledMetric"),
                      "the glyph must scale with the text it sits beside")
        let app = try String(contentsOf: root.appendingPathComponent("SlackwaterApp.swift"), encoding: .utf8)
        XCTAssertFalse(app.contains("Color.clear.frame(height: 96)"),
                       "the FAB clearance must scale, or the last card hides under the buttons")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
./scripts/test.sh 2>&1 | tail -30
```

Expected: both assertions fail.

- [ ] **Step 3: Scale the glyph**

In `StationCard.swift`, add the property and use it:

```swift
    /// Grows with the text it sits beside. Frozen, a 24pt mark next to 40pt
    /// type reads as a bullet rather than a station kind.
    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 24
```

and in `content(for:)`:

```swift
                StationGlyph(kind: glyphKind, tone: glyphTone, size: glyphSize)
```

- [ ] **Step 4: Scale the FAB clearance**

`SlackwaterApp.swift:335` is `Color.clear.frame(height: 96)  // scroll clear of the FABs`. The list must scroll clear of the floating buttons at every type size, or the last card sits under them however well the card itself reflows.

Add to the enclosing view:

```swift
    /// The FABs don't grow, but the row heights do — without this the last
    /// card ends up under them at large sizes. List-level, not card-level.
    @ScaledMetric(relativeTo: .body) private var fabClearance: CGFloat = 96
```

and replace the line with:

```swift
                        Color.clear.frame(height: fabClearance)  // scroll clear of the FABs
```

- [ ] **Step 5: Scale the map tile's glyph**

`SlackwaterApp.swift:993` is `StationGlyph(kind: glyphKind, tone: glyphTone, size: 26)`. Add to that view:

```swift
    @ScaledMetric(relativeTo: .callout) private var tileGlyphSize: CGFloat = 26
```

and use `size: tileGlyphSize`.

- [ ] **Step 5b: Scale the SF Symbols that sit inline with text**

Eighteen `Image(systemName:).font(.system(size: N, …))` sites survive Task 1 — correctly, since they are icons rather than text. Nine of them sit **inline with text** and look absurd frozen at 10–21pt beside type that has grown to 40pt. SF Symbols take a semantic style directly, which is simpler than `@ScaledMetric` and scales them exactly like the text they sit beside.

Convert these nine, matching each icon to the style of the text it accompanies:

| Site | Icon | New |
|---|---|---|
| `SettingsView.swift:53` | `chevron.right` | `.footnote.weight(.semibold)` |
| `ChsDetailView.swift:214` | `chevron.right` | `.footnote.weight(.semibold)` |
| `SlackwaterApp.swift:634` | `chevron.right` | `.footnote.weight(.semibold)` |
| `ChsDetailView.swift:187` | `exclamationmark.triangle.fill` | `.title3` |
| `SlackwaterApp.swift:617` | `location.slash` | `.title3` |
| `SlackwaterApp.swift:542` | `arrow.triangle.branch` | `.caption2.weight(.semibold)` |
| `SlackwaterApp.swift:837` | `location.north.fill` | `.caption2` |
| `Theme.swift:253` | `exclamationmark.triangle.fill` | `.caption2.weight(.semibold)` |
| ~~`OfflineDownloads.swift:83`~~ | ~~row icon~~ | **WRONG — do not convert** |

Line numbers drift — find each by its `Image(systemName:)` name in that file.

**Correction, found by Task 5's sweep: `OfflineDownloads.swift`'s row icon was wrongly on this list.**
It sits in a fixed 34×34 button — one of the very "two 34pt buttons" that `SlackwaterApp.swift:658`'s
wordmark comment is calibrated against — so it belongs with the chrome that stays fixed, alongside
the gear button right next to it, which this table correctly left alone. It was converted and then
reverted to `.font(.system(size: 13, weight: .medium))`. **Eight conversions, not nine.**

**The general rule this table was groping at:** an icon scales when it sits *beside* text and has
room to grow; it stays fixed when it sits *inside* a fixed container — a hit target, a disc, a slot.
Task 5's sweep turned this into a check anyone can rerun: for every `Image(systemName:)` with a
scaling font, measure `UIFont.preferredFont` at the largest category against whatever fixed dimension
must contain or clear it. Three more containers failed that check and now scale with `@ScaledMetric`
(`ChsAmberCard`'s and `unavailableCard`'s 46×46 discs, `RecentRowLabel`'s 38×38 glyph slot), and
`ProvisionalBadge`'s 22×22 disc failed it in the round before.

**Leave the other nine fixed, deliberately.** `MapHeader.swift:52, 87, 109` (back, star, return), `SlackwaterApp.swift:669, 705, 809, 896` (gear, FAB, two closes) and the two 40pt empty-state illustrations (`SlackwaterApp.swift:85, 308`) are chrome in fixed-size hit targets, not text companions. Growing them is what breaks the 320pt iPad sidebar row that `SlackwaterApp.swift:658`'s wordmark comment already warns about — the same row, the same 34pt buttons. Add a brief comment at the `MapHeader` cluster recording that the fixed size is intentional, so a later reader does not "finish the job".

- [ ] **Step 6: Run the suite**

```bash
./scripts/test.sh 2>&1 | tail -40
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Slackwater SlackwaterTests/TypeScaleTests.swift
git commit -m "type: scale the glyph, the FAB clearance, and inline SF Symbols"
```

---

### Task 6: Verify across the size range on both devices

The unit tests cover what each tier contains. They cannot cover which tier gets picked, whether anything clips, or whether the result is readable — that is what this task is for.

**Files:**
- Create: `docs/superpowers/notes/2026-08-02-dynamic-type-verification.md`
- Modify: whatever the screenshots expose

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: the verification note and any fixes.

**The trap, recorded because the spike hit it:** an invalid content-size-category launch argument makes UIKit **silently fall back to the default** with no error. Two screenshots at supposedly different sizes come out byte-identical, and nothing warns you. `UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge` is **not** a real category — the accessibility ones are `UICTContentSizeCategoryAccessibilityM/L/XL/XXL/XXXL`. Verify every string against `UIContentSizeCategory` before trusting a single shot.

- [ ] **Step 1: Create your own devices — never drive the suite's**

`iPhone 17` and `iPad Pro 11-inch (M5)` are the two devices `./scripts/test.sh` drives. Driving one while a suite runs collides with it: a reviewer's screenshot session on `iPhone 17` mid-run produced **nine spurious UI-test failures** that cost a full cycle to diagnose. This is the same class of contention that PR #17 fixed for CI-versus-local.

Create your own, use only those, delete them when done:

```bash
PHONE=$(xcrun simctl create sw-verify-phone "iPhone 17")
PAD=$(xcrun simctl create sw-verify-pad "iPad Pro 11-inch (M5)")
```

Building against the shared destinations is fine — it is driving the device that collides.

- [ ] **Step 2: Capture the matrix**

**Six** categories × two devices. Note `extra-small` is included deliberately: `@ScaledMetric` scales in *both* directions, and Task 5 shipped a bug where a scaling spacer dropped below fixed chrome at small sizes. That direction is the one nobody thinks to check, because Dynamic Type is reflexively tested by making text bigger.

Prefer `simctl ui <device> content_size`, whose category names you can enumerate with `simctl help ui`:

```bash
for SIZE in extra-small small large extra-extra-large \
            accessibility-large accessibility-extra-extra-extra-large; do
  xcrun simctl ui "$PHONE" content_size "$SIZE"
  xcrun simctl ui "$PHONE" content_size          # read it BACK — see the trap below
  # relaunch the app, then:
  xcrun simctl io "$PHONE" screenshot "/tmp/b2-shots/phone-$SIZE.png"
done
```

Repeat for `$PAD`, including the split-view sidebar at ~320pt — that width selects a different tier than full-screen at the *same* text size, which is the whole reason the card adapts by measured fit rather than by a type-size threshold.

Capture at minimum: the station list (both a tide and a current card), a pending CHS card, the search overlay with a query typed, the first-run gate button, and a detail view.

- [ ] **Step 3: Prove the shots differ**

```bash
md5 /tmp/b2-shots/*.png | sort
```

Any two matching hashes across *different* size settings means the override did not take. Do not proceed on a matrix you have not proved is real — this trap has already cost this project once.

- [ ] **Step 4: Read every shot against this checklist**

**The dominant defect of this branch — check for it first.** Content taught to scale inside a container that stayed fixed has been found **six** times across four files (`ProvisionalBadge`'s 22×22 disc, two 46×46 icon tiles, a 38×38 glyph slot, the gate button's 54pt capsule, the search field's 48pt capsule). Each was found by a different method and none by a test. Look for anything that has outgrown its own background shape, disc, pill or hit target.

It fails in two distinguishable ways, and one is silent:

| Content | Given a too-small container | Symptom |
|---|---|---|
| `Text` | accepts the proposal, **truncates** | words missing, often an ellipsis — easy to miss |
| `Image` / `TextField` | ignores it, **overflows** | glyph or caret crossing the shape's edge |

So do not only look for things spilling out. Read the *words* too: a button that says "Use My…" instead of "Use My Location" looks tidy and is broken.

Then, for each shot: does every name wrap rather than truncate? Is the glyph proportionate to the text beside it? Is the last card clear of the FABs — **at `extra-small` as well as the large sizes**? Does the tier that got picked look like the right call for that width and size, and does the ~320pt iPad sidebar pick a different one than full-screen at the same text size?

**Measure, do not eyeball.** Two rounds of this task were closed on confident visual impressions that pixel measurement later disproved — once claiming a capsule grew when its bounding box was byte-identical at both sizes. Where a judgement is close, crop and measure the bounding box, or read the element frame directly.

- [ ] **Step 5: Write the verification note**

Create `docs/superpowers/notes/2026-08-02-dynamic-type-verification.md` recording: the matrix captured, which tier each cell selected, anything that looked wrong, and what was changed in response. Embed nothing — reference the paths.

- [ ] **Step 6: Fix what the shots exposed, then re-run**

```bash
./scripts/test.sh 2>&1 | tail -40
```

- [ ] **Step 7: Delete your devices, then commit**

```bash
xcrun simctl delete "$PHONE" "$PAD"
```


```bash
git add docs/superpowers/notes/2026-08-02-dynamic-type-verification.md Slackwater
git commit -m "verify: Dynamic Type across five sizes on both devices"
```

---

## Self-Review

**Spec coverage.** §1 Type → Task 1 (mapping table, retirement, guard) and Task 2 (`.monospacedDigit()`). §2 adapts-by-fit → Task 4, with the shell prerequisite the spec's amendment identified handled in Task 3. §3 three tiers and shed order → Task 4 Steps 1–5. §4's three details → Task 5 (glyph, FAB clearance) and Task 4 Step 6 (`minimumScaleFactor`). §5 testing split → the comment in Task 4 Step 1 and the `body` comment in Step 5. §5's launch-argument trap → Task 6's preamble and Step 2. §6 out-of-scope items are absent, as intended.

**Placeholders.** Task 3 Step 7 is the one step that says "read the existing body and convert it the same way" rather than quoting the result — the `fittedCard` body runs past the region I read, so quoting it would mean inventing code. It is bounded by an explicit field mapping and by the fact that Steps 4–6 demonstrate the identical transformation three times.

**Type consistency.** `StationCard`'s generic parameters, `Field`, `Tier`, `Tier.fields`, and `content(for:)` are spelled the same in Tasks 3, 4, 5 and in every test. `MonoLabel`'s 3-parameter form introduced in Task 1 is used nowhere later with a `size:`.

**One risk worth naming.** `ViewThatFits(in: .horizontal)` inside a `List` row can measure against an unbounded proposed width, in which case the full tier always wins and the tiers never engage. If Task 6's shots show no tier change at any size, that is the cause — the fix is to constrain the candidates' width, not to switch to a `dynamicTypeSize` threshold, which would give up the iPad-sidebar fix that motivated measured fit in the first place.
