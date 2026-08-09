# Online Gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The 7 fit-reject CHS gates (Sechelt Rapids among them) become findable, honest, and — when connected — fully rendered from CHS's official predicted series, per `docs/superpowers/specs/2026-08-08-online-gates-design.md`.

**Architecture:** The rejects join `chs-current-gates.json` as `online: true` entries and stay `StationItem.chsCurrent` (search/map/lists inherit). A fetched 7.5-day window of official 15-min predictions persists per-gate beside the fit models; a sample-scan derives slack/max events; `TimelineData` grows an online-points path; `ChsDetailView` routes online gates to a new `OnlineGateDetailView` (fetched → normal single-track detail; unfetched/expired → honesty card). The fit queue skips them.

**Tech Stack:** SwiftUI, TideEngine point types, the existing IWLS fetcher inside `ChsFitService`, XcodeGen, XCTest/XCUITest.

## Global Constraints

- Branch `feature/online-gates` (off main at `a6f953c`). Branch-and-PR; never merge own PR.
- **PR #31 overlap:** `fix/chs-favorite-ids` (open PR) touches `ChsDetailView.swift:62` (`favoriteId:` prefix). This plan's routing task must NOT touch that argument. If #31 merges before Task 5 starts, rebase onto main first and use the bare `gate.id` it introduces there.
- Licensing posture (file header of `ChsCurrentGate.swift`): nothing CHS-published ships in the app bundle — fetched data is per-user, kept local, never re-served. The bundled json may carry only OUR measured error text.
- Flood/ebb axis and IWLS station ids are NEVER bundled — resolved from IWLS at fetch time by position, exactly like the fit path (spec's "record IWLS ids in json" open item is resolved: don't).
- Unit-test iteration command (worktree root): `xcodegen generate && lockf /tmp/slackwater-test.lock xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater -testPlan Slackwater -only-testing:SlackwaterTests -destination "platform=iOS Simulator,name=iPhone 17" -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -25`. lockf mandatory (shared machine); waits are normal.
- Full suite gate before PR: `./scripts/test.sh` both sims, detached (`nohup`/background), 40–70 min. Live-network coverage goes in the **Full** plan only (`TestPlans/Slackwater-Full.xctestplan`).
- Canvas labels stay fixed-size; tap targets below the strip use `.onTapGesture`, never Button (iPad split column).
- Commit trailers on every commit:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` + the Claude-Session line used by this branch's spec commit.

---

### Task 1: Identity — the rejects enter the bundle as online gates

**Files:**
- Modify: `tools/gen-chs-gates.mjs` (the rejects comment block ~:100-112 becomes an `ONLINE` map; emission gains the online entries), `Slackwater/Resources/chs-current-gates.json` (regenerated), `Slackwater/ChsCurrentGate.swift:17-66` (`ChsCurrentGateInfo`)
- Test: `SlackwaterTests/ChsCurrentGateTests.swift`

**Interfaces:**
- Produces: `ChsCurrentGateInfo.online: Bool?` + `var isOnline: Bool { online ?? false }`, `onlineNote: String?` (plain-words measured error for the honesty card, e.g. "Slackwater's on-device model missed the published slacks here by up to ~40 minutes in testing, so it won't guess at Sechelt Rapids."). Online entries emit `fitDays: 0` (documented sentinel: never fitted; `offersProvisional` is naturally false). All 7 rejects present with registry name/region/position/aliases/tideReference; Sechelt carries alias `"skookumchuck"`.

- [ ] **Step 1: Write the failing tests**

Append to `ChsCurrentGateTests.swift`:

```swift
// MARK: - Online gates (fit-rejects backed by official CHS predictions)

/// The 7 validation rejects ship as online: true identities — findable,
/// never fitted, never provisional (online-gates spec §1).
func testOnlineGatesShipAndShippedGatesStayOffline() throws {
    let online = ChsCurrentGateInfo.all.filter(\.isOnline)
    XCTAssertEqual(online.count, 7, "the 7 fit-rejects ship as online gates")
    for g in online {
        XCTAssert(g.id.hasPrefix("chs-"))
        XCTAssertFalse(g.offersProvisional, "an online gate never offers a fast answer")
        XCTAssertNotNil(g.onlineNote, "\(g.id) needs its plain-words measured error")
    }
    // The 11 shipped gates are untouched: not online, still fittable.
    XCTAssertEqual(ChsCurrentGateInfo.all.filter { !$0.isOnline }.count, 11)
    XCTAssert(ChsCurrentGateInfo.all.first { $0.id == "chs-dodd-narrows" }?.isOnline == false)
}

/// The origin bug: Sechelt Rapids must be findable by name AND alias.
func testSecheltIsSearchable() throws {
    let sechelt = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.id == "chs-sechelt-rapids" })
    XCTAssert(sechelt.isOnline)
    for query in ["sechelt", "skookumchuck"] {
        XCTAssert(StationItem.search(query).contains { $0.id == sechelt.id },
                  "search '\(query)' did not find Sechelt Rapids")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

`-only-testing:SlackwaterTests/ChsCurrentGateTests`. Expected: FAIL — `isOnline`/`onlineNote` don't compile yet.

- [ ] **Step 3: Struct changes**

In `ChsCurrentGateInfo`: add `let online: Bool?` and `let onlineNote: String?` after `provisionalSlackMinutes`, plus:

```swift
    /// A fit-reject backed by official CHS predictions fetched on demand —
    /// never fitted, never queued (online-gates spec §1). Bundled entries
    /// without the key decode as offline (the 11 shipped gates).
    var isOnline: Bool { online ?? false }
```

- [ ] **Step 4: Generator changes**

In `tools/gen-chs-gates.mjs`: convert the rejects comment block into data — an `ONLINE` map keyed by registry id carrying the plain-words `onlineNote` (write each from the measured numbers already in the comment: sechelt ~40 min, gabriola/second-narrows/etc. their own). Emission: after the `currentGates` array, append registry entries in `ONLINE`, shaped like the shipped ones (name/region/aliases/lat/lon/timezone/tideReference from the registry) with `fitDays: 0`, `online: true`, `onlineNote`. Check the tool's header for how it locates the station-corrections registry input and run it to regenerate `Slackwater/Resources/chs-current-gates.json`; verify with `git diff` that the 11 shipped entries are byte-identical and exactly 7 new entries appear.

- [ ] **Step 5: Run to verify green, then commit**

Unit suite (not just ChsCurrentGateTests — `NationalScaleTests`/`UnitsAndGroupsTests` count stations). If a count assertion moves by exactly the 7 new entries, amend it with a comment naming this task; any other movement is a bug in your emission.

```bash
git add tools/gen-chs-gates.mjs Slackwater/Resources/chs-current-gates.json Slackwater/ChsCurrentGate.swift SlackwaterTests/ChsCurrentGateTests.swift  # + any amended count test
git commit  # "online-gates: the 7 fit-rejects ship as findable online identities"
```

---

### Task 2: sampleEvents — slack/max from a fetched series

**Files:**
- Modify: `Slackwater/TimelineStrip.swift` (file scope, near `slackWindow`)
- Test: `SlackwaterTests/TimelineTests.swift`

**Interfaces:**
- Produces: `func sampleEvents(_ points: [CurrentPoint]) -> [CurrentEvent]` — slacks at sign changes (time linearly interpolated to the zero crossing, speed 0), `.maxFlood`/`.maxEbb` at local extrema between slacks (the largest |sample| in each run, positive = flood). Task 4 feeds its output to `TimelineData`; Task 5's schedule and readouts consume the events.

- [ ] **Step 1: Failing tests**

Append to `TimelineTests.swift`:

```swift
/// Events scanned from a sampled series (online gates draw fetched points,
/// not a harmonic engine): slacks at interpolated zero crossings, one signed
/// maximum per run between them.
func testSampleEventsScanCrossingsAndExtrema() {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    // 2 → -2 → 2 over 3 h at 15-min samples: crossings at +1h and +2h... use
    // a triangle wave: v(i) = [2,1,0.5,-0.5,-1,-2,-1,-0.5,0.5,1,2] per 15 min.
    let vs: [Double] = [2, 1, 0.5, -0.5, -1, -2, -1, -0.5, 0.5, 1, 2]
    let pts = vs.enumerated().map { CurrentPoint(time: t0.addingTimeInterval(Double($0.offset) * 900), speed: $0.element) }
    let events = sampleEvents(pts)
    let slacks = events.filter { $0.kind == .slack }
    XCTAssertEqual(slacks.count, 2)
    // First crossing: between samples 2 (0.5) and 3 (-0.5) → halfway, 2250 s.
    XCTAssertEqual(slacks[0].time.timeIntervalSince(t0), 2250, accuracy: 1)
    XCTAssertEqual(slacks[1].time.timeIntervalSince(t0), 6750, accuracy: 1)
    let ebbs = events.filter { $0.kind == .maxEbb }
    XCTAssertEqual(ebbs.count, 1)
    XCTAssertEqual(ebbs[0].speed, -2, accuracy: 1e-9)
    XCTAssertEqual(ebbs[0].time.timeIntervalSince(t0), 5 * 900, accuracy: 1)
    // Leading/trailing runs also get their maxima (floods at each end).
    XCTAssertEqual(events.filter { $0.kind == .maxFlood }.count, 2)
    // Events alternate: no two slacks adjacent, no two maxima adjacent.
    for (a, b) in zip(events, events.dropFirst()) {
        XCTAssert((a.kind == .slack) != (b.kind == .slack))
    }
}

/// A monotone window with no crossing: one maximum, no slacks, no crash.
func testSampleEventsMonotone() {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let pts = (0..<8).map { CurrentPoint(time: t0.addingTimeInterval(Double($0) * 900), speed: 1 + Double($0) * 0.1) }
    let events = sampleEvents(pts)
    XCTAssert(events.filter { $0.kind == .slack }.isEmpty)
    XCTAssertEqual(events.filter { $0.kind == .maxFlood }.count, 1)
}
```

- [ ] **Step 2: Verify compile failure**, **Step 3: Implement**

```swift
/// Slack/max events scanned from a sampled signed-velocity series — the
/// online-gate path draws fetched official points, so events come from the
/// samples, not a harmonic engine. Slacks interpolate the zero crossing;
/// each run between crossings contributes its largest |sample| as a signed
/// maximum. 15-min official samples make interpolated slacks exact to a few
/// minutes — the same series CHS's own tables are printed from.
func sampleEvents(_ points: [CurrentPoint]) -> [CurrentEvent] {
    guard points.count > 1 else { return [] }
    var events: [CurrentEvent] = []
    var runStart = 0
    func closeRun(_ end: Int) {  // [runStart, end] inclusive, one sign
        let peak = points[runStart...end].max { abs($0.speed) < abs($1.speed) }!
        guard peak.speed != 0 else { return }
        events.append(CurrentEvent(time: peak.time, speed: peak.speed,
                                   kind: peak.speed > 0 ? .maxFlood : .maxEbb))
    }
    for i in 1..<points.count {
        let a = points[i - 1], b = points[i]
        if (a.speed > 0) != (b.speed > 0), a.speed != 0 {
            let f = abs(a.speed) / (abs(a.speed) + abs(b.speed))
            closeRun(i - 1)
            events.append(CurrentEvent(
                time: a.time.addingTimeInterval(b.time.timeIntervalSince(a.time) * f),
                speed: 0, kind: .slack))
            runStart = i
        }
    }
    closeRun(points.count - 1)
    return events.sorted { $0.time < $1.time }
}
```

- [ ] **Step 4: Green** (`-only-testing:SlackwaterTests/TimelineTests`), **Step 5: Commit**

```bash
git add Slackwater/TimelineStrip.swift SlackwaterTests/TimelineTests.swift
git commit  # "online-gates: sampleEvents — slacks and signed maxima scanned from a fetched series"
```

---

### Task 3: The fetched window — store, fetch, expiry

**Files:**
- Modify: `Slackwater/ChsCurrentGate.swift` (window model + store extension), `Slackwater/ChsFitService.swift` (fetch entry point reusing the private fetcher/resolution/projection)
- Test: `SlackwaterTests/ChsCurrentGateTests.swift`

**Interfaces:**
- Produces:

```swift
struct ChsOnlineWindow: Codable {
    var schemaVersion = 1
    let stationID: String
    let iwlsName: String
    let fetchedAt: Date
    let start: Date            // today −48h at fetch, the Timeline window
    let end: Date              // today +132h at fetch
    let floodDirection: Double // IWLS metadata at fetch time, kept local
    let ebbDirection: Double
    let times: [Double]        // epoch seconds, 15-min official samples
    let speeds: [Double]       // signed kn along the flood axis (project())
    var points: [CurrentPoint] { get }  // zipped
}
// ChsModelStore: onlineUrl(_:), loadOnline(_:) -> ChsOnlineWindow?, saveOnline(_:)
// ChsOnlineWindow.coversStrip(now: Date) -> Bool   // end >= now's strip end… see below
// ChsFitService.fetchOnlineWindow(for gate: ChsCurrentGateInfo) async throws -> ChsOnlineWindow
```

- Expiry rule (pure, testable): `coversStrip(now:)` is true when `start <= today−48h` AND `end >= today+132h` for `now`'s local midnight — i.e. the stored window still covers the full strip `Timeline` would build today. Task 5 refetches when it's false and connectivity allows.

- [ ] **Step 1: Failing tests** — store round-trip (mirror `testCurrentModelStoreRoundTrip`, suffix `-online.json`, assert it never shadows fit models: `ChsModelStore.loadCurrent` returns nil for the same key) and `coversStrip` at three nows: inside, at the edge (today's strip exactly covered), and 3 days later (uncovered). Construct windows directly; no network in unit tests.
- [ ] **Step 2: Verify failure**, **Step 3: Implement** — model + store beside `ChsModelStore.currentUrl` (same pattern, `-online.json` suffix, atomic write). `fetchOnlineWindow`: read `ChsFitService`'s fit path (~:335-370: station-list resolution by position filtered on `wcsp1` availability at :443, chunked `fetcher.series("wcsp1"/"wcdp1", …)`, `project(speeds:dirs:floodDirection:)`, axis from the same station metadata the fit uses) and assemble the strip window's chunks only. Follow the file's existing error-handling idiom; the caller (Task 5) shows the honesty card on throw.
- [ ] **Step 4: Green** (unit suite), **Step 5: Commit**

```bash
git add Slackwater/ChsCurrentGate.swift Slackwater/ChsFitService.swift SlackwaterTests/ChsCurrentGateTests.swift
git commit  # "online-gates: the fetched window — official 15-min series, stored per-gate, strip-coverage expiry"
```

---

### Task 4: TimelineData accepts fetched points

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:101-161` (`TimelineData.build`)
- Test: `SlackwaterTests/TimelineTests.swift`

**Interfaces:**
- Consumes: `sampleEvents` (Task 2).
- Produces: `TimelineData.build(onlinePoints: [CurrentPoint], tz: TimeZone, lat: Double, lon: Double, now: Date) -> TimelineData` — current-only strip data whose `currentPoints` are the fetched samples clipped to the window, `currentEvents = sampleEvents(...)` over them, `snapTimes` = events + sun, `hasTide == false`.

- [ ] **Step 1: Failing test** — build from a synthetic 15-min series spanning the strip window; assert `hasCurrent && !hasTide`, `TimelineGeo(data:).height == 340`, events non-empty, and every in-window event is a snap stop (mirror the DerivedGateTests snap assertion).
- [ ] **Step 2: Verify failure**, **Step 3: Implement** — a thin overload that computes the same `tz/today/days/sun` chrome as the existing build (share, don't duplicate: extract the day-chrome block into a private static helper both builds call), clips points to `start...end`, and scans events with the ±6h pad semantics the engine path uses (scan unclipped, filter snaps to window — read how the existing build pads).
- [ ] **Step 4: Green**, **Step 5: Commit**

```bash
git add Slackwater/TimelineStrip.swift SlackwaterTests/TimelineTests.swift
git commit  # "online-gates: TimelineData builds a current-only strip from fetched points"
```

---

### Task 5: OnlineGateDetailView + routing + queue skip

**Files:**
- Create: `Slackwater/OnlineGateDetailView.swift`
- Modify: `Slackwater/ChsDetailView.swift` (routing + promote skip — do NOT touch the `favoriteId:` argument, see Global Constraints), `Slackwater/ChsQueue.swift` (seeding skips `isOnline`), `Slackwater/SlackwaterApp.swift` (card message for unfetched online gates — find where CHS pending cards get their reading/message and give online gates "Online — official CHS predictions, fetched when connected")
- Test: build-only gate here; behavior is Task 6's UI tests

**Interfaces:**
- Consumes: Tasks 1–4 (`isOnline`, `onlineNote`, window store/fetch, `build(onlinePoints:…)`, `sampleEvents`).
- Produces: `OnlineGateDetailView(gate: ChsCurrentGateInfo)` with accessibility identifiers `online-honesty-card` (the unfetched card) and `online-provenance` (the fetched footer line); the nearest-gate link reuses the quiet-link visual convention with identifier `nearest-gate-link`.

- [ ] **Step 1: The view.** Model it on `CurrentDetailView` (post-split single-track anatomy) minus everything fit/provisional, plus the two states:
  - `@State window: ChsOnlineWindow?` — `onAppear`: `ChsModelStore.loadOnline(gate.id)`; if nil or `!coversStrip(now:)` and `Connectivity.shared.online`, `Task { try await ChsFitService.fetchOnlineWindow(for: gate) }` → save + set. Keep the stale window rendering while a refetch runs; swap when it lands.
  - **Fetched:** `TimelineData.build(onlinePoints:…)`; readout mirrors `CurrentDetailView`'s (speed via `tl.velocityAt(scrubTime)` — the drawn interpolation IS the data here; phase word from sign; slack from `currentEvents`; `slackWindow(tl.currentPoints, …)` under Next slack; `CompassArrow` from the window's flood/ebb directions). `MultiDaySchedule` with `days: tl.days`. `ScrubWhen`, `‹ swipe to scrub ›`, extreme-time labels — all standard. Footer/provenance (`online-provenance`): "CHS-published predictions · fetched <abbrev date>, covers to <abbrev date> — not computed on this device" + the standard "Predictions — not for navigation" MonoLabel.
  - **Unfetched/expired (and fetch-failed):** MapHeader (star = bare `gate.id`) + an amber card (`ChsAmberCard`, identifier `online-honesty-card`): title "No offline prediction here", headline = `gate.onlineNote ?? ""`, expectation = connectivity-aware ("Connect for a moment and Slackwater fetches CHS's official predictions — they cover about a week." / offline variant; if an expired window exists, append "Last fetch covered to <date>."). Below it, the nearest shipped gate (min distance over `ChsCurrentGateInfo.all.filter { !$0.isOnline }`) as a quiet link (`.onTapGesture`, push `ChsRoute.currentGate(nearest)` via the same `\.openTideDetail`-style pattern — but that key is typed to `TideStationRecord`; use a `NavigationLink`-free tap that appends through a new tiny `\.openChsGate` environment closure wired beside `openTideDetail` at the SAME root-level attachment point in `SlackwaterApp` — one line per layout... no: ONE shared attachment above both layouts, exactly like `openTideDetail`).
- [ ] **Step 2: Routing.** `ChsDetailView.currentGate` case: `if gate.isOnline { OnlineGateDetailView(gate: gate) } else { existing fitted/waiting logic }`. The `.onAppear { service.promote(route.jobID) }` must not fire for online gates (no job): guard on the route's gate being online.
- [ ] **Step 3: Queue.** Find where `ChsQueue` seeds jobs from `ChsCurrentGateInfo.all` and filter `!isOnline`; also check `OfflineManagerView`'s downloads list source — online gates must not appear as downloadable rows.
- [ ] **Step 4: Cards.** The list/search card for an online gate without a current window: message line per §4. With a covering window: next-slack reading from the stored points (`sampleEvents` over `window.points`) — find where CHS gate cards compute their reading and branch there.
- [ ] **Step 5: Build both destinations** (iPhone build + iPad build, lockf-wrapped), unit suite green. **Step 6: Commit**

```bash
git add Slackwater/OnlineGateDetailView.swift Slackwater/ChsDetailView.swift Slackwater/ChsQueue.swift Slackwater/SlackwaterApp.swift
git commit  # "online-gates: the online detail — fetched strip or the honest why-not, queue and cards follow"
```

---

### Task 6: UI tests (fast plan, no network)

**Files:**
- Modify: `SlackwaterUITests/ScreenshotTests.swift`, `Slackwater/SlackwaterApp.swift` (seed hook)

**Interfaces:**
- Consumes: identifiers from Task 5 (`online-honesty-card`, `online-provenance`, `nearest-gate-link`), the store from Task 3.

- [ ] **Step 1: Seed hook.** Mirror the existing `-seedGate`/`-chsResetModels` launch-argument pattern (find where they're handled at startup): add `-seedOnlineWindow <id>` which writes a synthetic `ChsOnlineWindow` covering today's strip (M2-ish sine, 15-min samples) via `ChsModelStore.saveOnline`, and make `-chsResetModels` also clear `-online.json` files.
- [ ] **Step 2: Tests.**

```swift
/// The origin report: a fresh install can FIND Sechelt Rapids, and the tap
/// lands on the honest explanation, not a dead end (M48).
func testOnlineGateUnfetchedShowsHonestyCard() throws { /* launch -chsResetModels -seedGate;
    openSearch "skookumchuck"; assert "Sechelt Rapids" result; tap;
    assert online-honesty-card exists; assert nearest-gate-link exists, tap it,
    assert a shipped gate detail opens (its name); back; star round-trip:
    detail-favorite → FAVORITES group renders (bare-id rule) → cleanup unfavorite. */ }

/// Seeded window: the online gate renders the full single-track detail.
func testOnlineGateFetchedRendersDetail() throws { /* launch -seedGate
    -seedOnlineWindow chs-sechelt-rapids; open Sechelt; assert timeline-strip,
    NEXT SLACK, slack-window, online-provenance (label CONTAINS "CHS-published"),
    schedule day-sun-d0; assert NO provisional badge and NO amber fast-answer card. */ }
```

Write them fully (the sketches above name every assertion; follow the file's narrative-comment style). Tests must leave the simulator as found (the favorites-leak lesson, 2026-08-08 — clean up any favorite they create).
- [ ] **Step 3:** `build-for-testing` compiles; run both new tests on the iPhone sim, then both on the iPad sim (lockf-wrapped, targeted). Expected: PASS with observed output.
- [ ] **Step 4: Commit**

```bash
git add SlackwaterUITests/ScreenshotTests.swift Slackwater/SlackwaterApp.swift
git commit  # "online-gates: UI pins — findable by alias, honest when empty, whole when seeded"
```

---

### Task 7: Live full-plan test + suite gate + PR draft

- [ ] **Step 1:** Add to the Full plan's live section (find how full-only tests are gated — test-plan membership or an in-test guard): `testOnlineGateLiveFetch` — open Sechelt with network, wait (generous timeout, like M46's 300s) for `online-provenance`, assert its label carries a real "covers to" date and `timeline-strip` exists.
- [ ] **Step 2:** Full fast suite both sims, detached; green or fix (systematic-debugging per failure, targeted re-runs before another full run).
- [ ] **Step 3:** Run the ONE live test on one sim against real IWLS (Full plan, targeted) — this is the spec's open-item verification that the rejects resolve in IWLS; if a gate does not resolve, STOP and report which (it may need dropping from the online set — human decision).
- [ ] **Step 4:** Push; draft (do NOT post) the PR body: origin story (Sechelt unfindable), what online gates are, the licensing posture line, test coverage, and the #31 interaction note. Bryan posts on his go.

## Self-review notes (spec → plan)

- Spec §1 → Task 1 (identity, aliases, queue-skip lands in Task 5 Step 3). §2 → Tasks 2, 3, 4, 5 (fetch/store/strip/detail/provenance/refetch rule). §3 → Task 5 (honesty card, nearest link, auto-fetch). §4 → Task 5 Step 4 (cards). §6 → Tasks 1–4 units, Task 6 UI, Task 7 live. Open item (IWLS resolution) → Task 7 Step 3, corrected to runtime resolution per the licensing constraint.
- Spec deviation, deliberate: set bearings come from IWLS metadata at fetch time (stored in the window), NOT the registry — the registry doesn't carry them and the fit path already works this way. The spec's §2 bearing sentence is superseded by this plan; noted for the PR body.
- Names crossing tasks: `isOnline`/`onlineNote` (T1→T5), `sampleEvents` (T2→T4/T5), `ChsOnlineWindow`/`loadOnline`/`saveOnline`/`coversStrip`/`fetchOnlineWindow` (T3→T5/T6), `build(onlinePoints:…)` (T4→T5), identifiers `online-honesty-card`/`online-provenance`/`nearest-gate-link` (T5→T6/T7).
