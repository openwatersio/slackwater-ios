# Colour and Form — iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make colour encode water state and form encode station kind, everywhere in the iOS app — removing the green/blue collision where the map paints kind in the same hues the rest of the app paints direction.

**Architecture:** One token change in `Theme.swift` retargets the direction axis and frees green for slack; every consumer then either inherits it or is audited. The list card gains a kind glyph and loses its per-station gradient. Map pins stop matching `circle-color` on kind and become shape-per-kind, colour-per-state.

**Tech Stack:** SwiftUI, MapLibre (via `MapScreen.swift`), XCTest via `scripts/test.sh`, xcodegen (`project.yml`).

**Spec:** `docs/superpowers/specs/2026-08-02-colour-and-form-design.md`

## Global Constraints

- **Colour encodes state; form encodes kind.** Nothing may derive colour from station kind.
- Direction tokens, exact values: `flood = 0x4A9FD8`, `ebb = 0xE8A33D`, `go = 0x88B868`. `rising` aliases `flood`; `falling` aliases `ebb`.
- `SN.amber` becomes `0xEF6F4A` — it currently sits too close to the new `ebb` to be distinguishable.
- **Slack is `SN.go` everywhere.** On web, `--go` had one consumer while chart dots, event pills and phase pills still drew slack neutral, so a gate at slack showed a green glyph beside a grey "slack" pill in one card. Do not reproduce that.
- Map marks: **filled circle = current station, filled square = tide station**, square drawn to equal *area* not equal width. Not the card's glyphs — those were tried on the web map and rejected as too busy over bathymetry.
- **`pinKind` has three values** — `tide`, `current`, `chs`. `chs` is a Canadian tide port: it is a **tide station**, and the `chs` distinction is provenance, not kind. `tide` and `chs` both draw the square. `PIN_CHS` is deleted along with `PIN_TIDE` / `PIN_CURRENT`.
- **Clusters draw neutral.** A cluster is an aggregate with no single kind or state, so it takes neither the kind shape nor a state colour.
- Typography, launch behaviour, the `MapHeader` height, and the starred/tap-card interaction are **out of scope** — each is its own piece. Do not touch fonts.
- Work on branch `design/colour-and-form` in `/Users/clarkbw/src/sailingnaturali/slackwater-ios`. **No direct pushes to `main`** (`CONTRIBUTING.md`). **An agent never merges its own PR.**
- **Verify the branch before every commit** — this repo has other work landing concurrently: `git rev-parse --show-toplevel && git branch --show-current`.
- Run `./scripts/test.sh` (fast plan, ~9 min/sim) before each commit.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `Slackwater/Theme.swift` | Tokens; delete `stationGradient`/`gradientTrios`; `DistancePill` | 1, 3 |
| `SlackwaterTests/ColourAndFormTests.swift` | **New.** The two-axis invariant | 1, 3 |
| `Slackwater/CurrentDetailView.swift`, `DerivedGateDetailView.swift`, `TideDetailView.swift`, `TimelineStrip.swift` | Direction and slack call sites | 2 |
| `Slackwater/StationGlyph.swift` | **New.** The card's kind glyph | 3 |
| `Slackwater/SlackwaterApp.swift` | Five card variants → layout A | 3 |
| `Slackwater/MapScreen.swift` | Pin marks and colours | 4 |

---

### Task 1: Tokens

**Files:**
- Modify: `Slackwater/Theme.swift:15-36` (the `SN` enum)
- Create: `SlackwaterTests/ColourAndFormTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `SN.flood`, `SN.ebb`, `SN.go`, retargeted `SN.rising` / `SN.falling`, and `SN.amber` at its new value. Tasks 2-4 reference these by name.

- [ ] **Step 1: Write the failing test**

Create `SlackwaterTests/ColourAndFormTests.swift`. Comparing `Color` directly is unreliable across colour spaces, so compare resolved sRGB components.

```swift
import SwiftUI
import XCTest
@testable import Slackwater

/// Colour is state; form is kind. These tests are the rule, executable.
final class ColourAndFormTests: XCTestCase {

    /// Resolved sRGB components, so two Colors built the same way compare equal.
    private func rgb(_ color: Color) -> [CGFloat] {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { ($0 * 1000).rounded() / 1000 }
    }

    private func assertSameColour(_ a: Color, _ b: Color, _ message: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rgb(a), rgb(b), message, file: file, line: line)
    }

    private func assertDifferentColour(_ a: Color, _ b: Color, _ message: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(rgb(a), rgb(b), message, file: file, line: line)
    }

    func testDirectionIsASignedDivergingAxis() {
        assertSameColour(SN.rising, SN.flood, "rising must alias flood")
        assertSameColour(SN.falling, SN.ebb, "falling must alias ebb")
        assertDifferentColour(SN.flood, SN.ebb, "the two ends of the axis must differ")
    }

    func testGreenMeansOnlySlack() {
        assertDifferentColour(SN.go, SN.flood, "green must not also mean flood")
        assertDifferentColour(SN.go, SN.ebb, "green must not also mean ebb")
    }

    func testWarningIsDistinguishableFromEbb() {
        // These were briefly the same hex on web and collided in the event list,
        // where a sunset pill and a max-ebb pill became indistinguishable.
        assertDifferentColour(SN.amber, SN.ebb, "the warning tone must not read as ebb")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/test.sh`
Expected: FAIL — `SN.flood`, `SN.ebb` and `SN.go` do not exist, so the target does not compile. A compile failure is the correct RED here.

- [ ] **Step 3: Retarget the tokens**

In `Slackwater/Theme.swift`, replace the `rising` / `falling` lines (`:25-26`) and add the three new tokens:

```swift
    // Direction is one signed diverging axis; green means only slack.
    //
    // This replaced a green/blue direction pair that collided with the map's
    // green/blue *kind* pins — a green dot meant "current station" on one
    // screen and "flooding" on the next. Amber/blue is the standard
    // colourblind-safe diverging pair and it frees green, which matters: for an
    // app called Slackwater the moment you wait for is slack, and green names
    // it. Never colour anything by station kind.
    static let flood = Color(hex: 0x4A9FD8)
    static let ebb = Color(hex: 0xE8A33D)
    static let go = Color(hex: 0x88B868)
    static let rising = flood
    static let falling = ebb
```

Then change `amber` (`:33`):

```swift
    /// Attention, never alarm: the location-denied card, and the unfitted
    /// station's ⚠️ download warning. Deliberately red-leaning rather than
    /// golden — the old 0xE0B45A sat close enough to `ebb` to be misread as a
    /// tide state. Same value the web app uses for the same job.
    static let amber = Color(hex: 0xEF6F4A)
```

Leave `SN.leaf` as it is — it is still the brand green used for chrome (`cardStroke`, accents), and `go` is deliberately a separate name even though the value matches today.

- [ ] **Step 4: Run the tests**

Run: `./scripts/test.sh`
Expected: PASS, including the three new tests.

- [ ] **Step 5: Commit**

Verify the branch first: `git rev-parse --show-toplevel && git branch --show-current` must print the repo path and `design/colour-and-form`.

```bash
git add Slackwater/Theme.swift SlackwaterTests/ColourAndFormTests.swift
git commit -m "feat(theme): direction is a diverging axis, green means slack

Replaces a green/blue direction pair that collided with the map's
green/blue kind pins. Splits the warning tone off the new ebb before
they become indistinguishable, as they did on web."
```

---

### Task 2: Direction and slack call sites

Retargeting the tokens changes most of these for free. The work is the **audit** — confirming each surface now says the right thing, and fixing every slack rendering that is still neutral.

**Files:**
- Modify: `Slackwater/CurrentDetailView.swift:95-99`, `Slackwater/DerivedGateDetailView.swift:73-77`, `Slackwater/TideDetailView.swift:96`, `Slackwater/TimelineStrip.swift:744,750,759` and its slack renderings
- Modify: `SlackwaterTests/ColourAndFormTests.swift`

**Interfaces:**
- Consumes: `SN.flood`, `SN.ebb`, `SN.go` from Task 1.
- Produces: no new API. Every `phaseColor` returns `SN.go` for `.slack`.

- [ ] **Step 1: Find every slack rendering**

```bash
grep -rn "slack" Slackwater/*.swift | grep -iv "slackwater"
```

Record the list in your report — it is the audit's evidence. Expect `phaseColor` switches in `CurrentDetailView.swift` and `DerivedGateDetailView.swift`, plus pill and dot renderings in `TimelineStrip.swift`.

- [ ] **Step 2: Write the failing test**

Append to `SlackwaterTests/ColourAndFormTests.swift`:

```swift
    func testSlackIsGreenWhereverItAppears() {
        // A gate at slack must not show a green glyph beside a grey "slack"
        // pill in the same card — which is exactly what happened on web when
        // only one surface adopted the go colour.
        assertSameColour(CurrentDetailView.phaseColor(.slack), SN.go, "detail view slack")
        assertSameColour(DerivedGateDetailView.phaseColor(.slack), SN.go, "derived gate slack")
    }

    func testPhaseColoursUseTheDivergingAxis() {
        assertSameColour(CurrentDetailView.phaseColor(.flood), SN.flood, "flood")
        assertSameColour(CurrentDetailView.phaseColor(.ebb), SN.ebb, "ebb")
    }
```

If `phaseColor` is currently a private instance member, make it a `static` method on the view type so it is testable without constructing a view. That is a smaller change than it sounds — it takes a phase and returns a colour, and depends on nothing else.

- [ ] **Step 3: Run it to verify it fails**

Run: `./scripts/test.sh`
Expected: FAIL — slack returns a neutral ink rather than `SN.go` (or the target does not compile until `phaseColor` is made static).

- [ ] **Step 4: Make slack green**

In each `phaseColor` switch, the `.slack` arm returns `SN.go`. Then work the list from Step 1: every remaining slack rendering — timeline pills, chart dots — takes `SN.go`.

Add a comment at one representative site so the reason survives:

```swift
        // Slack is the app's "go" colour, not a neutral. It is the moment the
        // app is named for, and it must read the same on every surface.
```

- [ ] **Step 5: Verify the direction sites inherited correctly**

These need no edit, but confirm each renders the new hue rather than a hardcoded old one:

```bash
grep -rn "0x7FB4D8\|0x88B868" Slackwater/*.swift
```

Expected: no hit outside `Theme.swift`'s own definitions. A hit elsewhere is a surface that hardcoded the retired value and would silently keep speaking the old language — fix it to use the token.

- [ ] **Step 6: Run the tests**

Run: `./scripts/test.sh`
Expected: PASS.

- [ ] **Step 7: Commit**

Verify the branch, then:

```bash
git add Slackwater/CurrentDetailView.swift Slackwater/DerivedGateDetailView.swift Slackwater/TideDetailView.swift Slackwater/TimelineStrip.swift SlackwaterTests/ColourAndFormTests.swift
git commit -m "feat(detail): slack is green on every surface, not just one

Audited every slack rendering rather than assuming the token retarget
covered them. On web, only the glyph adopted the go colour and a gate
at slack showed green beside a grey slack pill in the same card."
```

---

### Task 3: The kind glyph and card layout A

**Files:**
- Create: `Slackwater/StationGlyph.swift`
- Modify: `Slackwater/SlackwaterApp.swift` — `StationCardView` (:1036-1085), `ChsCardView`/`ChsPendingCard` (:1090-1171), `ChsGateCardView` (:1177-1237), `ChsCurrentGateCardView`/`CurrentCardView` (:1242-1349)
- Modify: `Slackwater/Theme.swift` — delete `gradientTrios` (:78-88) and `stationGradient` (:90-99); `DistancePill` (:258-274)
- Modify: `SlackwaterTests/ColourAndFormTests.swift`

**Interfaces:**
- Consumes: `SN.flood`, `SN.ebb`, `SN.go` from Task 1.
- Produces: `StationGlyph(kind:tone:)` — `enum GlyphKind { case tide, current }`, `enum Tone { case rising, falling, flood, ebb, slack, unknown }`, and `static func colour(for: Tone) -> Color`. Task 4 reuses `Tone` and `colour(for:)`.

- [ ] **Step 1: Write the failing test**

Append to `SlackwaterTests/ColourAndFormTests.swift`:

```swift
    func testGlyphColourTracksStateAndNeverKind() {
        // Same state, different kinds: same colour.
        assertSameColour(StationGlyph.colour(for: .slack), StationGlyph.colour(for: .slack),
                         "tone determines colour")
        // Different states: different colours.
        assertDifferentColour(StationGlyph.colour(for: .flood), StationGlyph.colour(for: .ebb),
                              "flood and ebb must not share a colour")
        assertSameColour(StationGlyph.colour(for: .rising), StationGlyph.colour(for: .flood),
                         "rising and flood are one end of the axis")
        assertSameColour(StationGlyph.colour(for: .slack), SN.go, "slack is the go colour")
    }

    func testGlyphShapeTracksKind() {
        // The two kinds must not produce identical paths — that would collapse
        // the form axis and leave kind unexpressed.
        let box = CGRect(x: 0, y: 0, width: 24, height: 24)
        XCTAssertNotEqual(StationGlyph.path(for: .tide, in: box).description,
                          StationGlyph.path(for: .current, in: box).description,
                          "tide and current must draw different shapes")
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/test.sh`
Expected: FAIL — `StationGlyph` does not exist, so the target does not compile.

- [ ] **Step 3: Write the glyph**

Create `Slackwater/StationGlyph.swift`:

```swift
import SwiftUI

/// A station's kind, drawn — a wave for a current station, a dome over a datum
/// line for a tide station. The glyph's COLOUR is its live state and never its
/// kind: that separation is the whole point. A green wave is a current gate at
/// slack, which is the most useful thing to spot while scanning a mixed list.
///
/// The map deliberately does NOT use these. Tried there and rejected: thin
/// curved strokes over bathymetry contours make a dense chart denser. The map
/// takes plain circle and square markers instead. A list row is roomy enough to
/// earn an expressive glyph; a chart at zoom 12 is not.
struct StationGlyph: View {
    enum GlyphKind { case tide, current }
    enum Tone { case rising, falling, flood, ebb, slack, unknown }

    let kind: GlyphKind
    let tone: Tone
    var size: CGFloat = 24

    static func colour(for tone: Tone) -> Color {
        switch tone {
        case .rising, .flood: SN.flood
        case .falling, .ebb: SN.ebb
        case .slack: SN.go
        case .unknown: SN.steel
        }
    }

    /// One wave for a current station; a dome over a datum line for a tide one.
    static func path(for kind: GlyphKind, in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        switch kind {
        case .current:
            p.move(to: CGPoint(x: 0.08 * w, y: 0.5 * h))
            p.addCurve(to: CGPoint(x: 0.5 * w, y: 0.5 * h),
                       control1: CGPoint(x: 0.22 * w, y: 0.12 * h),
                       control2: CGPoint(x: 0.36 * w, y: 0.88 * h))
            p.addCurve(to: CGPoint(x: 0.92 * w, y: 0.5 * h),
                       control1: CGPoint(x: 0.64 * w, y: 0.12 * h),
                       control2: CGPoint(x: 0.78 * w, y: 0.88 * h))
        case .tide:
            p.move(to: CGPoint(x: 0.10 * w, y: 0.66 * h))
            p.addQuadCurve(to: CGPoint(x: 0.90 * w, y: 0.66 * h),
                           control: CGPoint(x: 0.5 * w, y: 0.08 * h))
            p.move(to: CGPoint(x: 0.14 * w, y: 0.84 * h))
            p.addLine(to: CGPoint(x: 0.86 * w, y: 0.84 * h))
        }
        return p
    }

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            context.stroke(Self.path(for: kind, in: rect),
                           with: .color(Self.colour(for: tone)),
                           style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(kind == .current ? "Current station" : "Tide station")
    }
}
```

- [ ] **Step 4: Run the glyph tests**

Run: `./scripts/test.sh`
Expected: PASS.

- [ ] **Step 5: Apply layout A to the five card variants**

All five share the same shell: an `HStack(alignment: .top)` with an identity `VStack` on the left and a state `VStack` on the right. Three changes per variant:

1. **Add the glyph** in the gutter, before the identity column:

```swift
            HStack(alignment: .top, spacing: 12) {
                StationGlyph(kind: .tide, tone: state?.rising == true ? .rising : .falling)
                VStack(alignment: .leading, spacing: 2) {
```

Use `.current` for `CurrentCardView`, `ChsGateCardView` and `ChsCurrentGateCardView`; `.tide` for `StationCardView` and `ChsCardView`. Where no state has loaded yet, pass `.unknown` — **do not** infer kind from whether a reading arrived; kind is fixed by which card variant renders.

2. **Distance moves into the identity column** as a third line, below region:

```swift
                    if let km {
                        Text("\(formatNm(km))")
                            .font(.geist(12))
                            .foregroundStyle(SN.foam.opacity(0.7))
                    }
```

Each card variant that currently has `DistancePill` overlaid at its call site takes a `km: Double?` parameter instead. Remove the `DistancePill` overlay from those call sites. Leave `DistancePill` itself in place if the My Location tile still uses it — check with `grep -rn "DistancePill" Slackwater/`.

3. **Background goes flat.** Replace `.background(stationGradient(id: record.id))` with:

```swift
        .background(SN.cardFill)
```

- [ ] **Step 6: Delete the gradient**

Once no call site remains, delete `gradientTrios` and `stationGradient` from `Theme.swift`. Verify first:

```bash
grep -rn "stationGradient\|gradientTrios" Slackwater/
```

Expected after the edit: no hits. The per-station tint is what the design reviewer could not decode — it genuinely varies per station and genuinely encodes nothing.

- [ ] **Step 7: Run the tests**

Run: `./scripts/test.sh`
Expected: PASS. Screenshot UI tests may need their reference images regenerated — if a screenshot test fails purely on appearance, that is expected and the images are updated, but **say so explicitly in your report** rather than updating them silently.

- [ ] **Step 8: Commit**

Verify the branch, then:

```bash
git add Slackwater/StationGlyph.swift Slackwater/SlackwaterApp.swift Slackwater/Theme.swift SlackwaterTests/ColourAndFormTests.swift
git commit -m "feat(card): layout A, kind glyph, flat background

Distance moves from a floating corner pill into the identity column
where it belongs. The per-station gradient goes: it varied per station
and encoded nothing, which is exactly what a reviewer could not decode."
```

---

### Task 4: Map pins

**Files:**
- Modify: `Slackwater/MapScreen.swift:33` (the `PIN_*` constants), `:90-115` (cluster and dot layers)
- Modify: `SlackwaterTests/ColourAndFormTests.swift`

**Interfaces:**
- Consumes: `StationGlyph.Tone` and `StationGlyph.colour(for:)` from Task 3, for the tone vocabulary.
- Produces: no new API.

- [ ] **Step 1: Write the failing test**

Append to `SlackwaterTests/ColourAndFormTests.swift`:

```swift
    func testMapNeverColoursByStationKind() throws {
        // The defect this whole change exists to remove: the map matched
        // circle-color against ["get", "kind"], so a green dot meant "current
        // station" here and "flooding" everywhere else.
        let source = try String(contentsOfFile: mapScreenPath(), encoding: .utf8)
        XCTAssertFalse(source.contains("#8fd0a0"), "retired kind-green must be gone")
        XCTAssertFalse(source.contains("#7fb3d5"), "retired kind-blue must be gone")
        XCTAssertFalse(source.contains("#c0d8e4"), "retired chs-kind tone must be gone")
        XCTAssertNil(source.range(of: #"circle-color[^\n]*\["get", "kind"\]"#, options: .regularExpression),
                     "colour must never be matched against kind")
    }

    /// `#filePath` of this test file resolves to the repo, so the source under
    /// test can be read relative to it.
    private func mapScreenPath() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SlackwaterTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Slackwater/MapScreen.swift").path
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/test.sh`
Expected: FAIL — the retired hexes are still present.

- [ ] **Step 3: Replace the pin constants**

In `Slackwater/MapScreen.swift`, replace line 33:

```swift
// A pin's COLOUR is the water's state, never the station's kind — kind is the
// pin's SHAPE: a circle for a current station, a square for a tide one. One
// shape per feature class, the oldest convention on any chart, and a silhouette
// difference reads where an interior one does not.
//
// `chs` is a Canadian tide port. That is provenance, not kind — it draws the
// same square a NOAA tide station does.
private let PIN_NEUTRAL = "#7d9cb8"
```

- [ ] **Step 4: Split the dot layer into two shaped layers**

Replace the `dots` layer (`:103-115`) with two layers, one per shape. MapLibre circles cannot be squares, so the tide layer uses an SDF icon.

The square needs an image. MapLibre Native tints an image with `icon-color` only when it is registered as a **template** image — `UIImage.withRenderingMode(.alwaysTemplate)` is what marks it as SDF on this binding, which is far simpler than the manual distance-field encoding the web version needed.

Register it in the existing `didFinishLoading style:` delegate callback (`MapScreen.swift:257`), which fires on **every** style load — and this map loads twice, the local fallback then Seascape, so registering once at init would lose the image on the swap:

```swift
    /// A filled square, drawn to equal AREA with the 5pt circle pins: for
    /// radius r the side is r·√π. A same-width square always reads heavier.
    /// Registered as a template image so `icon-color` can tint it — that is
    /// MapLibre Native's SDF path, and without it the pin ignores state.
    private func squarePinImage(radius: CGFloat = 5, scale: CGFloat = 3) -> UIImage {
        let side = radius * CGFloat(Double.pi.squareRoot())
        let size = CGSize(width: side * 2, height: side * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
```

and in `mapView(_:didFinishLoading:)`:

```swift
        style.setImage(squarePinImage(), forName: "pin-square")
```

```swift
    let currentPins: [String: Any] = [
        "id": "station-pins-current", "type": "circle", "source": "stations",
        "filter": ["all", notACluster, ["==", ["get", "kind"], "current"]] as [Any],
        "paint": [
            "circle-radius": 5,
            "circle-color": PIN_NEUTRAL,
            "circle-stroke-width": 1.5,
            "circle-stroke-color": WATER_TONE,
        ],
    ]
    // tide and chs are both tide stations — provenance is not kind.
    let tidePins: [String: Any] = [
        "id": "station-pins-tide", "type": "symbol", "source": "stations",
        "filter": ["all", notACluster, ["!=", ["get", "kind"], "current"]] as [Any],
        "layout": [
            "icon-image": "pin-square",
            "icon-allow-overlap": true,
            "icon-ignore-placement": true,
        ],
        "paint": [
            "icon-color": PIN_NEUTRAL,
            "icon-halo-color": WATER_TONE,
            "icon-halo-width": 1.5,
        ],
    ]
```

Both layers carry the **same** colour expression. That is the invariant made structural: kind selects which layer a pin lands in, and colour is identical across them, so colour cannot track kind.

Both layers use `PIN_NEUTRAL` for now. Task 5 replaces that with live state on both at once — keeping them identical is what makes colour structurally unable to track kind.

- [ ] **Step 5: Make the cluster neutral**

The cluster layer (`:90-102`) currently paints `circle-color: PIN_TIDE`. A cluster is an aggregate with no single kind or state:

```swift
            "circle-color": PIN_NEUTRAL,
```

- [ ] **Step 6: Update every layer-id reference**

`station-dots` no longer exists. Find every use — tap handling, hit-testing, layer ordering:

```bash
grep -rn "station-dots" Slackwater/
```

Each must become both new ids. **Missing one silently kills interaction for one pin kind, and no test will catch it** — this exact omission nearly shipped on web when the equivalent layer was split.

- [ ] **Step 7: Run the tests**

Run: `./scripts/test.sh`
Expected: PASS.

- [ ] **Step 8: Verify on a simulator**

No unit test can see whether pins render or whether tapping one works. Build and run, open the map, and confirm:

1. Current stations draw as circles, tide stations (both NOAA and CHS) as squares.
2. Both read as equal visual weight — neither dominates.
3. Tapping a pin of **each** kind still selects that station.
4. Clusters render neutral and expand on tap as before.

Report what you actually observed for each. If you cannot run a simulator, say so and report BLOCKED rather than claiming the check passed.

- [ ] **Step 9: Commit**

Verify the branch, then:

```bash
git add Slackwater/MapScreen.swift SlackwaterTests/ColourAndFormTests.swift
git commit -m "feat(map): pins encode kind by shape, not colour

The map matched circle-color against kind, so a green dot meant
'current station' here and 'flooding' on every other screen. Kind
becomes shape — circle for current, square for tide — and both layers
carry the same colour expression, so colour cannot track kind."
```

---

---

### Task 5: Pin colour carries state

Task 4 gave pins their shape and left them neutral. This makes colour mean what the rule says it means.

**Scope limit, deliberate:** only stations that resolve **synchronously on device** get a colour — bundled NOAA tide and current stations, and derived gates, all via the `cardState(at:)` helpers that already exist. **CHS stations stay neutral**, because their readings live behind an async cache and wiring that in is a subsystem, not a step. Neutral is the honest "unknown" the rule already defines, and the async CHS read is recorded as a follow-on. Do not build it here.

**Files:**
- Modify: `Slackwater/MapScreen.swift` — `pinFeatures()` (:36-48), the two pin layers from Task 4
- Modify: `SlackwaterTests/ColourAndFormTests.swift`

**Interfaces:**
- Consumes: `StationGlyph.Tone` and `StationGlyph.colour(for:)` from Task 3; `cardState(at:)` on the station types.
- Produces: a `state` property on every pin feature, one of `rising`/`falling`/`flood`/`ebb`/`slack`/`unknown`.

- [ ] **Step 1: Write the failing test**

Append to `SlackwaterTests/ColourAndFormTests.swift`:

```swift
    func testPinFeaturesCarryStateAndBothLayersShareOneColourExpression() throws {
        let source = try String(contentsOfFile: mapScreenPath(), encoding: .utf8)
        // Every pin feature must declare a state, defaulting to unknown.
        XCTAssertTrue(source.contains("\"state\""), "pin features must carry a state property")
        // Colour must be matched against state, never kind.
        XCTAssertNotNil(source.range(of: #"\["get", "state"\]"#, options: .regularExpression),
                        "colour must be driven by state")
        XCTAssertNil(source.range(of: #"(circle-color|icon-color)[^\n]*\["get", "kind"\]"#,
                                  options: .regularExpression),
                     "colour must never be matched against kind")
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/test.sh`
Expected: FAIL — pin features carry no `state`.

- [ ] **Step 3: Resolve a tone per station**

Add to `MapScreen.swift`, above `pinFeatures()`:

```swift
/// A station's state as a tone name, for the pin's colour.
///
/// Synchronous only. Bundled stations predict on device from their own
/// harmonics; CHS readings live behind an async cache, so they report
/// "unknown" and draw neutral — an honest admission, not a guess. On a boat a
/// wrong slack is worse than an admitted grey. Wiring the async CHS cache in is
/// a follow-on, deliberately not done here.
private func pinTone(_ item: StationItem, at now: Date) -> String {
    switch item {
    case .tide(let record):
        guard let s = record.cardState(at: now) else { return "unknown" }
        return s.rising ? "rising" : "falling"
    case .current(let station):
        return phaseName(station.cardState(at: now).phase)
    case .chsGate(let gate):
        return phaseName(gate.cardState(at: now).phase)
    case .chs, .chsCurrent:
        return "unknown"   // async cache — see the follow-on above
    }
}
```

Match `phaseName` to whatever the phase enum is actually called in this codebase — check `CurrentCardState` and `DerivedGateCardState` before writing it, and map the three cases to `"flood"`, `"ebb"`, `"slack"`. If `cardState(at:)` is not optional for a given type, drop the `guard`.

Then add the property in `pinFeatures()`, alongside the existing `kind`:

```swift
                "state": pinTone(s, at: appNow()),
```

- [ ] **Step 4: Drive both layers' colour from it**

Replace `PIN_NEUTRAL` in **both** layers from Task 4 with the same expression — literally the same, so kind cannot influence it:

```swift
private let PIN_STATE_COLOUR: [Any] = [
    "match", ["get", "state"],
    "rising", "#4a9fd8", "flood", "#4a9fd8",
    "falling", "#e8a33d", "ebb", "#e8a33d",
    "slack", "#88b868",
    "#7d9cb8",   // unknown
]
```

`circle-color` on the current layer and `icon-color` on the tide layer both take `PIN_STATE_COLOUR`. The cluster layer keeps `PIN_NEUTRAL` — an aggregate has no state.

Hex literals rather than `SN` tokens because these go into a MapLibre style dictionary, which takes strings and cannot read Swift `Color`s. Keep them in step with `Theme.swift` by hand; the Task 4 test guards the retired values from returning.

- [ ] **Step 5: Run the tests**

Run: `./scripts/test.sh`
Expected: PASS.

- [ ] **Step 6: Verify on a simulator**

Build and run, open the map, and confirm:

1. Bundled US stations take on colour — blue rising/flooding, amber falling/ebbing, green at slack.
2. Canadian CHS stations draw neutral grey.
3. Circles and squares still read as equal weight now that they carry colour.
4. Tapping each kind still selects the station.

Report what you observed. A map where *every* pin is grey means `pinTone` is returning `"unknown"` for everything — report that rather than working around it.

- [ ] **Step 7: Commit**

Verify the branch, then:

```bash
git add Slackwater/MapScreen.swift SlackwaterTests/ColourAndFormTests.swift
git commit -m "feat(map): pin colour carries water state

Bundled stations resolve on device; CHS stays neutral until the async
cache read lands, which is an honest unknown rather than a guess. Both
pin layers share one colour expression, so colour cannot track kind."
```

---

## Verification

```bash
./scripts/test.sh          # fast plan, both reference simulators
```

Then the simulator checks from Task 4 Step 8 and Task 5 Step 6, which are the only evidence the map works.

Open a PR per `CONTRIBUTING.md`. **Do not merge it** — that is a human decision.
