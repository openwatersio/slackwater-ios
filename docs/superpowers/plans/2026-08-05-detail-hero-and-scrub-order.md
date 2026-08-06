# Detail Hero Crop & Scrub Order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shrink the detail-view map hero to ~⅓, convert all floating chrome to Liquid Glass, lead the scrub card with the water reading, and move date/time/moon to the bottom of the card — per `docs/superpowers/specs/2026-08-03-detail-hero-and-scrub-order-design.md`.

**Architecture:** `MapHeader` loses its fixed 420pt frame (intrinsic: title pill + margins), its opaque chrome backings, its station pin, and its return-to-now overlay. A new shared `ScrubWhen` row replaces the three identical date/time/moon blocks and moves to the bottom of each scrub card. Return-to-now moves into each card's primary readout row. Two search FABs in `SlackwaterApp.swift` convert to glass in the same pass.

**Tech Stack:** SwiftUI on iOS 26 (`.glassEffect`, `GlassEffectContainer`), XcodeGen, XCTest. `.xcodeproj` is generated — `scripts/test.sh` runs `xcodegen generate` itself; never edit the project file.

## Global Constraints

- Deployment target: iOS 26.0 (`project.yml`, already committed on this branch as `eef66a4`). No `#available` fences anywhere — the floor is the fence.
- Branch: `detail/hero-crop-and-scrub-order`. Never commit to `main`; PR at the end, do not merge it (CONTRIBUTING.md).
- Glass is chrome-only: content cards keep flat `SN.cardFill`. Nothing else converts.
- No `.ultraThinMaterial` remains anywhere in `Slackwater/` when done (Task 2's test makes this executable).
- The hero's 44pt hit targets stay fixed-size — the comment at `MapHeader.swift:50-55` explains why; keep it.
- Run tests with `./scripts/test.sh` (fast plan; it holds the machine-wide lock, regenerates the project, runs both reference simulators).
- Every commit message ends with the Co-Authored-By + Claude-Session trailer used by the two commits already on this branch.

---

### Task 1: The iOS 26 floor builds and passes

The `project.yml` bump is committed but nothing has built against it. Prove the floor is safe before stacking layout work on it.

**Files:**
- None (verification only; `xcodegen generate` output is not checked in)

**Interfaces:**
- Produces: a green baseline every later task diffs against.

- [ ] **Step 1: Regenerate and run the fast plan**

Run: `./scripts/test.sh`

Expected: all unit + fast UI tests pass on both reference simulators. If another run holds `/tmp/slackwater-test.lock`, it waits — that is normal.

- [ ] **Step 2: No commit**

Nothing changed on disk. If anything failed, stop and report — the floor bump has a problem the spec didn't anticipate, and that's a conversation, not a workaround.

---

### Task 2: Chrome becomes glass (hero + search FABs), with the executable rule

Every piece of floating chrome stacks `.ultraThinMaterial` plus an opaque navy tint plus a hand-rolled stroke. All of it becomes one `.glassEffect` call. The test is a repo-scan in the style of `TypeScaleTests.testNoSourceFileSpellsARetiredFont` — the rule "chrome is glass, not a material imitation," executable.

**Files:**
- Create: `SlackwaterTests/HeroChromeTests.swift`
- Modify: `Slackwater/MapHeader.swift:57-99` (back button, title pill, star), `:110-126` (return-to-now)
- Modify: `Slackwater/SlackwaterApp.swift:758-770` (fab), `:870-880` (close-search)

**Interfaces:**
- Consumes: nothing new.
- Produces: the glass idiom later tasks copy — `.glassEffect(.regular.interactive(), in: Circle())` for buttons, `.glassEffect(.regular, in:)` for passive surfaces.

- [ ] **Step 1: Write the failing test**

```swift
// SlackwaterTests/HeroChromeTests.swift
import XCTest
@testable import Slackwater

/// The hero-crop spec's material rule, executable: floating chrome is Liquid
/// Glass. A material-plus-tint imitation must not come back — repo-wide, like
/// the retired-font scan, because the survivor is always in the file nobody
/// thought to check.
final class HeroChromeTests: XCTestCase {

    private func appSources() throws -> [(name: String, source: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SlackwaterTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Slackwater")
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

    func testNoMaterialImitationOfGlass() throws {
        var offenders: [String] = []
        for (name, source) in try appSources() {
            for (n, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains(".ultraThinMaterial") {
                offenders.append("\(name):\(n + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "chrome must use .glassEffect, not material imitation:\n"
                      + offenders.joined(separator: "\n"))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/test.sh`

Expected: `testNoMaterialImitationOfGlass` FAILS listing 6 offenders — `MapHeader.swift` ×4, `SlackwaterApp.swift` ×2. Everything else stays green.

- [ ] **Step 3: Convert the hero chrome**

In `Slackwater/MapHeader.swift`, wrap the chrome `HStack` (line 56) in a `GlassEffectContainer` so adjacent glass blends instead of double-refracting where the pill nears a button:

```swift
GlassEffectContainer {
    HStack(alignment: .top) {
        // ... back / pill / star exactly as they are, with the
        // background changes below ...
    }
}
.padding(.horizontal, 16)
.padding(.top, 62)  // clears the status bar; header ignores the top safe area
```

(The `.padding` calls move from the `HStack` to the container — same geometry.)

Back button (`:62-63`) — replace both `.background` lines with:

```swift
.glassEffect(.regular.interactive(), in: Circle())
```

Title pill (`:77-82`) — replace both `.background` lines AND delete the `.overlay(RoundedRectangle...strokeBorder...)`:

```swift
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
```

Star button (`:95-96`) — replace both `.background` lines with:

```swift
.glassEffect(.regular.interactive(), in: Circle())
```

Return-to-now (`:117-119`) — replace both `.background` lines AND delete its `.overlay(Circle().strokeBorder...)`:

```swift
.glassEffect(.regular.interactive(), in: Circle())
```

(Return-to-now still lives in the hero in this task; Task 4 moves it.)

- [ ] **Step 4: Convert the two FABs**

In `Slackwater/SlackwaterApp.swift`, `fab(_:label:action:)` (`:758`) — replace the two `.background` lines and the `.overlay(Circle().strokeBorder...)` with:

```swift
.glassEffect(.regular.interactive(), in: Circle())
```

Keep the `.shadow` line: it is depth over content, not an edge treatment, and glass does not supply it.

Close-search button (`:877-879`) — same three-line replacement:

```swift
.glassEffect(.regular.interactive(), in: Circle())
```

- [ ] **Step 5: Run tests to verify green**

Run: `./scripts/test.sh`

Expected: PASS, including the new scan and the existing `ScreenshotTests` (they tap `Search` / `Close search` by accessibility label, which the conversion must not change).

- [ ] **Step 6: Commit**

```bash
git add SlackwaterTests/HeroChromeTests.swift Slackwater/MapHeader.swift Slackwater/SlackwaterApp.swift
git commit -m "glass: floating chrome rides .glassEffect, the navy imitation layer goes"
```

---

### Task 3: `ScrubWhen` — one when-row, plus the day-offset function

The three scrub cards each open with an identical date/time/moon block and each compute `dayOffset` identically. Extract both. This task only *creates* the shared pieces and their test; the cards adopt them in Tasks 4–5.

**Files:**
- Modify: `Slackwater/Theme.swift` (append near `MoonGlyph`, `:199`)
- Create: `SlackwaterTests/ScrubWhenTests.swift`

**Interfaces:**
- Consumes: `relativeDayLabel(_:_:_:)` (`TimelineStrip.swift:429`), `dayLine`, `cardTime`, `MonoLabel`, `MoonGlyph`, `SunMoon.moonIllumination` — all existing.
- Produces:
  - `func scrubDayOffset(_ scrub: Date, from live: Date, _ tz: TimeZone) -> Int`
  - `struct ScrubWhen: View { init(scrubTime: Date, live: Date, tz: TimeZone) }`

- [ ] **Step 1: Write the failing test**

```swift
// SlackwaterTests/ScrubWhenTests.swift
import XCTest
@testable import Slackwater

final class ScrubWhenTests: XCTestCase {

    private let vancouver = TimeZone(identifier: "America/Vancouver")!

    /// Local-midnight day boundaries, not 24h intervals: 23:30 → 00:00+30m is
    /// "tomorrow" even though only half an hour passed.
    func testDayOffsetCrossesLocalMidnightNotDayLengths() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = vancouver
        let live = cal.date(from: DateComponents(year: 2026, month: 8, day: 3,
                                                 hour: 23, minute: 30))!
        XCTAssertEqual(scrubDayOffset(live, from: live, vancouver), 0)
        XCTAssertEqual(scrubDayOffset(live.addingTimeInterval(3600), from: live, vancouver), 1,
                       "30 min after midnight is tomorrow")
        XCTAssertEqual(scrubDayOffset(live.addingTimeInterval(-48 * 3600), from: live, vancouver), -2)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/test.sh`

Expected: FAIL to compile — `scrubDayOffset` not defined.

- [ ] **Step 3: Implement in `Theme.swift`**

Append after `MoonGlyph` (`Theme.swift:199`'s struct):

```swift
/// Whole local days between the live "today" and the scrubbed day — the shared
/// definition behind every card's TODAY / TOMORROW / +N label.
func scrubDayOffset(_ scrub: Date, from live: Date, _ tz: TimeZone) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.dateComponents([.day], from: cal.startOfDay(for: live),
                              to: cal.startOfDay(for: scrub)).day ?? 0
}

/// The *when* of a scrub reading — relative day, clock time, moon for that
/// day. The LAST row of every scrub card: it is the calendar of the reading,
/// secondary to what the water is doing (2026-08-03 hero-crop spec §3).
struct ScrubWhen: View {
    let scrubTime: Date
    let live: Date
    let tz: TimeZone

    var body: some View {
        let moon = SunMoon.moonIllumination(date: scrubTime)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            MonoLabel(text: "\(relativeDayLabel(scrubDayOffset(scrubTime, from: live, tz), scrubTime, tz)) · \(dayLine(scrubTime, tz))")
            Text(cardTime(scrubTime, tz))
                .font(.title.weight(.medium).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Spacer()
            MoonGlyph(fraction: moon.fraction, waxing: moon.waxing, size: 22)
            Text(SunMoon.phaseName(phase: moon.phase))
                .font(.caption2)
                .foregroundStyle(SN.foam.opacity(0.6))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
```

The time keeps `.title` weight-medium monospaced-digit with `.contentTransition(.numericText())` — it is still the thing that ticks while you scrub. One row, not the old stacked block: at the bottom of the card it is a footer, not a headline.

- [ ] **Step 4: Run tests to verify green**

Run: `./scripts/test.sh`

Expected: PASS. `ScrubWhen` is not yet referenced by any view — that is Tasks 4–5.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/Theme.swift SlackwaterTests/ScrubWhenTests.swift
git commit -m "when-row: extract ScrubWhen + scrubDayOffset, the shared calendar of a scrub reading"
```

---

### Task 4: Tide detail — readout leads, when-row last, return-to-now in the row

`TideDetailView.scrubCard` reorders to: readout (with ↺) → strip → hint → `ScrubWhen`. The hero seam closes.

**Files:**
- Modify: `Slackwater/TideDetailView.swift:26-31` (delete `dayOffset`), `:33-48` (body spacing), `:63-129` (scrubCard)

**Interfaces:**
- Consumes: `ScrubWhen`, `scrubDayOffset` (Task 3); `scrubbedAway` (`TimelineStrip.swift:35`).
- Produces: the return-slot idiom Task 5 copies (the fixed-44pt `ZStack`).

- [ ] **Step 1: Reorder the card**

In `scrubCard` (`TideDetailView.swift:63`):

1. Delete the opening `HStack(alignment: .top) { ... }` date/time/moon block (`:65-85`).
2. The height/NEXT LOW `HStack` (`:87-109`) becomes the card's first child; delete its `.padding(.top, 14)`.
3. Append a return-to-now slot at the trailing edge of that `HStack`, after the NEXT LOW `VStack` — a fixed-size slot so the row never reflows when a scrub starts or ends (the same occupies-its-points-either-way reasoning as the old hero overlay, `MapHeader.swift:107-109`):

```swift
// Return-to-now: a FIXED 44pt slot beside NEXT LOW — present or not, the
// row's layout is identical, so nothing reflows when a scrub starts/ends.
ZStack {
    if scrubbedAway(scrubTime, from: live) {
        Button(action: returnToNow) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SN.leaf)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .accessibilityLabel("Return to now")
        .accessibilityIdentifier("detail-return-now")
    }
}
.frame(width: 44, height: 44)
```

4. After the swipe-hint `MonoLabel` (`:117-120`), append the when-row:

```swift
ScrubWhen(scrubTime: scrubTime, live: live, tz: tz)
    .padding(.top, 14)
```

5. Delete the `dayOffset` computed property (`:26-31`) — `ScrubWhen` owns it now.

- [ ] **Step 2: Close the hero seam and stop passing showReturn**

In `body` (`:33-48`):

- `VStack(spacing: 14)` → `VStack(spacing: 0)`; the schedule card and footer get their spacing back explicitly: `.padding(.top, 14)` on `scheduleCard(timeline)` and on `footer`.
- The card's `.padding(.top, 16)` (`:123`) → `.padding(.top, 14)` — the seam's gap now lives entirely inside the card, against `SN.cardFill`, not as page background between hero and card.
- `MapHeader` call (`:36-40`): pass `showReturn: false, onReturn: {}` — the hero's copy goes dark here; Task 6 deletes the parameters everywhere.

- [ ] **Step 3: Run tests**

Run: `./scripts/test.sh`

Expected: PASS. `ScreenshotTests` finds `detail-return-now` by identifier — it moved but kept its name.

- [ ] **Step 4: Look at it**

Build to the iPhone 17 Pro simulator, open any tide station, scrub away, and check: readout directly under the hero, no page-coloured gap, ↺ appears beside NEXT LOW without shifting it, when-row at the card's bottom ticking as you scrub.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/TideDetailView.swift
git commit -m "tide detail: the reading leads, the calendar goes last, return-to-now joins the readout"
```

---

### Task 5: Current + derived-gate details — same order, same slot

Both cards keep their per-type anatomy (primary readout *below* the strip — the phase colour sits next to the curve it describes) and adopt the same two rules: when-row last, return-to-now in the primary readout row.

**Files:**
- Modify: `Slackwater/CurrentDetailView.swift:45-50` (delete `dayOffset`), `:52-72` (body spacing), `:104-219` (scrubCard)
- Modify: `Slackwater/DerivedGateDetailView.swift:26-34` (delete `dayOffset`), `:36-50` (body spacing), `:80-172` (scrubCard)

**Interfaces:**
- Consumes: `ScrubWhen`, `scrubDayOffset`, the Task 4 return-slot idiom (repeated below in full).

- [ ] **Step 1: CurrentDetailView**

In `scrubCard` (`:104`):

1. Delete the opening date/time/moon `HStack` (`:106-125`).
2. The `tide at port` block (`:127-148`) becomes the card's first child; its `.padding(.top, 14)` is deleted. (The block itself is explicitly out of scope — it stays above the strip.)
3. In the current readout `HStack` below the strip (`:157`), after the Next-slack `VStack` (`:189-203`), append the identical fixed slot:

```swift
ZStack {
    if scrubbedAway(scrubTime, from: live) {
        Button(action: returnToNow) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SN.leaf)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .accessibilityLabel("Return to now")
        .accessibilityIdentifier("detail-return-now")
    }
}
.frame(width: 44, height: 44)
```

4. After the swipe-hint `MonoLabel` (`:207-210`), append:

```swift
ScrubWhen(scrubTime: scrubTime, live: live, tz: tz)
    .padding(.top, 14)
```

5. Delete `dayOffset` (`:45-50`).

In `body` (`:52-72`): `VStack(spacing: 14)` → `spacing: 0`; add `.padding(.top, 14)` to `scheduleCard(timeline)`, `footer`, and the `ChsAmberCard` (`:60-65` — the amber card sits between hero and scrub card when provisional; it needs the spacing both sides, so also give `scrubCard(timeline)` `.padding(.top, 14)` *only inside the `if let gate = provisionalGate` world* — simplest correct form: give the amber card `.padding(.top, 14)` and leave the scrub card flush, since the amber card's own fill reads as part of the stack). Card `.padding(.top, 16)` (`:213`) → `.padding(.top, 14)`. `MapHeader` call (`:55-59`): `showReturn: false, onReturn: {}`.

- [ ] **Step 2: DerivedGateDetailView**

Same four moves in `scrubCard` (`:80`):

1. Delete the date/time/moon `HStack` (`:82-101`).
2. `Tide at port` block (`:103-121`) leads; delete its `.padding(.top, 14)`.
3. In the phase readout `HStack` (`:132`), after the Next-slack `VStack` (`:141-150`), append the same fixed 44pt `ZStack` slot verbatim.
4. After the swipe-hint `MonoLabel` (`:160-163`), append `ScrubWhen(scrubTime: scrubTime, live: live, tz: tz).padding(.top, 14)`. The shape-only caveat text (`:154-158`) stays where it is, above the hint.
5. Delete `dayOffset` (`:26-34`).

In `body` (`:36-50`): `VStack(spacing: 0)`; `.padding(.top, 14)` on `scheduleCard` and `footer`; card top padding 16 → 14; `MapHeader` gets `showReturn: false, onReturn: {}`.

- [ ] **Step 3: Run tests**

Run: `./scripts/test.sh`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Slackwater/CurrentDetailView.swift Slackwater/DerivedGateDetailView.swift
git commit -m "current + gate details: when-row last, return-to-now in the readout row"
```

---

### Task 6: The hero crops — intrinsic height, two-stop scrim, no pin, no return params

With return-to-now living in the cards, `MapHeader` sheds the overlay and the `showReturn`/`onReturn` parameters, drops the pin, and stops being 420pt.

**Files:**
- Modify: `Slackwater/MapHeader.swift` (throughout)
- Modify: `Slackwater/TideDetailView.swift:36-40`, `Slackwater/CurrentDetailView.swift:55-59`, `Slackwater/DerivedGateDetailView.swift:39-43`, `Slackwater/ChsDetailView.swift:114-115` (call sites)
- Test: `SlackwaterTests/HeroChromeTests.swift`

**Interfaces:**
- Produces: `MapHeader(name:region:latitude:longitude:favoriteId:)` — five parameters, nothing else.

- [ ] **Step 1: Write the failing height test**

Append to `HeroChromeTests.swift`:

```swift
/// The "a third, not a half" claim, executable: at default type the hero is
/// title-pill + clearances, well under 200pt. At AX3 it must GROW — a fixed
/// crop that clips the region line is the defect class the Dynamic Type pass
/// just cleared (2026-08-02 note).
@MainActor
func testHeroIsAThirdAtDefaultTypeAndGrowsAtAX3() {
    func height(at size: UIContentSizeCategory) -> CGFloat {
        let host = UIHostingController(rootView:
            MapHeader(name: "Sesuit Harbor", region: "EAST DENNIS",
                      latitude: 41.75, longitude: -70.15, favoriteId: "test"))
        host.traitOverrides.preferredContentSizeCategory = size
        return host.sizeThatFits(in: CGSize(width: 393, height: .greatestFiniteMagnitude)).height
    }
    let base = height(at: .large)
    XCTAssertLessThan(base, 200, "hero must be a third of the screen, not half")
    XCTAssertGreaterThan(base, 100, "hero must still clear the status bar + pill")
    XCTAssertGreaterThan(height(at: .accessibilityExtraExtraExtraLarge), base,
                         "the hero grows with type — it never crops the pill")
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/test.sh`

Expected: compile FAILURE — `MapHeader` still takes `showReturn:`/`onReturn:`. (The compile error *is* the failing state; the height assertion bites after Step 3.)

- [ ] **Step 3: Rework `MapHeader`**

```swift
/// Bottom band of map kept below the title pill — the border the name sits
/// on, not a viewport. The header's height is pill + clearances, so it
/// scales with Dynamic Type instead of cropping at AX sizes.
let mapHeaderBottomMargin: CGFloat = 24
```

(Replaces `mapHeaderHeight` at `:11`; `stationZoom` stays.)

Signature: delete `showReturn` and `onReturn`. Body:

1. Delete the pin `Circle()` (`:31-37`) — at this crop the center is behind the title pill; the name answers "where", not the map.
2. Scrim (`:40-45`) collapses to two stops — the middle stops were tuned for 420pt and read as a flat wash at a third:

```swift
LinearGradient(stops: [
    .init(color: Color(hex: 0x05122A, opacity: 0.80), location: 0),
    .init(color: Color(hex: 0x05122A, opacity: 0.35), location: 1),
], startPoint: .top, endPoint: .bottom)
.allowsHitTesting(false)
```

3. Height: the chrome sizes the header; the map fills behind it. The `ZStack` restructures to:

```swift
GlassEffectContainer {
    HStack(alignment: .top) { /* back / pill / star, unchanged from Task 2 */ }
}
.padding(.horizontal, 16)
.padding(.top, 62)   // clears the status bar; header ignores the top safe area
.padding(.bottom, mapHeaderBottomMargin)
.frame(maxWidth: .infinity)
.background {
    StationMapView(latitude: latitude, longitude: longitude)
    LinearGradient(/* the two-stop scrim above */)
        .allowsHitTesting(false)
}
```

Delete: the outer `VStack`/`Spacer()` (`:48`, `:103`), `.frame(height: mapHeaderHeight)` (`:106`), the whole return-to-now `.overlay` (`:110-126`). Keep: `.clipped()`, `.background(Color(hex: 0x05122A))`, `.background(InteractivePopEnabler())`, both accessibility modifiers, and the fixed-hit-target comment (`:50-55`).

4. Call sites: all four detail views drop `showReturn:`/`onReturn:` from their `MapHeader` calls. `ChsDetailView` (`:114-115`) simply loses the two dead arguments — it never had a scrubber to return from.

- [ ] **Step 4: Run tests to verify green**

Run: `./scripts/test.sh`

Expected: PASS, including the new height assertions and the AX3 `ScreenshotTests`.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/MapHeader.swift Slackwater/TideDetailView.swift Slackwater/CurrentDetailView.swift Slackwater/DerivedGateDetailView.swift Slackwater/ChsDetailView.swift SlackwaterTests/HeroChromeTests.swift
git commit -m "hero: crop to pill + margin, two-stop scrim, pin and return overlay go"
```

---

### Task 7: Look at all of it, then the PR

**Files:**
- None (verification + PR)

- [ ] **Step 1: Full-surface screenshots**

Run: `SHOT_DIR=/tmp/hero-shots ./scripts/test.sh`

Walk the saved screenshots: tide, current, derived gate, CHS-waiting details at default type and AX3, iPhone and iPad split. The four checks from the spec's Verification section:

1. `TypeScaleTests` green (already asserted by the run).
2. AX3: the title pill never clips; the hero grows.
3. Glass legibility over the brightest chart fill — open a station whose hero top is sand-coloured land (Sesuit Harbor's stored twin, or any Boundary Pass station with land in frame) and confirm the two-stop scrim still carries the pill's legibility with the navy layer gone.
4. Scrub away on device/simulator: ↺ appears in the readout row with zero reflow of NEXT LOW.

If any check fails, fix forward on this branch before the PR — do not ship the screenshot pass as a follow-up.

- [ ] **Step 2: Push and open the PR (do not merge)**

```bash
gh auth status
git push -u origin detail/hero-crop-and-scrub-order
```

Draft the PR body for Bryan's review before `gh pr create` — outbound text gets review first. Body covers: the spec link, the five decisions, the iOS 26 floor rationale (scaffolded-not-chosen, pre-App-Store, chartplotter-vs-tides), and the two executable rules added (`testNoMaterialImitationOfGlass`, the hero height assertions). Never merge your own PR (CONTRIBUTING.md).

---

## Self-Review

- **Spec coverage:** hero ⅓ + intrinsic height (Task 6), glass chrome + floor (Tasks 1–2), readout leads + flush seam (Tasks 4–5), when-row last (Tasks 3–5), `ScrubWhen` shared (Task 3), FAB conversions (Task 2), pin dropped + return-to-now moved (Tasks 4–6), `ChsDetailView` loses dead params (Task 6), the under-200pt assertion (Task 6). The `tide at port` block explicitly stays put (Task 5, spec's Out list).
- **Placeholder scan:** all code steps carry full code; the two "verbatim" repeats in Task 5 are printed in full.
- **Type consistency:** `ScrubWhen(scrubTime:live:tz:)` and `scrubDayOffset(_:from:_:)` match between Task 3 (definition) and Tasks 4–5 (use); `MapHeader(name:region:latitude:longitude:favoriteId:)` matches between Task 6's test and rework.
