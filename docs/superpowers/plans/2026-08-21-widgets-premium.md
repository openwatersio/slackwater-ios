# Widgets + Premium Debut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship free home-screen widgets, Premium lock-screen (accessory) widgets, and the Slackwater Premium StoreKit tier, per `docs/superpowers/specs/2026-08-21-widgets-premium-design.md`.

**Architecture:** A new WidgetKit extension target compiles the app's existing station-model files plus two new pure units (`WidgetStationLoader`, `WidgetSnapshot`) against the `TideEngine` package — fully offline, deterministic timelines. An App Group moves favorites/recents and CHS fitted models into shared storage the widget can read. StoreKit 2 (`PremiumStore`) caches the entitlement into shared defaults; accessory widgets read that flag and render a quiet locked state without it.

**Tech Stack:** Swift/SwiftUI, WidgetKit + AppIntents, StoreKit 2, XcodeGen, XCTest, `TideEngine` SPM package (`from: 0.4.0`).

## Global Constraints

- Deployment target **iOS 26.0** (project-wide `options.deploymentTarget`); new targets inherit it.
- The Xcode project is **generated** — edit `project.yml` only, never `Slackwater.xcodeproj` (regenerate with `xcodegen generate`; `./scripts/test.sh` runs it for you).
- Tests: `./scripts/test.sh` (fast) / `./scripts/test.sh --full` before an upload. **Never run a bare `xcodebuild build` while a test run is in flight** — the script's lock comment warns it swaps `Slackwater.app` under live UI tests. To just check compilation, wait for the lock or run `./scripts/test.sh`.
- Every source file starts with the repo's header-comment style: `// Slackwater — GPL v3. <one-line purpose>`.
- App Group id: `group.org.openwaters.slackwater`. Widget bundle id: `org.openwaters.slackwater.widgets`. Product ids: `org.openwaters.slackwater.premium.yearly`, `org.openwaters.slackwater.premium.lifetime`.
- Shared-defaults keys (exact): favorites `slackwater.favorites`, recents `slackwater.recents`, premium flag `slackwater.premium`, migration marker `slackwater.appgroup.migrated`.
- Copy rules (spec §3, §5): the tier sheet leads with "Everything you use today stays free, forever…"; locked widget shows a wave glyph + "Premium" — no data, no exclamation marks, no urgency language anywhere. Upsell surfaces are ONLY: Settings row, Widgets gallery page, locked-widget tap-through.
- Slack-window threshold everywhere: **0.5 kn** (matches `speedRampAnchorsKn[0]`).
- TDD: each logic task writes its failing test first. View-only tasks verify by building + simulator screenshot instead.
- `TimelineData.slackWindows` is a tuple array (not Codable) — widget code builds its own value types; never try to serialize app tuples.
- Commit after every task (branch `widgets-premium-spec`, worktree `slackwater-ios-wt-widgets`); trailer lines per workspace CLAUDE.md.

---

### Task 1: App Group foundation — shared defaults + storage migration

**Files:**
- Create: `Slackwater/AppGroup.swift`
- Create: `Slackwater/Slackwater.entitlements`
- Modify: `project.yml` (app target settings: `CODE_SIGN_ENTITLEMENTS`)
- Modify: `Slackwater/Theme.swift` (FavoritesStore ~line 845, RecentsStore ~line 795: every `UserDefaults.standard` → `AppGroup.defaults`)
- Modify: `Slackwater/ChsStation.swift:80-110` (`ChsModelStore.dir` → App Group container + one-time move)
- Test: `SlackwaterTests/AppGroupTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `enum AppGroup { static let id: String; static let defaults: UserDefaults; static var container: URL; static func migrateIfNeeded(into: UserDefaults, from: UserDefaults) }` — every later task reads favorites and the premium flag through `AppGroup.defaults`.

- [ ] **Step 1: Write the failing test**

```swift
// Slackwater — GPL v3. App Group migration: standard-defaults state moves to
// the shared suite exactly once; the shared container hosts ChsModels.
import XCTest
@testable import Slackwater

final class AppGroupTests: XCTestCase {
    func testMigrationCopiesOnce() {
        let from = UserDefaults(suiteName: "test.from")!
        let into = UserDefaults(suiteName: "test.into")!
        defer {
            from.removePersistentDomain(forName: "test.from")
            into.removePersistentDomain(forName: "test.into")
        }
        from.set(["a", "b"], forKey: "slackwater.favorites")
        from.set(["c"], forKey: "slackwater.recents")

        AppGroup.migrateIfNeeded(into: into, from: from)
        XCTAssertEqual(into.stringArray(forKey: "slackwater.favorites"), ["a", "b"])
        XCTAssertEqual(into.stringArray(forKey: "slackwater.recents"), ["c"])

        // A second run must not clobber post-migration edits.
        into.set(["z"], forKey: "slackwater.favorites")
        from.set(["stale"], forKey: "slackwater.favorites")
        AppGroup.migrateIfNeeded(into: into, from: from)
        XCTAssertEqual(into.stringArray(forKey: "slackwater.favorites"), ["z"])
    }

    func testChsModelsDirLivesInSharedContainer() {
        XCTAssert(ChsModelStore.dir.path.hasSuffix("ChsModels"))
        XCTAssertEqual(ChsModelStore.dir.deletingLastPathComponent().path,
                       AppGroup.container.path)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `./scripts/test.sh` → FAIL: `AppGroup` not defined.

- [ ] **Step 3: Implement**

`Slackwater/AppGroup.swift`:

```swift
// Slackwater — GPL v3. The App Group shared by the app and the widget
// extension: shared UserDefaults (favorites, recents, premium flag) and the
// shared container (CHS fitted models). One-time migration from the
// pre-widget standard-defaults/App-Support locations.
import Foundation

enum AppGroup {
    static let id = "group.org.openwaters.slackwater"

    static let defaults: UserDefaults = {
        let d = UserDefaults(suiteName: id) ?? .standard
        migrateIfNeeded(into: d, from: .standard)
        return d
    }()

    /// Shared container; falls back to App Support so unit tests (no
    /// provisioned group) still get a real directory.
    static var container: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask)[0]
    }

    private static let migratedKey = "slackwater.appgroup.migrated"

    static func migrateIfNeeded(into d: UserDefaults, from standard: UserDefaults) {
        guard !d.bool(forKey: migratedKey) else { return }
        for key in ["slackwater.favorites", "slackwater.recents"] {
            if d.object(forKey: key) == nil, let v = standard.stringArray(forKey: key) {
                d.set(v, forKey: key)
            }
        }
        d.set(true, forKey: migratedKey)
    }
}
```

`Slackwater/Slackwater.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.org.openwaters.slackwater</string>
	</array>
</dict>
</plist>
```

`project.yml` — in the `Slackwater` target's `settings.base`, add:

```yaml
        CODE_SIGN_ENTITLEMENTS: Slackwater/Slackwater.entitlements
```

`Slackwater/Theme.swift` — in `FavoritesStore` and `RecentsStore`, replace every `UserDefaults.standard` with `AppGroup.defaults` (init reads, all `set` calls, and the `-resetRecents`/`-resetFavorites`/`-seedFavorites` UI-test hooks — the hooks must hit the same suite the stores read).

`Slackwater/ChsStation.swift` — replace `ChsModelStore.dir` with:

```swift
    static let dir: URL = {
        let dest = AppGroup.container.appendingPathComponent("ChsModels", isDirectory: true)
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask)[0]
            .appendingPathComponent("ChsModels", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dest.path), fm.fileExists(atPath: legacy.path) {
            try? fm.createDirectory(at: dest.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            try? fm.moveItem(at: legacy, to: dest)
        }
        return dest
    }()
```

(`ChsChunkStore` stays where it is — the widget never fits, and chunks are purged post-fit.)

- [ ] **Step 4: Run tests** — `./scripts/test.sh` → all pass (existing favorites/recents/CHS suites prove the swap broke nothing; simulator UI tests exercise the seeded-favorites hooks against the suite).

- [ ] **Step 5: Commit** — `git add Slackwater/AppGroup.swift Slackwater/Slackwater.entitlements project.yml Slackwater/Theme.swift Slackwater/ChsStation.swift SlackwaterTests/AppGroupTests.swift && git commit -m "feat: App Group — shared defaults + CHS model container, one-time migration"`

---

### Task 2: Hoist `slackWindow` into its own file + direct unit test

**Files:**
- Create: `Slackwater/SlackWindow.swift`
- Modify: `Slackwater/TimelineStrip.swift:167-198` (delete the function there; nothing else changes — it is already a free function, same name/signature, all callers unaffected)
- Test: `SlackwaterTests/SlackWindowTests.swift`

**Interfaces:**
- Produces: `func slackWindow(_ points: [CurrentPoint], around slack: Date, threshold: Double) -> (start: Date, end: Date)?` — unchanged signature, now in a file the widget target can compile.

- [ ] **Step 1: Write the failing-first test** (fails only after the move if the move breaks something; write it now so the unit finally has direct coverage)

```swift
// Slackwater — GPL v3. Direct tests for slackWindow (SlackWindow.swift):
// interpolated sub-threshold span, clamping, and the no-window cases.
import XCTest
@testable import Slackwater
import TideEngine

final class SlackWindowTests: XCTestCase {
    /// Symmetric V through zero: -1 kn at t0, 0 at t0+600, +1 at t0+1200.
    /// Threshold 0.5 crosses halfway down each leg.
    func testInterpolatedWindow() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = [CurrentPoint(time: t0, speed: -1),
                   CurrentPoint(time: t0.addingTimeInterval(600), speed: 0),
                   CurrentPoint(time: t0.addingTimeInterval(1200), speed: 1)]
        let w = slackWindow(pts, around: t0.addingTimeInterval(600), threshold: 0.5)!
        XCTAssertEqual(w.start.timeIntervalSince(t0), 300, accuracy: 1)
        XCTAssertEqual(w.end.timeIntervalSince(t0), 900, accuracy: 1)
    }

    func testSlackOutsideSeriesHasNoWindow() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = [CurrentPoint(time: t0, speed: -1),
                   CurrentPoint(time: t0.addingTimeInterval(600), speed: 1)]
        XCTAssertNil(slackWindow(pts, around: t0.addingTimeInterval(7200), threshold: 0.5))
    }

    func testNeverSubThresholdHasNoWindow() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = (0..<5).map { CurrentPoint(time: t0.addingTimeInterval(Double($0) * 600),
                                             speed: 2.0) }
        XCTAssertNil(slackWindow(pts, around: t0.addingTimeInterval(1200), threshold: 0.5))
    }
}
```

- [ ] **Step 2: Run** — `./scripts/test.sh` → these pass already (function exists); that's fine — this task's risk is the *move*, and the tests guard it.

- [ ] **Step 3: Move the function.** Create `Slackwater/SlackWindow.swift` with header `// Slackwater — GPL v3. The workable sub-threshold window around a slack — shared by the timeline strip and the widget extension.`, `import Foundation` + `import TideEngine`, and the `slackWindow` function cut verbatim from `TimelineStrip.swift:167-198` (keep its doc comment). Delete it from `TimelineStrip.swift`. Leave `suppressesSlackLabel` where it is (strip-only concern).

- [ ] **Step 4: Run tests** — `./scripts/test.sh` → all pass (TimelineTests cover the strip's window consumers).

- [ ] **Step 5: Commit** — `git add Slackwater/SlackWindow.swift Slackwater/TimelineStrip.swift SlackwaterTests/SlackWindowTests.swift && git commit -m "refactor: hoist slackWindow into SlackWindow.swift for the widget target"`

---

### Task 3: `WidgetStationLoader` — station id → engine-ready station, app-free

**Files:**
- Create: `Slackwater/WidgetStationLoader.swift`
- Test: `SlackwaterTests/WidgetStationLoaderTests.swift`

**Interfaces:**
- Consumes: `StationItem.byId` (`CurrentStation.swift`), `TideStationRecord.engineStation` (`TideStation.swift:19`), `CurrentStationRecord.engineStation` (`CurrentStation.swift:76`), `ChsModelStore.load` (`ChsStation.swift`), `ChsStationInfo.record(with:)` (`ChsStation.swift:115`).
- Produces:

```swift
enum WidgetStation {
    case tide(Station, tz: TimeZone, name: String)
    case current(CurrentStation, tz: TimeZone, name: String)
    case derived(DerivedSlackStation, tz: TimeZone, name: String)
}
enum WidgetStationLoader {
    /// nil = unknown id OR a CHS station whose model isn't fitted yet
    /// (widget renders "Open Slackwater to prepare this station").
    static func load(id: String) -> WidgetStation?
    /// First favorite, else most-recent, else Friday Harbor — the widget's
    /// default when unconfigured.
    static func defaultStationID() -> String
}
```

- [ ] **Step 1: Write the failing test**

```swift
// Slackwater — GPL v3. WidgetStationLoader: id → engine-ready station for the
// widget process — bundled NOAA directly, CHS via the shared fitted-model
// store, nil when unfitted.
import XCTest
@testable import Slackwater
import TideEngine

final class WidgetStationLoaderTests: XCTestCase {
    func testBundledTideStationLoads() {
        let st = WidgetStationLoader.load(id: TideStationRecord.fridayHarborID)
        guard case .tide(let s, let tz, let name)? = st else {
            return XCTFail("expected .tide, got \(String(describing: st))")
        }
        XCTAssertFalse(s.extremes(from: .now, to: .now.addingTimeInterval(86_400)).isEmpty)
        XCTAssertEqual(tz.identifier, "America/Los_Angeles")
        XCTAssert(name.contains("Friday Harbor"))
    }

    func testBundledCurrentStationLoads() {
        // Any bundled NOAA current station; take the first from the catalog.
        let record = CurrentStationRecord.all.first!
        guard case .current(let s, _, _)? =
                WidgetStationLoader.load(id: "current:" + record.id) else {
            return XCTFail("expected .current")
        }
        XCTAssertFalse(s.events(from: .now, to: .now.addingTimeInterval(86_400)).isEmpty)
    }

    func testUnknownIdIsNil() {
        XCTAssertNil(WidgetStationLoader.load(id: "nope:missing"))
    }

    func testDefaultFollowsFavorites() {
        let d = AppGroup.defaults
        let saved = d.stringArray(forKey: "slackwater.favorites")
        defer { d.set(saved, forKey: "slackwater.favorites") }
        d.set([TideStationRecord.fridayHarborID], forKey: "slackwater.favorites")
        XCTAssertEqual(WidgetStationLoader.defaultStationID(), TideStationRecord.fridayHarborID)
    }
}
```

(If `fridayHarborID`'s tz differs, copy the actual value from `stations.json` — assert what the catalog says, don't weaken the assert.)

- [ ] **Step 2: Run** — FAIL: `WidgetStationLoader` not defined.

- [ ] **Step 3: Implement** `Slackwater/WidgetStationLoader.swift`:

```swift
// Slackwater — GPL v3. Station id → engine-ready station for the widget
// process. Bundled NOAA records directly; CHS stations/gates only via their
// fitted models in the shared ChsModelStore — the widget NEVER fits, never
// touches the network, never instantiates ChsFitService.
import Foundation
import TideEngine

enum WidgetStation {
    case tide(Station, tz: TimeZone, name: String)
    case current(CurrentStation, tz: TimeZone, name: String)
    case derived(DerivedSlackStation, tz: TimeZone, name: String)
}

enum WidgetStationLoader {
    static func load(id: String) -> WidgetStation? {
        guard let item = StationItem.byId[id] else { return nil }
        switch item {
        case .tide(let r):
            return .tide(r.engineStation, tz: r.tz, name: r.name)
        case .current(let r):
            return .current(r.engineStation, tz: r.tz, name: r.name)
        case .chs(let info):
            guard let model = ChsModelStore.load(info.id) else { return nil }
            let r = info.record(with: model)
            return .tide(r.engineStation, tz: r.tz, name: r.name)
        case .chsGate(let gate):
            // Mirror the construction at ChsGate.swift:41 — reference port's
            // fitted model → DerivedSlackStation(hwLag/lwLag). Copy the exact
            // property names from that file; nil when the port isn't fitted.
            return derivedStation(for: gate)
        case .chsCurrent(let info):
            // Mirror the fitted-current path in ChsCurrentGate.swift — the
            // "-current" suffixed model in ChsModelStore → CurrentStationRecord.
            guard let r = fittedCurrentRecord(for: info) else { return nil }
            return .current(r.engineStation, tz: r.tz, name: r.name)
        }
    }

    static func defaultStationID() -> String {
        AppGroup.defaults.stringArray(forKey: "slackwater.favorites")?.first
            ?? AppGroup.defaults.stringArray(forKey: "slackwater.recents")?.first
            ?? TideStationRecord.fridayHarborID
    }
}
```

The two private helpers (`derivedStation(for:)`, `fittedCurrentRecord(for:)`) transcribe the existing detail-view constructions — read `ChsGate.swift` and `ChsCurrentGate.swift` first and reuse their exact accessors; the point of this task is that the widget resolves stations through the *same* records the app renders. If a construction turns out to require `ChsFitService` state that only exists in-app (not in `ChsModelStore`), return nil for that case and note it in the commit message — the widget shows its "open the app" placeholder.

- [ ] **Step 4: Run tests** — `./scripts/test.sh` → PASS.

- [ ] **Step 5: Commit** — `git add Slackwater/WidgetStationLoader.swift SlackwaterTests/WidgetStationLoaderTests.swift && git commit -m "feat: WidgetStationLoader — id to engine station, shared-container CHS models"`

---

### Task 4: `WidgetSnapshot` — one render-ready value per timeline entry

**Files:**
- Create: `Slackwater/WidgetSnapshot.swift`
- Test: `SlackwaterTests/WidgetSnapshotTests.swift`

**Interfaces:**
- Consumes: `WidgetStation` (Task 3), `slackWindow` (Task 2), engine `heights/extremes/speeds/events/slacks`.
- Produces:

```swift
struct WidgetSnapshot: Equatable {
    struct Event: Equatable {
        let time: Date
        let label: String     // "Slack" / "Max flood 3.1 kn" / "High 2.4 m" …
        let symbol: String    // SF Symbol name
    }
    let stationName: String
    let tz: TimeZone
    let next: Event?                       // nil only for the unfitted placeholder
    let window: (start: Date, end: Date)?  // slack window, current stations only
    let sparkline: [Double]                // today 00:00–24:00 normalized 0…1, 97 samples
    let nowFraction: Double                // 0…1 position of `now` in today
    static func build(_ station: WidgetStation, now: Date) -> WidgetSnapshot
}
```

(`Equatable` manually for the tuple member — compare start/end.)

- [ ] **Step 1: Write the failing test**

```swift
// Slackwater — GPL v3. WidgetSnapshot: next event, slack window, and a
// normalized day-curve — deterministic given (station, now).
import XCTest
@testable import Slackwater
import TideEngine

final class WidgetSnapshotTests: XCTestCase {
    var friday: WidgetStation { WidgetStationLoader.load(id: TideStationRecord.fridayHarborID)! }
    var current: WidgetStation {
        WidgetStationLoader.load(id: "current:" + CurrentStationRecord.all.first!.id)!
    }

    func testTideNextEventIsFuture() {
        let now = Date()
        let s = WidgetSnapshot.build(friday, now: now)
        XCTAssertNotNil(s.next)
        XCTAssert(s.next!.time > now)
        XCTAssert(s.next!.label.hasPrefix("High") || s.next!.label.hasPrefix("Low"))
    }

    func testCurrentNextEventAndWindow() {
        let s = WidgetSnapshot.build(current, now: Date())
        XCTAssertNotNil(s.next)
        // A slack inside the sampled day gets its 0.5 kn window attached.
        if s.next!.label == "Slack" { XCTAssertNotNil(s.window) }
    }

    func testSparklineShape() {
        let s = WidgetSnapshot.build(friday, now: Date())
        XCTAssertEqual(s.sparkline.count, 97)
        XCTAssert(s.sparkline.allSatisfy { (0.0...1.0).contains($0) })
        XCTAssert((0.0...1.0).contains(s.nowFraction))
    }

    func testDeterministic() {
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        XCTAssertEqual(WidgetSnapshot.build(friday, now: now),
                       WidgetSnapshot.build(friday, now: now))
    }
}
```

- [ ] **Step 2: Run** — FAIL: `WidgetSnapshot` not defined.

- [ ] **Step 3: Implement** `Slackwater/WidgetSnapshot.swift`:

```swift
// Slackwater — GPL v3. The render-ready value a widget entry carries: next
// event, its slack window, and today's normalized curve. Pure function of
// (station, now) — deterministic, offline, engine-only.
import Foundation
import TideEngine

struct WidgetSnapshot: Equatable {
    struct Event: Equatable {
        let time: Date
        let label: String
        let symbol: String
    }
    let stationName: String
    let tz: TimeZone
    let next: Event?
    let window: (start: Date, end: Date)?
    let sparkline: [Double]
    let nowFraction: Double

    static func == (a: Self, b: Self) -> Bool {
        a.stationName == b.stationName && a.tz == b.tz && a.next == b.next
            && a.window?.start == b.window?.start && a.window?.end == b.window?.end
            && a.sparkline == b.sparkline && a.nowFraction == b.nowFraction
    }

    static let threshold = 0.5  // kn — speedRampAnchorsKn[0], the app's window bar

    static func build(_ station: WidgetStation, now: Date) -> WidgetSnapshot {
        var cal = Calendar(identifier: .gregorian)
        let tz: TimeZone
        switch station {
        case .tide(_, let z, _), .current(_, let z, _), .derived(_, let z, _): tz = z
        }
        cal.timeZone = tz
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        let nowFraction = min(1, max(0, now.timeIntervalSince(dayStart) / 86_400))

        func normalize(_ values: [Double]) -> [Double] {
            guard let lo = values.min(), let hi = values.max(), hi > lo else {
                return values.map { _ in 0.5 }
            }
            return values.map { ($0 - lo) / (hi - lo) }
        }

        switch station {
        case .tide(let s, _, let name):
            let heights = s.heights(from: dayStart, to: dayEnd, step: 900).map(\.height)
            let ext = s.extremes(from: now, to: now.addingTimeInterval(172_800))
                .first { $0.time > now }
            let next = ext.map {
                Event(time: $0.time,
                      label: ($0.kind == .high ? "High" : "Low")
                          + String(format: " %.1f m", $0.height),
                      symbol: $0.kind == .high ? "arrow.up" : "arrow.down")
            }
            return .init(stationName: name, tz: tz, next: next, window: nil,
                         sparkline: normalize(heights), nowFraction: nowFraction)

        case .current(let s, _, let name):
            let pts = s.speeds(from: dayStart, to: dayEnd, step: 900)
            let ev = s.events(from: now, to: now.addingTimeInterval(172_800))
                .first { $0.time > now }
            var window: (Date, Date)?
            if let ev, ev.kind == .slack {
                let windowPts = s.speeds(from: ev.time.addingTimeInterval(-21_600),
                                         to: ev.time.addingTimeInterval(21_600))
                window = slackWindow(windowPts, around: ev.time, threshold: threshold)
            }
            let next = ev.map {
                switch $0.kind {
                case .slack: Event(time: $0.time, label: "Slack", symbol: "minus")
                case .maxFlood: Event(time: $0.time,
                                      label: String(format: "Max flood %.1f kn", abs($0.speed)),
                                      symbol: "arrow.up.right")
                case .maxEbb: Event(time: $0.time,
                                    label: String(format: "Max ebb %.1f kn", abs($0.speed)),
                                    symbol: "arrow.down.right")
                }
            }
            return .init(stationName: name, tz: tz, next: next, window: window,
                         sparkline: normalize(pts.map { abs($0.speed) }),
                         nowFraction: nowFraction)

        case .derived(let s, _, let name):
            let slacks = s.slacks(from: dayStart, to: now.addingTimeInterval(172_800))
            let nextSlack = slacks.first { $0.time > now }
            let next = nextSlack.map {
                Event(time: $0.time, label: "Slack", symbol: "minus")
            }
            let samples = stride(from: 0, through: 96, by: 1).map {
                abs(s.schematicSigned(at: dayStart.addingTimeInterval(Double($0) * 900),
                                      slacks: slacks))
            }
            // No window for a derived gate — a window measured off a schematic
            // shape would be fiction (TimelineData precedent).
            return .init(stationName: name, tz: tz, next: next, window: nil,
                         sparkline: normalize(samples), nowFraction: nowFraction)
        }
    }
}
```

(Unit display: the widget views format meters/feet per the app's `unitsKey` `@AppStorage` — that key also moves through `AppGroup.defaults` reads in the views, Task 5. If label formatting with units in `build` proves cleaner, pass the units string in; keep it a pure input either way.)

- [ ] **Step 4: Run tests** — `./scripts/test.sh` → PASS.

- [ ] **Step 5: Commit** — `git add Slackwater/WidgetSnapshot.swift SlackwaterTests/WidgetSnapshotTests.swift && git commit -m "feat: WidgetSnapshot — deterministic render value for widget entries"`

---

### Task 5: Widget extension target + free home-screen widgets

**Files:**
- Modify: `project.yml` (new `SlackwaterWidgets` target; app embeds it)
- Create: `SlackwaterWidgets/SlackwaterWidgets.entitlements` (same app-group XML as Task 1)
- Create: `SlackwaterWidgets/SlackwaterWidgetsBundle.swift`
- Create: `SlackwaterWidgets/StationIntent.swift`
- Create: `SlackwaterWidgets/HomeWidgets.swift`

**Interfaces:**
- Consumes: `WidgetStationLoader`, `WidgetSnapshot`, `AppGroup` (Tasks 1/3/4).
- Produces: `SlackwaterEntry: TimelineEntry { date: Date; snapshot: WidgetSnapshot?; premium: Bool }`, `StationConfigIntent` (station parameter), `StationProvider` (AppIntentTimelineProvider) — Task 6 adds accessory widgets on the same provider.

- [ ] **Step 1: Add the target to `project.yml`**

```yaml
  SlackwaterWidgets:
    type: app-extension
    platform: iOS
    sources:
      - SlackwaterWidgets
      - path: Slackwater/Resources
      - Slackwater/AppGroup.swift
      - Slackwater/SlackWindow.swift
      - Slackwater/WidgetStationLoader.swift
      - Slackwater/WidgetSnapshot.swift
      - Slackwater/TideStation.swift
      - Slackwater/CurrentStation.swift
      - Slackwater/ChsStation.swift
      - Slackwater/ChsGate.swift
      - Slackwater/ChsCurrentGate.swift
    dependencies:
      - package: TideEngine
        product: TideEngine
    info:
      path: SlackwaterWidgets/Info.plist
      properties:
        CFBundleDisplayName: Slackwater
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: org.openwaters.slackwater.widgets
        CODE_SIGN_ENTITLEMENTS: SlackwaterWidgets/SlackwaterWidgets.entitlements
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: R3H8DPTV9C
        GENERATE_INFOPLIST_FILE: NO
        SKIP_INSTALL: YES
```

And in the `Slackwater` app target's `dependencies`, add:

```yaml
      - target: SlackwaterWidgets
        embed: true
```

The explicit `sources` file list is deliberate: the widget compiles exactly the model files it needs, no more. The first build will demand stragglers (e.g. wherever `StationIdentity`/`Con` helpers or `ChsFitService` references live) — add each demanded file to the list explicitly and record the final list in the commit message. If the transitive set balloons past ~a dozen files, stop and flag it in the PR instead of dragging the whole app in. **Do not** leave Release-signing overrides unset silently: Debug/simulator work runs on Automatic; the Release manual-profile story is Task 10's checklist.

- [ ] **Step 2: Station picker intent** — `SlackwaterWidgets/StationIntent.swift`:

```swift
// Slackwater — GPL v3. Widget configuration: pick a station. Choices come
// from Favorites then Recents (shared defaults); default is the first
// favorite — the widget works with zero configuration.
import AppIntents
import WidgetKit

struct StationChoice: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Station"
    static let defaultQuery = StationQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}

struct StationQuery: EntityQuery {
    private func choices() -> [StationChoice] {
        let d = AppGroup.defaults
        let ids = (d.stringArray(forKey: "slackwater.favorites") ?? [])
            + (d.stringArray(forKey: "slackwater.recents") ?? [])
        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted, let item = StationItem.byId[id] else { return nil }
            return StationChoice(id: id, name: item.name)
        }
    }
    func entities(for identifiers: [String]) async throws -> [StationChoice] {
        identifiers.compactMap { id in
            StationItem.byId[id].map { StationChoice(id: id, name: $0.name) }
        }
    }
    func suggestedEntities() async throws -> [StationChoice] { choices() }
    func defaultResult() async -> StationChoice? { choices().first }
}

struct StationConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Station"
    static let description = IntentDescription("Choose the station this widget shows.")
    @Parameter(title: "Station") var station: StationChoice?
}
```

- [ ] **Step 3: Provider + bundle + home widgets** — `SlackwaterWidgets/SlackwaterWidgetsBundle.swift`:

```swift
// Slackwater — GPL v3. Widget bundle + shared timeline provider. Entries are
// precomputed half-hourly for 24h — predictions are deterministic, so the
// timeline never needs network, background refresh, or luck.
import SwiftUI
import WidgetKit

struct SlackwaterEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?   // nil: unknown/unfitted station
    let premium: Bool
}

struct StationProvider: AppIntentTimelineProvider {
    private func entry(_ intent: StationConfigIntent, at date: Date) -> SlackwaterEntry {
        let id = intent.station?.id ?? WidgetStationLoader.defaultStationID()
        let snapshot = WidgetStationLoader.load(id: id)
            .map { WidgetSnapshot.build($0, now: date) }
        return SlackwaterEntry(date: date, snapshot: snapshot,
                               premium: AppGroup.defaults.bool(forKey: "slackwater.premium"))
    }
    func placeholder(in context: Context) -> SlackwaterEntry {
        entry(StationConfigIntent(), at: .now)
    }
    func snapshot(for intent: StationConfigIntent, in context: Context) async -> SlackwaterEntry {
        entry(intent, at: .now)
    }
    func timeline(for intent: StationConfigIntent, in context: Context) async -> Timeline<SlackwaterEntry> {
        let now = Date()
        let entries = stride(from: 0.0, to: 86_400, by: 1_800)
            .map { entry(intent, at: now.addingTimeInterval($0)) }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

@main
struct SlackwaterWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextEventWidget()
        DayCurveWidget()
    }
}
```

`SlackwaterWidgets/HomeWidgets.swift` — the two free widgets. Reuse the app's palette by adding `Slackwater/Theme.swift`'s color constants **only if** Theme.swift compiles standalone in the extension; otherwise define the three needed colors locally with a `// matches SN.<name>` comment (check `Theme.swift` first — don't fork the palette without looking):

```swift
// Slackwater — GPL v3. Free home-screen widgets: next event (small) and
// today's curve (medium). The 3-second test: station, curve, next slack —
// answered before the app opens.
import SwiftUI
import WidgetKit

struct NextEventWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextEvent", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            NextEventView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Next Event")
        .description("The next slack or tide turn at your station.")
        .supportedFamilies([.systemSmall])
    }
}

struct NextEventView: View {
    let entry: SlackwaterEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = entry.snapshot {
                Text(s.stationName).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                if let next = s.next {
                    Image(systemName: next.symbol).font(.title3)
                    Text(next.time, style: .time)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .environment(\.timeZone, s.tz)
                    Text(next.label).font(.caption).lineLimit(1)
                } else {
                    Text("—").font(.title)
                }
            } else {
                Text("Open Slackwater to prepare this station")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(deepLink(entry))
    }
}

struct DayCurveWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DayCurve", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            DayCurveView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today's Curve")
        .description("Today's tide or current curve, with the next event.")
        .supportedFamilies([.systemMedium])
    }
}

struct DayCurveView: View {
    let entry: SlackwaterEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = entry.snapshot {
                HStack {
                    Text(s.stationName).font(.caption).lineLimit(1)
                    Spacer()
                    if let next = s.next {
                        Image(systemName: next.symbol).font(.caption2)
                        Text(next.time, style: .time)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .environment(\.timeZone, s.tz)
                        Text(next.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                SparklineView(values: s.sparkline, nowFraction: s.nowFraction)
            } else {
                Text("Open Slackwater to prepare this station")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(deepLink(entry))
    }
}

struct SparklineView: View {
    let values: [Double]
    let nowFraction: Double
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Path { p in
                    for (i, v) in values.enumerated() {
                        let pt = CGPoint(x: w * CGFloat(i) / CGFloat(values.count - 1),
                                         y: h * (1 - CGFloat(v)))
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                }
                .stroke(.tint, lineWidth: 2)
                Rectangle().fill(.secondary).frame(width: 1)
                    .position(x: w * CGFloat(nowFraction), y: h / 2)
            }
        }
    }
}

func deepLink(_ entry: SlackwaterEntry) -> URL? {
    // Station route lands in Task 9; harmless until the app registers the scheme.
    guard entry.snapshot != nil else { return URL(string: "slackwater://station") }
    return URL(string: "slackwater://station")  // refined to carry the id in Task 9
}
```

- [ ] **Step 4: Build + fix stragglers** — `./scripts/test.sh` (regenerates the project and builds everything; expect straggler compile errors from the explicit source list — add the demanded files per Step 1's rule).

- [ ] **Step 5: Manual verification** — run the `Slackwater` scheme in the simulator, long-press home screen → add both Slackwater widgets, confirm: station name, plausible next event, curve with now-marker; then toggle a favorite in-app and confirm the widget picker's station list follows.

- [ ] **Step 6: Commit** — `git add project.yml SlackwaterWidgets SlackwaterTests && git commit -m "feat: widget extension — free home-screen widgets (next event + day curve)"`

---

### Task 6: Premium accessory widgets + locked state

**Files:**
- Create: `SlackwaterWidgets/AccessoryWidgets.swift`
- Modify: `SlackwaterWidgets/SlackwaterWidgetsBundle.swift` (add three widgets to the bundle)

**Interfaces:**
- Consumes: `SlackwaterEntry`, `StationProvider` (Task 5); `entry.premium` flag.
- Produces: widget kinds `"SlackInline"`, `"SlackCircular"`, `"SlackRectangular"` — Task 8's `PremiumStore` flips their content by writing `slackwater.premium`.

- [ ] **Step 1: Implement** `SlackwaterWidgets/AccessoryWidgets.swift`:

```swift
// Slackwater — GPL v3. Premium lock-screen widgets (spec §4). Without the
// entitlement they render the quiet locked state — wave glyph + "Premium",
// no data, no urgency. Tapping any of them opens the in-app Widgets page.
import SwiftUI
import WidgetKit

private struct Locked: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "water.waves")
            Text("Premium").font(.caption2)
        }
        .widgetURL(URL(string: "slackwater://premium"))
    }
}

struct SlackInlineWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SlackInline", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            if !entry.premium { Locked() }
            else if let s = entry.snapshot, let next = s.next {
                // e.g. "Slack 14:32 · Race Passage"
                Text("\(next.label) \(next.time.formatted(.dateTime.hour().minute())) · \(s.stationName)")
                    .environment(\.timeZone, s.tz)
            } else { Text("Open Slackwater") }
        }
        .configurationDisplayName("Next Slack")
        .description("The next event, above the clock.")
        .supportedFamilies([.accessoryInline])
    }
}

struct SlackCircularWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SlackCircular", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            ZStack {
                AccessoryWidgetBackground()
                if !entry.premium { Locked() }
                else if let s = entry.snapshot, let next = s.next {
                    VStack(spacing: 0) {
                        Image(systemName: next.symbol).font(.caption2)
                        Text(next.time, style: .time)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .environment(\.timeZone, s.tz)
                    }
                } else { Image(systemName: "water.waves") }
            }
        }
        .configurationDisplayName("Next Event")
        .description("Next slack or turn at a glance.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct SlackRectangularWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SlackRectangular", intent: StationConfigIntent.self,
                               provider: StationProvider()) { entry in
            if !entry.premium { Locked() }
            else if let s = entry.snapshot, let next = s.next {
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.stationName).font(.caption2).lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: next.symbol)
                        Text(next.time, style: .time).fontWeight(.semibold)
                            .environment(\.timeZone, s.tz)
                        Text(next.label).lineLimit(1)
                    }
                    .font(.caption)
                    if let w = s.window {
                        Text("window \(w.start.formatted(.dateTime.hour().minute()))–\(w.end.formatted(.dateTime.hour().minute()))")
                            .font(.caption2).foregroundStyle(.secondary)
                            .environment(\.timeZone, s.tz)
                    }
                }
            } else { Text("Open Slackwater") }
        }
        .configurationDisplayName("Slack Window")
        .description("Next event plus the workable window.")
        .supportedFamilies([.accessoryRectangular])
    }
}
```

In `SlackwaterWidgetsBundle.body` add `SlackInlineWidget(); SlackCircularWidget(); SlackRectangularWidget()`.

- [ ] **Step 2: Build** — `./scripts/test.sh` → green.

- [ ] **Step 3: Manual verification** — simulator: add all three to the lock screen. With `slackwater.premium` unset they must all show the wave + "Premium" state. Then `xcrun simctl spawn booted defaults write group.org.openwaters.slackwater slackwater.premium -bool YES` (or temporarily set it in app code), reload timelines (re-add a widget or relaunch), confirm real data renders, window line included on a current station. Unset again.

- [ ] **Step 4: Commit** — `git add SlackwaterWidgets && git commit -m "feat: Premium accessory widgets with quiet locked state"`

---

### Task 7: `PremiumStore` — StoreKit 2 tier + entitlement cache

**Files:**
- Create: `Slackwater/PremiumStore.swift`
- Create: `Slackwater.storekit` (repo root, referenced by scheme for local testing)
- Modify: `project.yml` (scheme `run.storeKitConfiguration: Slackwater.storekit`)
- Test: `SlackwaterTests/PremiumTests.swift`

**Interfaces:**
- Consumes: `AppGroup.defaults` (Task 1).
- Produces:

```swift
@MainActor final class PremiumStore: ObservableObject {
    static let shared = PremiumStore()
    static let yearlyID = "org.openwaters.slackwater.premium.yearly"
    static let lifetimeID = "org.openwaters.slackwater.premium.lifetime"
    @Published private(set) var isPremium: Bool
    @Published private(set) var products: [Product]   // loaded on demand
    static func isPremium(owned: Set<String>) -> Bool          // pure, tested
    static func cache(_ premium: Bool, into: UserDefaults)     // pure, tested
    func loadProducts() async
    func purchase(_ product: Product) async throws
    func restore() async                                       // AppStore.sync
    func refreshEntitlement() async
}
```

- [ ] **Step 1: Write the failing test**

```swift
// Slackwater — GPL v3. Premium entitlement derivation + shared-defaults cache
// — the part the widget's free/premium gate depends on.
import XCTest
@testable import Slackwater

final class PremiumTests: XCTestCase {
    func testEntitlementDerivation() {
        XCTAssertFalse(PremiumStore.isPremium(owned: []))
        XCTAssertFalse(PremiumStore.isPremium(owned: ["some.other.product"]))
        XCTAssertTrue(PremiumStore.isPremium(owned: [PremiumStore.yearlyID]))
        XCTAssertTrue(PremiumStore.isPremium(owned: [PremiumStore.lifetimeID]))
        XCTAssertTrue(PremiumStore.isPremium(owned: [PremiumStore.yearlyID,
                                                     PremiumStore.lifetimeID]))
    }

    func testCacheRoundtrip() {
        let d = UserDefaults(suiteName: "test.premium")!
        defer { d.removePersistentDomain(forName: "test.premium") }
        PremiumStore.cache(true, into: d)
        XCTAssertTrue(d.bool(forKey: "slackwater.premium"))
        PremiumStore.cache(false, into: d)
        XCTAssertFalse(d.bool(forKey: "slackwater.premium"))
    }
}
```

- [ ] **Step 2: Run** — FAIL: `PremiumStore` not defined.

- [ ] **Step 3: Implement** `Slackwater/PremiumStore.swift`:

```swift
// Slackwater — GPL v3. Slackwater Premium (spec §3): one tier, two SKUs —
// yearly + lifetime. StoreKit 2. The verified entitlement is cached into the
// App Group so the widget process can gate without touching StoreKit.
import Foundation
import StoreKit
import WidgetKit

@MainActor
final class PremiumStore: ObservableObject {
    static let shared = PremiumStore()
    static let yearlyID = "org.openwaters.slackwater.premium.yearly"
    static let lifetimeID = "org.openwaters.slackwater.premium.lifetime"
    private static let ids = [yearlyID, lifetimeID]
    static let premiumKey = "slackwater.premium"

    @Published private(set) var isPremium: Bool
    @Published private(set) var products: [Product] = []

    private var updatesTask: Task<Void, Never>?

    private init() {
        isPremium = AppGroup.defaults.bool(forKey: Self.premiumKey)
        updatesTask = Task { [weak self] in
            for await _ in Transaction.updates { await self?.refreshEntitlement() }
        }
        Task { await refreshEntitlement() }
    }

    static func isPremium(owned: Set<String>) -> Bool {
        !owned.isDisjoint(with: ids)
    }

    static func cache(_ premium: Bool, into defaults: UserDefaults) {
        defaults.set(premium, forKey: premiumKey)
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        products = ((try? await Product.products(for: Self.ids)) ?? [])
            .sorted { $0.price < $1.price }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        if case .success(let verification) = result,
           case .verified(let transaction) = verification {
            await transaction.finish()
            await refreshEntitlement()
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var owned = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil {
                owned.insert(t.productID)
            }
        }
        let premium = Self.isPremium(owned: owned)
        guard premium != isPremium || AppGroup.defaults.object(forKey: Self.premiumKey) == nil
        else { return }
        isPremium = premium
        Self.cache(premium, into: AppGroup.defaults)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
```

`Slackwater.storekit` (repo root — StoreKit configuration JSON for simulator testing; prices are the band's opening guesses, real prices set in ASC later):

```json
{
  "identifier" : "6D31BE8A-0000-4000-8000-5A6C6B770001",
  "nonRenewingSubscriptions" : [],
  "products" : [
    {
      "displayPrice" : "24.99",
      "familyShareable" : false,
      "internalID" : "6D31BE8A-0000-4000-8000-5A6C6B770002",
      "localizations" : [
        {
          "description" : "The lock screen, forever — and a thank-you.",
          "displayName" : "Premium Lifetime",
          "locale" : "en_US"
        }
      ],
      "productID" : "org.openwaters.slackwater.premium.lifetime",
      "referenceName" : "Premium Lifetime",
      "type" : "NonConsumable"
    }
  ],
  "settings" : { "_failTransactionsEnabled" : false },
  "subscriptionGroups" : [
    {
      "id" : "6D31BE8A-0000-4000-8000-5A6C6B770003",
      "localizations" : [],
      "name" : "Slackwater Premium",
      "subscriptions" : [
        {
          "adHocOffers" : [],
          "displayPrice" : "5.99",
          "familyShareable" : false,
          "groupNumber" : 1,
          "internalID" : "6D31BE8A-0000-4000-8000-5A6C6B770004",
          "localizations" : [
            {
              "description" : "The lock screen — and it funds development.",
              "displayName" : "Premium Yearly",
              "locale" : "en_US"
            }
          ],
          "productID" : "org.openwaters.slackwater.premium.yearly",
          "recurringSubscriptionPeriod" : "P1Y",
          "referenceName" : "Premium Yearly",
          "subscriptionGroupID" : "6D31BE8A-0000-4000-8000-5A6C6B770003",
          "type" : "RecurringSubscription"
        }
      ]
    }
  ],
  "version" : { "major" : 4, "minor" : 0 }
}
```

`project.yml` scheme block — under `schemes.Slackwater.run`, add:

```yaml
      storeKitConfiguration: Slackwater.storekit
```

(If xcodegen rejects the key name, check `xcodegen dump --type json` / the ProjectSpec docs for the current spelling — it has been `storeKitConfiguration` since xcodegen 2.25.)

- [ ] **Step 4: Run tests** — `./scripts/test.sh` → PASS.

- [ ] **Step 5: Commit** — `git add Slackwater/PremiumStore.swift Slackwater.storekit project.yml SlackwaterTests/PremiumTests.swift && git commit -m "feat: PremiumStore — StoreKit 2 tier, entitlement cached for the widget"`

---

### Task 8: Tier sheet (paywall) + Settings row

**Files:**
- Create: `Slackwater/PremiumView.swift`
- Modify: `Slackwater/SettingsView.swift` (one new `section`, after "Offline downloads")

**Interfaces:**
- Consumes: `PremiumStore` (Task 7); `SettingsView`'s local `section(_:content:)` helper and `SN` palette.
- Produces: `struct PremiumView: View` — presented as a sheet; Task 9's gallery links to it.

- [ ] **Step 1: Implement** `Slackwater/PremiumView.swift` (copy is the spec's §3 — verbatim tone, no urgency):

```swift
// Slackwater — GPL v3. The Slackwater Premium sheet (spec §3). Quiet by
// design: the free core is stated first, the ask is support, and there is no
// trial, discount, or countdown anywhere.
import StoreKit
import SwiftUI

struct PremiumView: View {
    @ObservedObject private var store = PremiumStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Everything you use today stays free, forever. Premium adds the lock screen — and it's how Slackwater's development gets funded. Buy it because you want it, or because you want to say thanks.")
                        .font(.callout)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Lock screen widgets — next slack, next turn, the workable window", systemImage: "lock.iphone")
                        Label("Coming to the same tier: the live slack tile, alerts, go-windows for your boat", systemImage: "arrow.forward.circle")
                    }
                    .font(.footnote)

                    if store.isPremium {
                        Label("You have Premium — thank you.", systemImage: "checkmark.seal")
                            .font(.callout.weight(.semibold))
                    } else {
                        ForEach(store.products, id: \.id) { product in
                            Button {
                                Task { try? await store.purchase(product) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(product.displayName).fontWeight(.semibold)
                                        if product.id == PremiumStore.lifetimeID {
                                            Text("Pay once, never again.").font(.caption2)
                                        }
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button("Restore purchase") { Task { await store.restore() } }
                            .font(.footnote)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Slackwater Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            } }
            .task { await store.loadProducts() }
        }
    }
}
```

Match the file's styling to `SettingsView.swift`'s `SN` palette usage (`.background(SN.page…)` etc.) when writing it — copy the exact modifiers SettingsView uses on its `ScrollView`.

- [ ] **Step 2: Settings row** — in `SettingsView.swift`, add `@State private var showPremium = false` beside the other properties, a section after "Offline downloads":

```swift
                    section("Slackwater Premium") {
                        Button { showPremium = true } label: {
                            HStack {
                                Text(PremiumStore.shared.isPremium
                                     ? "Premium — thank you for supporting the app"
                                     : "Support the app — lock screen widgets and more")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(SN.leaf)
                        }
                    }
```

and `.sheet(isPresented: $showPremium) { PremiumView() }` on the same view the other Settings modifiers hang from.

- [ ] **Step 3: Build + manual verification** — `./scripts/test.sh` green; in the simulator (scheme now loads `Slackwater.storekit`): Settings → row → sheet shows both SKUs with prices; buy the yearly (sandbox); sheet flips to the thank-you state; lock-screen widgets now render data (Task 6's flag flipped via `PremiumStore` → `WidgetCenter` reload). Screenshot the sheet for the PR.

- [ ] **Step 4: Commit** — `git add Slackwater/PremiumView.swift Slackwater/SettingsView.swift && git commit -m "feat: Premium tier sheet + quiet Settings row"`

---

### Task 9: Widgets gallery page + deep links

**Files:**
- Create: `Slackwater/WidgetsGalleryView.swift`
- Modify: `project.yml` (app `info.properties`: URL scheme)
- Modify: `Slackwater/SlackwaterApp.swift` (`StationListView`: gallery sheet state + `.onOpenURL` route)
- Modify: `Slackwater/SettingsView.swift` (gallery link line in the Premium section)
- Modify: `SlackwaterWidgets/HomeWidgets.swift` (`deepLink` carries the station id)

**Interfaces:**
- Consumes: `PremiumView` (Task 8), `StationItem.byId`, `StationListView`'s `open(_:)`/`path` plumbing and its documented sheet-environment-reforwarding gotcha (`SlackwaterApp.swift:426-434`).
- Produces: URL contract — `slackwater://station/<id>` opens that station's detail; `slackwater://premium` opens the Widgets gallery. The widget target already emits both.

- [ ] **Step 1: Register the scheme** — `project.yml`, app target `info.properties`:

```yaml
        CFBundleURLTypes:
          - CFBundleURLName: org.openwaters.slackwater
            CFBundleURLSchemes: [slackwater]
```

- [ ] **Step 2: Gallery view** — `Slackwater/WidgetsGalleryView.swift`:

```swift
// Slackwater — GPL v3. The in-app Widgets page (spec §5): every widget, free
// and Premium side by side, with add instructions. Doubles as the free
// widgets' discoverability surface; the only other pitch is the Settings row.
import SwiftUI

struct WidgetsGalleryView: View {
    @ObservedObject private var store = PremiumStore.shared
    @State private var showPremium = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    group("Home screen — free",
                          note: "Long-press your home screen → + → Slackwater.",
                          rows: [("Next Event", "square.grid.2x2",
                                  "The next slack or tide turn at your station."),
                                 ("Today's Curve", "waveform.path.ecg",
                                  "Today's curve with the next event.")])
                    group("Lock screen — Premium",
                          note: "Long-press your lock screen → Customize → add Slackwater above or below the clock.",
                          rows: [("Next Slack (inline)", "lock.iphone",
                                  "Above the clock: the next event and time."),
                                 ("Next Event (circular)", "circle.dashed",
                                  "A glance: arrow and time."),
                                 ("Slack Window (rectangular)", "rectangle.dashed",
                                  "Next event plus the workable window.")])
                    if !store.isPremium {
                        Button { showPremium = true } label: {
                            Text("About Slackwater Premium")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Widgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            } }
            .sheet(isPresented: $showPremium) { PremiumView() }
        }
    }

    private func group(_ title: String, note: String,
                       rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.1).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.0).font(.footnote.weight(.medium))
                        Text(row.2).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
```

(Style pass: mirror `SettingsView`'s `SN.page` background and section typography — copy its modifiers.)

- [ ] **Step 3: Routes** — in `StationListView` (`SlackwaterApp.swift`), add `@State private var showWidgetsGallery = false` beside `showSettings` (~line 295), a sheet beside the others (~line 435; no custom environment keys needed by the gallery, but keep the reforwarding gotcha in mind if it ever gains a station link):

```swift
        .sheet(isPresented: $showWidgetsGallery) { WidgetsGalleryView() }
        .onOpenURL { url in
            guard url.scheme == "slackwater" else { return }
            switch url.host {
            case "premium": showWidgetsGallery = true
            case "station":
                let id = url.pathComponents.dropFirst().first ?? ""
                if let item = StationItem.byId[id] { open(item) }
            default: break
            }
        }
```

(`open(_:)` is the existing chooser-sheet path — reuse it exactly; read its definition before wiring.) In `SettingsView`'s Premium section add a second line-button "Widgets — add them to your home and lock screen" presenting `WidgetsGalleryView` as a sheet (`@State private var showWidgets = false`).

- [ ] **Step 4: Widget side of the link** — in `SlackwaterWidgets/HomeWidgets.swift`, replace the `deepLink` stub: the provider puts the resolved station id into `SlackwaterEntry` (add `let stationID: String?` to the entry in `SlackwaterWidgetsBundle.swift`, set it in `entry(_:at:)`), and:

```swift
func deepLink(_ entry: SlackwaterEntry) -> URL? {
    guard let id = entry.stationID,
          let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    else { return URL(string: "slackwater://station") }
    return URL(string: "slackwater://station/\(encoded)")
}
```

(Station ids contain `:` — percent-encode, and mind `url.pathComponents` returns the decoded form.)

- [ ] **Step 5: Build + manual verification** — `./scripts/test.sh` green. Simulator: `xcrun simctl openurl booted "slackwater://premium"` opens the gallery; tapping the home widget opens its station's detail; tapping a locked accessory widget opens the gallery.

- [ ] **Step 6: Commit** — `git add project.yml Slackwater/WidgetsGalleryView.swift Slackwater/SlackwaterApp.swift Slackwater/SettingsView.swift SlackwaterWidgets && git commit -m "feat: Widgets gallery page + slackwater:// deep links"`

---

### Task 10: Full verification + release checklist

**Files:**
- Modify: `docs/release-notes/1.4.0.md` (create — short, user-voice, follows `docs/release-notes/1.3.0.md`'s format)
- No other code.

- [ ] **Step 1: Full suite** — `./scripts/test.sh --full` → all green on both simulators.

- [ ] **Step 2: End-to-end pass in the simulator** — fresh install (delete app first, so the App Group migration path runs from real pre-existing standard defaults: install the *previous* main build, star two favorites, then build this branch over it and confirm the stars survived into the widget picker). Add every widget family; buy yearly via the StoreKit config; confirm accessory widgets unlock; screenshot set for the PR (home small/medium, locked accessory, unlocked accessory, tier sheet, gallery).

- [ ] **Step 3: Draft `docs/release-notes/1.4.0.md`** — lead with free widgets, one quiet line for Premium, in the app's release-notes voice. (Version bump itself happens via the `releasing-to-testflight` skill at release time, not in this plan.)

- [ ] **Step 4: Commit + push branch** — plan checkboxes updated, PR description gains the screenshot set.

- [ ] **Step 5: Manual/ASC checklist (Bryan or asc.mjs, NOT automatable here; some items blocked):**
  1. Developer portal: register App Group `group.org.openwaters.slackwater`; add it to the `org.openwaters.slackwater` identifier; create identifier `org.openwaters.slackwater.widgets` with the group.
  2. Regenerate the pinned Release profile `"Slackwater App Store"` (it must now carry the group) and create `"Slackwater Widgets App Store"`; add the widget target's Release manual-signing block to `project.yml` mirroring the app's (same identity SHA-1, new specifier) — until then TestFlight uploads will fail signing, expected.
  3. ASC: create the subscription group "Slackwater Premium" + yearly sub + lifetime IAP with the two product ids, final prices from the band. **Blocked on the Open Waters seller-entity/revenue-split agreement (spec §8) — do not submit the paid tier before it's resolved.**
  4. TestFlight release: `releasing-to-testflight` skill as usual.

---

## Self-review notes

- Spec §4 free/premium widget sets, §5 surfaces, §6 technical shape, §7 scoping all map to Tasks 5/6, 8/9, 1–4/7, and the task boundaries respectively; §8 blockers land in Task 10's checklist. Live Activity, alerts, go-windows: correctly absent (spec §7/§9).
- Types cross-checked: `SlackwaterEntry` gains `stationID` in Task 9 (declared where consumed); `WidgetSnapshot.Event` names match between Tasks 4/5/6; `PremiumStore.premiumKey` = the constraint key list.
- Known unknowns called out in-task rather than hidden: straggler source files (Task 5 Step 1), CHS gate constructions (Task 3 Step 3), xcodegen StoreKit-config key (Task 7 Step 3) — each with a look-first instruction and a fallback.
