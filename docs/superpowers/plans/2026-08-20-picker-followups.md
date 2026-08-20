# Picker Follow-ups (#67 items 1, 2, 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An online gate's fetched blocks survive each other on disk (item 4), every timeline window carries the 48h back-pad so the noon park never opens on dead space (item 1), and the honesty card keeps the week-range bar as the way back (item 2).

**Architecture:** Three changes in dependency order — but note the order **differs from the spec's commit numbering** (spec: storage → window → UI; here: window → storage → UI). Reason: doing the window simplification first means the new store API is born with `covers(anchor:)` and never has to thread `today:` parameters that the very next commit would delete. The spec's end state is identical.

**Tech Stack:** Swift/SwiftUI, XCTest + XCUITest, XcodeGen (`project.yml` → `xcodegen generate`), `scripts/test.sh` on two reference simulators.

**Spec:** `docs/superpowers/specs/2026-08-20-picker-followups-design.md` (committed on this branch).

## Global Constraints

- **You are in the worktree `~/src/sailingnaturali/slackwater-ios-wt-picker67`, branch `picker-67-followups`.** Never touch `main`; never merge the PR yourself (README § Branching).
- **This repo's CLAUDE.md is load-bearing — read it before the first build.** In particular: plan code below is *intent, never compiled* — if something here doesn't match the tree, trust the tree and say so; prove every new assertion red; two concurrent `xcodebuild` runs kill each other, so every build/test goes through `lockf /tmp/slackwater-test.lock`, and **no bare `xcodebuild` while a test run is in flight**.
- First build in the worktree: `xcodegen generate` (creates `Slackwater.xcodeproj`).
- Compile check (fast feedback):
  `lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20`
- Single test:
  `lockf /tmp/slackwater-test.lock xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages -only-testing:SlackwaterTests/ChsCurrentGateTests/testName 2>&1 | tail -30`
- Full fast suite (both sims, ~9 min/sim): `./scripts/test.sh`
- Retention constant is **60 days** (`Timeline.onlineRetentionDays`), spec § Commit 1.
- Commit trailer on every commit:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01HaMaRk9UijJQMDX48EVvTk`

---

### Task 1: Unconditional 48h back-pad — `Timeline.window(anchor:)` (item 1)

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:114-125` (the `window` definition)
- Modify: `Slackwater/ChsCurrentGate.swift:111` (`saveOnline` cut), `:159-163` (`covers`)
- Modify: `Slackwater/ChsFitService.swift:558-572` (`onlineFetchSpan`)
- Modify: `Slackwater/Theme.swift:481-508` (`WeekPickerSheet` `onPick` + noon-park comment)
- Modify: `Slackwater/SlackwaterApp.swift:86-102` (seed comment + call), `:1553-1560` (`onlineCard`)
- Modify: `Slackwater/OnlineGateDetailView.swift:36-70` (`timeline` comment + covers), `:131-141` (`onAppear`)
- Test: `SlackwaterTests/TimelineTests.swift:185-204`, `:803`; `SlackwaterTests/ChsCurrentGateTests.swift:165-212`, `:355-390`

**Interfaces:**
- Produces: `Timeline.window(anchor: Date) -> (start: Date, end: Date)` — no `today:` parameter, back-pad always applied. `ChsOnlineWindow.covers(anchor: Date) -> Bool` — no `today:`. Tasks 2–4 use these signatures.

**Known fence being moved (do not "fix back"):** `TimelineTests.testWindowBackPadOnlyOnTheCurrentWeek` deliberately asserts a past/future week gets *no* pad, with a written rationale. Issue #67 item 1 supersedes it: the pad-free window opens half a viewport of dead space left of the noon park on wide panes (UIScrollView clamps the negative offset), and the `anchor == today` exact-equality conditional is the documented "two clocks answering one question" bug class. You are inverting that test on purpose.

- [ ] **Step 1: Rewrite the window test (failing first)**

Replace `testWindowBackPadOnlyOnTheCurrentWeek` (TimelineTests.swift:188) with:

```swift
/// #67 item 1: every window carries the 48h look-back — today's answers "what
/// did the water just do"; a picked week's puts data behind the noon park
/// (216pt in), which otherwise opens on dead space on any pane wider than
/// 432pt (UIScrollView clamps the negative centering offset). One
/// unconditional shape also deletes the anchor == today exact-equality trap
/// three comment blocks used to guard.
func testWindowBackPadIsUnconditional() {
    let today = vancouverMidnight(2026, 8, 11)
    let current = Timeline.window(anchor: today)
    XCTAssertEqual(current.start, today.addingTimeInterval(-48 * 3600))
    XCTAssertEqual(current.end, today.addingTimeInterval(180 * 3600))

    let future = vancouverMidnight(2026, 9, 14)
    let ahead = Timeline.window(anchor: future)
    XCTAssertEqual(ahead.start, future.addingTimeInterval(-48 * 3600),
                   "a picked week gets the same look-back as today's")
    XCTAssertEqual(ahead.end, future.addingTimeInterval(180 * 3600))
}
```

- [ ] **Step 2: Verify it fails to compile / fails**

The call `Timeline.window(anchor:)` doesn't exist yet — the compile error IS the red. Run the compile check from Global Constraints; expect failure naming this call.

- [ ] **Step 3: Implement the new window definition**

`TimelineStrip.swift` — replace the `window` function (keep the "THE window definition" paragraph of its doc comment; replace the back-pad paragraph):

```swift
/// The 48h back-pad is UNCONDITIONAL (#67 item 1). It used to exist only when
/// `anchor == today`, which (a) left the noon park with dead space to its left
/// on panes wider than 432pt — the centering target is `x(t) − width/2`, and
/// UIScrollView clamps the negative result to 0 — and (b) made the window's
/// shape depend on exact Date equality between two `todayLocal` calls, a
/// documented class of "two clocks answering one question" defects.
static func window(anchor: Date) -> (start: Date, end: Date) {
    (anchor.addingTimeInterval(-backHours * 3600),
     anchor.addingTimeInterval(forwardHours * 3600))
}
```

- [ ] **Step 4: Update every call site (7 production, 4 test regions)**

All become `Timeline.window(anchor: X)`:
1. `ChsCurrentGate.swift:111` → `let cut = min(Timeline.window(anchor: today).start, window.start)`
2. `ChsCurrentGate.swift` `covers` →
```swift
func covers(anchor: Date) -> Bool {
    let need = Timeline.window(anchor: anchor)
    return start <= need.start && end >= need.end
}
```
Trim its doc comment's "conditional back-pad / second derivation drifts" sentence — the shared-definition rule still stands, the conditional is gone. Same for the `start:` property comment at `:144`.
3. `ChsFitService.swift` `onlineFetchSpan` body → `(Timeline.window(anchor: from).start, from.addingTimeInterval(Timeline.onlineFetchDays * 86_400))`. Its doc comment: "back-padded only when the anchor IS today" → "back-padded like every window (#67 item 1)".
4. `TimelineStrip.swift:488` (`dayChrome`) → `let w = Timeline.window(anchor: anchor)` (`today` is still computed there for the chrome labels — leave it).
5. `Theme.swift:502` → `let week = Timeline.window(anchor: picked)`. In the onPick comment, replace the "Noon is 216pt in, past half a phone viewport" sentence with: "With the unconditional 48h back-pad, noon has 60h (1080pt) of data behind it — no pane is that wide, so the park never opens on dead space (#67 item 1)." Keep the rest (midnight-artefact rationale still true).
6. `SlackwaterApp.swift:102` (seed) → `let w = Timeline.window(anchor: today)`.
7. `OnlineGateDetailView.swift:69` → `return window.covers(anchor: anchor) ? tl : nil`, and `:140` → `if window?.covers(anchor: anchor) != true, net.online { fetchNow(from: anchor) }`.

Comment shrink (the point of the change — don't skip): `OnlineGateDetailView.timeline`'s "Built FIRST, then asked to cover its own `today`" paragraph and `onAppear`'s "ONE snapshot of today" comment, and `SlackwaterApp.onlineCard`'s "ONE snapshot of today" comment all describe the equality trap that no longer exists. Reduce each to one line or delete; keep the unrelated parts (computed-not-@State, cache note).

- [ ] **Step 5: Update the remaining tests**

- `TimelineTests.swift:803` → `let (start, end) = Timeline.window(anchor: today)` (and delete its "only passed by hand because anchor == today" comment — no longer true).
- `ChsCurrentGateTests.swift` `testOnlineWindowCoversStrip`: `let need = Timeline.window(anchor: today0)`; all `covers(anchor: X, today: Y)` → `covers(anchor: X)`. The "3 days later" case keeps working: the same window fails a later anchor's strip.
- `testCoversHoldsForThreeWeeksOfAnchors`: drop `today:` args; the 22-days-passes / 24-days-fails assertions hold unchanged (a +22d anchor's window is `[+20d, +29.5d]` ⊂ `[−2d, +30d]`; +24d's end `+31.5d` overruns).
- `testOnlineFetchSpanBackPadsOnlyTodayAndRunsThirtyDaysForward` → rename `testOnlineFetchSpanBackPadsAndRunsThirtyDaysForward`; the anchored assertion becomes:
```swift
XCTAssertEqual(paged.start, ahead.addingTimeInterval(-Timeline.backHours * 3600),
               "an anchored fetch is back-padded like every window (#67 item 1)")
```
(chunk-plan and `covers(anchor: ahead)` assertions stay, minus `today:`).

- [ ] **Step 6: Compile-check, then run the touched suites**

Compile check first. Then:
`lockf /tmp/slackwater-test.lock xcodebuild test -project Slackwater.xcodeproj -scheme Slackwater -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath build/SourcePackages -only-testing:SlackwaterTests 2>&1 | tail -30`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A Slackwater SlackwaterTests
git commit -m "app: every window carries the 48h back-pad (#67 item 1)"
```
(with the standard trailers from Global Constraints).

---

### Task 2: `ChsOnlineStore` — the multi-block type (pure addition)

**Files:**
- Modify: `Slackwater/TimelineStrip.swift:51` (add constant beside `onlineFetchDays`)
- Modify: `Slackwater/ChsCurrentGate.swift` (add `pruned(before:)` to `ChsOnlineWindow`; add `ChsOnlineStore` below it)
- Test: `SlackwaterTests/ChsCurrentGateTests.swift` (new section after the merging tests, reusing the `onlineWindow` helper at `:233`)

**Interfaces:**
- Consumes: `ChsOnlineWindow.merging(_:prunedBefore:)`, `ChsOnlineWindow.sampleInterval`, `covers(anchor:)` from Task 1.
- Produces (Task 3 depends on these exact names):
  - `Timeline.onlineRetentionDays: Double` (= 60)
  - `ChsOnlineWindow.pruned(before: Date) -> ChsOnlineWindow?`
  - `struct ChsOnlineStore: Codable { var schemaVersion = 2; let stationID: String; let blocks: [ChsOnlineWindow] }`
  - `ChsOnlineStore.block(covering anchor: Date) -> ChsOnlineWindow?`
  - `ChsOnlineStore.block(spanning window: ChsOnlineWindow) -> ChsOnlineWindow?`
  - `ChsOnlineStore.inserting(_ window: ChsOnlineWindow, prunedBefore cut: Date) -> ChsOnlineStore`

Nothing else references the store yet, so this task compiles green throughout.

- [ ] **Step 1: Write the failing tests**

Append to the merging section of `ChsCurrentGateTests.swift`:

```swift
// MARK: - Multi-block store (#67 item 4)

/// A far-forward fetch used to discard today's block outright (single
/// start/end, newest wins). The store keeps both.
func testInsertingKeepsDisjointBlocksSeparate() {
    let t0 = Date().timeIntervalSince1970.rounded(.down)
    let today = onlineWindow([t0, t0 + 900], [1, 2])
    let far = onlineWindow([t0 + 40 * 86_400, t0 + 40 * 86_400 + 900], [3, 4])
    let store = ChsOnlineStore(stationID: "chs-test-merge", blocks: [today])
        .inserting(far, prunedBefore: Date(timeIntervalSince1970: t0 - 1))
    XCTAssertEqual(store.blocks.count, 2, "a disjoint fetch must not cost the stored block")
    XCTAssertEqual(store.blocks[0].times, today.times, "sorted by start, stored block intact")
    XCTAssertEqual(store.blocks[1].times, far.times)
}

/// An incoming block that reaches two stored blocks joins all three — the
/// single ascending pass has to absorb a chain, not just one neighbour.
func testInsertingBridgesTwoStoredBlocks() {
    let t0 = Date().timeIntervalSince1970.rounded(.down)
    let a = onlineWindow([t0, t0 + 900], [1, 2])
    let c = onlineWindow([t0 + 3600, t0 + 4500], [5, 6])
    let bridge = onlineWindow([t0 + 1800, t0 + 2700], [3, 4])
    let store = ChsOnlineStore(stationID: "chs-test-merge", blocks: [a, c])
        .inserting(bridge, prunedBefore: Date(timeIntervalSince1970: t0 - 1))
    XCTAssertEqual(store.blocks.count, 1, "the bridge joins both neighbours")
    XCTAssertEqual(store.blocks[0].times, [t0, t0 + 900, t0 + 1800, t0 + 2700, t0 + 3600, t0 + 4500])
}

/// Coverage never stitches across the gap between blocks — the same "no strip
/// with a dead zone" rule `covers` enforces inside one block.
func testBlockCoveringRefusesTheGap() throws {
    let tz = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let today = cal.startOfDay(for: Date())
    func span(_ anchor: Date) -> ChsOnlineWindow {
        let w = Timeline.window(anchor: anchor)
        return ChsOnlineWindow(stationID: "g", iwlsName: "G", timezone: tz.identifier,
                               fetchedAt: .now, start: w.start, end: w.end,
                               floodDirection: 0, ebbDirection: 180, times: [], speeds: [])
    }
    let far = today.addingTimeInterval(60 * 86_400)
    let store = ChsOnlineStore(stationID: "g", blocks: [span(today), span(far)])
    XCTAssertNotNil(store.block(covering: today))
    XCTAssertNotNil(store.block(covering: far))
    XCTAssertNil(store.block(covering: today.addingTimeInterval(30 * 86_400)),
                 "the gap between blocks has no samples — it must not read as covered")
}

/// #67 item 6 (bounded backward retention): a block ages out at the next save
/// after it falls behind today − 60d — but never the save's own fetch, so a
/// deliberately-picked old week still renders (the min(_, incoming.start)
/// guard lives in saveOnline; inserting itself just applies the cut).
func testInsertingPrunesAgedBlocks() {
    let t0 = Date().timeIntervalSince1970.rounded(.down)
    let aged = onlineWindow([t0 - 70 * 86_400, t0 - 70 * 86_400 + 900], [1, 2])
    let fresh = onlineWindow([t0, t0 + 900], [3, 4])
    let store = ChsOnlineStore(stationID: "chs-test-merge", blocks: [aged])
        .inserting(fresh, prunedBefore: Date(timeIntervalSince1970: t0 - 60 * 86_400))
    XCTAssertEqual(store.blocks.count, 1, "the aged block is gone, not half-kept")
    XCTAssertEqual(store.blocks[0].times, fresh.times)
}

/// pruned(before:) follows merging's rule: `start` follows the cut, or
/// `covers` keeps claiming a range whose samples were deleted.
func testPrunedDropsSamplesAndMovesStart() {
    let t0 = Date().timeIntervalSince1970.rounded(.down)
    let w = onlineWindow([t0, t0 + 900, t0 + 1800], [1, 2, 3])
    let cut = Date(timeIntervalSince1970: t0 + 900)
    let p = w.pruned(before: cut)
    XCTAssertEqual(p?.times, [t0 + 900, t0 + 1800])
    XCTAssertEqual(p?.start, cut)
    XCTAssertNil(w.pruned(before: Date(timeIntervalSince1970: t0 + 86_400)),
                 "nothing survives → nil, not an empty shell that still claims a span")
    XCTAssertEqual(w.pruned(before: Date(timeIntervalSince1970: t0 - 1))?.times, w.times,
                   "a cut before the block is a no-op")
}
```

- [ ] **Step 2: Verify red**

Compile check — expect failure on `ChsOnlineStore` / `pruned` not existing.

- [ ] **Step 3: Implement**

`TimelineStrip.swift`, beside `onlineFetchDays` (:51):

```swift
/// How far back fetched online blocks are kept (#67 item 6: bounded backward
/// retention). A block ages out at the first save after it falls behind
/// today − this; a save's own fetch is always protected (`saveOnline`'s min),
/// so a deliberately-picked old week renders and only later saves collect it.
static let onlineRetentionDays = 60.0
```

`ChsCurrentGate.swift`, inside `ChsOnlineWindow` (below `merging`):

```swift
/// This window with everything before `cut` dropped — nil when nothing
/// survives. `start` follows the cut for `merging`'s reason: an unpruned
/// start keeps `covers` claiming a range whose samples are gone.
func pruned(before cut: Date) -> ChsOnlineWindow? {
    guard start < cut else { return self }
    guard end > cut else { return nil }
    let c = cut.timeIntervalSince1970
    let kept = zip(times, speeds).filter { $0.0 >= c }
    return ChsOnlineWindow(stationID: stationID, iwlsName: iwlsName, timezone: timezone,
                           fetchedAt: fetchedAt, start: cut, end: end,
                           floodDirection: floodDirection, ebbDirection: ebbDirection,
                           times: kept.map { $0.0 }, speeds: kept.map { $0.1 })
}
```

Below the `ChsOnlineWindow` struct:

```swift
/// The on-disk shape for an online gate (#67 item 4): DISJOINT fetched
/// blocks, sorted by start. The single start/end window before it made every
/// disjoint merge lossy — a far-forward pick discarded today's block, and
/// paging back refetched ~30 days the app had just held. Blocks stay pairwise
/// separated by more than `sampleInterval`; anything closer merges on save.
/// Coverage questions go to a SINGLE block: the gap between blocks has no
/// samples, and claiming it renders a strip with a dead zone.
struct ChsOnlineStore: Codable {
    var schemaVersion = 2
    let stationID: String
    let blocks: [ChsOnlineWindow]

    /// The one block covering `anchor`'s whole strip, or nil — never a stitch
    /// across a gap.
    func block(covering anchor: Date) -> ChsOnlineWindow? {
        blocks.first { $0.covers(anchor: anchor) }
    }

    /// The block whose span contains `window`'s — what `saveOnline` returns:
    /// the caller's copy must never be narrower than the disk's.
    func block(spanning window: ChsOnlineWindow) -> ChsOnlineWindow? {
        blocks.first { $0.start <= window.start && $0.end >= window.end }
    }

    /// Union `window` in: absorb every stored block that overlaps or abuts it
    /// (within `sampleInterval` slack — the seam a clamped fetch end
    /// produces), keep the rest, prune everything to `cut`, drop empties.
    /// One ascending pass absorbs a chain: stored blocks are pairwise
    /// disjoint, so only the incoming block can bridge two of them, and
    /// sorted order means it meets each neighbour after absorbing the last.
    /// `merging`'s own disjoint guard never fires here — the test above is
    /// the same test it applies.
    func inserting(_ window: ChsOnlineWindow, prunedBefore cut: Date) -> ChsOnlineStore {
        let slack = ChsOnlineWindow.sampleInterval
        var merged = window
        var rest: [ChsOnlineWindow] = []
        for b in blocks.sorted(by: { $0.start < $1.start }) {
            if b.start <= merged.end.addingTimeInterval(slack),
               merged.start <= b.end.addingTimeInterval(slack) {
                merged = b.merging(merged, prunedBefore: cut)
            } else if let kept = b.pruned(before: cut) {
                rest.append(kept)
            }
        }
        if let kept = merged.pruned(before: cut) { rest.append(kept) }
        return ChsOnlineStore(stationID: stationID,
                              blocks: rest.sorted { $0.start < $1.start })
    }
}
```

- [ ] **Step 4: Run the new tests**

`-only-testing:SlackwaterTests/ChsCurrentGateTests` — expect all green, including the untouched merging tests.

- [ ] **Step 5: Commit**

```bash
git add Slackwater/ChsCurrentGate.swift Slackwater/TimelineStrip.swift SlackwaterTests/ChsCurrentGateTests.swift
git commit -m "app: ChsOnlineStore — disjoint fetched blocks with bounded retention (#67 item 4)"
```

---

### Task 3: Persist the store and switch every reader (item 4 lands)

**Files:**
- Modify: `Slackwater/ChsCurrentGate.swift:79-116` (`loadOnline`/`saveOnline`)
- Modify: `Slackwater/OnlineGateDetailView.swift` (`onAppear`, `.onReceive`, `applyAnchor`, `returnToNow`, `expectation`)
- Modify: `Slackwater/SlackwaterApp.swift:1541-1560` (list card store read)
- Modify: `Slackwater/ChsFitService.swift` (`runOnlineFetch` comments; the one-fetch-per-gate rationale)
- Test: `SlackwaterTests/ChsCurrentGateTests.swift` (`testOnlineWindowStoreRoundTrip`, `testSaveOnlineMergesInsteadOfReplacing`, + 2 new)

**Interfaces:**
- Consumes: everything Task 2 produced.
- Produces: `ChsModelStore.loadOnline(_ stationID: String) -> ChsOnlineStore?` (was `ChsOnlineWindow?`); `ChsModelStore.saveOnline(_ window: ChsOnlineWindow) throws -> ChsOnlineWindow` (signature unchanged — returns the merged block spanning the input). Task 4's UI test relies on both via the seed.

**Trap — the #93 two-state card:** the list card distinguishes "never fetched" from "fetched, ran out" via a non-nil-but-uncovering window. `block(covering:)` returns nil for both, so the card must keep the raw store for the status path. Check `onlineGateStatus`'s actual parameter use before wiring `blocks.last` in.

- [ ] **Step 1: Update the two persistence tests + add two (failing first)**

`testOnlineWindowStoreRoundTrip`: after the existing saves, load becomes:

```swift
let store = try XCTUnwrap(ChsModelStore.loadOnline("chs-test-online"))
let loaded = try XCTUnwrap(store.blocks.first)
XCTAssertEqual(store.blocks.count, 1)
```
(rest of its assertions unchanged against `loaded`).

`testSaveOnlineMergesInsteadOfReplacing`: the `saved` assertions stand (the returned value is still the merged block). The `loaded` half becomes `store.blocks` (count 1, the same times/speeds/start/end assertions against `blocks[0]`).

New tests:

```swift
/// THE #67 item 4 headline: a far-forward fetch and today's block coexist on
/// disk. Under the single window the second save discarded the first.
func testSaveOnlineKeepsTodayWhenAFarBlockLands() throws {
    let tz = try XCTUnwrap(TimeZone(identifier: "America/Vancouver"))
    let t0 = todayLocal(tz).timeIntervalSince1970
    let url = ChsModelStore.onlineUrl("chs-test-merge")
    try? FileManager.default.removeItem(at: url)
    defer { try? FileManager.default.removeItem(at: url) }

    try ChsModelStore.saveOnline(onlineWindow([t0, t0 + 900], [1, 2]))
    let far = t0 + 40 * 86_400
    let saved = try ChsModelStore.saveOnline(onlineWindow([far, far + 900], [3, 4]))
    XCTAssertEqual(saved.times, [far, far + 900],
                   "saveOnline returns the block the fetch landed in, not the whole store")

    let store = try XCTUnwrap(ChsModelStore.loadOnline("chs-test-merge"))
    XCTAssertEqual(store.blocks.count, 2, "today's block survived the far save")
    XCTAssertEqual(store.blocks[0].times, [t0, t0 + 900])
}

/// A device that fetched under the single-window shape keeps its data: the
/// legacy file decodes as one block.
func testLoadOnlineMigratesALegacySingleWindowFile() throws {
    let legacy = onlineWindow([0, 900], [1, 2], id: "chs-test-legacy")
    try ChsModelStore.save(legacy, id: "chs-test-legacy", suffix: "-online")  // v1 bytes, straight to disk
    defer { try? FileManager.default.removeItem(at: ChsModelStore.onlineUrl("chs-test-legacy")) }
    let store = try XCTUnwrap(ChsModelStore.loadOnline("chs-test-legacy"))
    XCTAssertEqual(store.blocks.count, 1)
    XCTAssertEqual(store.blocks[0].times, [0, 900])
}
```

- [ ] **Step 2: Verify red** (compile check — `loadOnline` still returns the old type).

- [ ] **Step 3: Switch `ChsModelStore`**

Replace `loadOnline`/`saveOnline` (ChsCurrentGate.swift:82, :109-116). Keep the existing doc comment's merge/returns story, replace the prune paragraph:

```swift
/// Store decode first, then the legacy single-window shape (schemaVersion 1,
/// pre-#67): each fails cleanly on the other's bytes (`blocks` vs
/// `times`/`speeds` are required keys), so the order is just preference.
/// The first save rewrites the file in the store shape.
static func loadOnline(_ stationID: String) -> ChsOnlineStore? {
    if let store: ChsOnlineStore = load(stationID, suffix: "-online") { return store }
    guard let legacy: ChsOnlineWindow = load(stationID, suffix: "-online") else { return nil }
    return ChsOnlineStore(stationID: legacy.stationID, blocks: [legacy])
}

/// The prune cut is bounded backward retention (#67 item 6): blocks age out
/// at the first save after they fall behind today − onlineRetentionDays. The
/// min(_, window.start) guard is unchanged from the single-window days — the
/// cut never discards data the incoming fetch itself covers, or a picked old
/// week would be deleted by its own save and refetch forever.
@discardableResult
static func saveOnline(_ window: ChsOnlineWindow) throws -> ChsOnlineWindow {
    let tz = TimeZone(identifier: window.timezone) ?? .current
    let cut = min(todayLocal(tz).addingTimeInterval(-Timeline.onlineRetentionDays * 86_400),
                  window.start)
    let store = (loadOnline(window.stationID)
                 ?? ChsOnlineStore(stationID: window.stationID, blocks: []))
        .inserting(window, prunedBefore: cut)
    try save(store, id: window.stationID, suffix: "-online")
    return store.block(spanning: window) ?? window
}
```

Note what this deletes: the old `Timeline.window(anchor: today).start` cut — the 48h horizon is now 60 days, which is the retention decision from the spec, not an accident. The `// ponytail: no forward cap` note stays.

- [ ] **Step 4: Switch the detail view**

`OnlineGateDetailView.swift` — `window` stays `@State ChsOnlineWindow?` but its meaning narrows to "the block for the current anchor"; update its `/// ...` accordingly. Changes:

- `onAppear` (:138): `if window == nil { window = ChsModelStore.loadOnline(gate.id)?.block(covering: anchor) }`
- `.onReceive` (:152): `window = ChsModelStore.loadOnline(gate.id)?.block(covering: anchor) ?? window`
- `applyAnchor` — the item-4 payoff; a re-pick from disk BEFORE deciding to fetch:

```swift
/// The anchor moved. The store may already hold a block for it — paging back
/// to a week the app has must be a disk read, never a refetch (#67 item 4) —
/// so re-pick first; only then is a nil timeline a real gap worth a fetch.
private func applyAnchor() {
    if let block = ChsModelStore.loadOnline(gate.id)?.block(covering: anchor) { window = block }
    if timeline == nil, net.online { fetchNow(from: anchor) }
}
```

- `returnToNow`: delete the "A far-forward pick's fetch can have discarded today's block (disjoint blocks: the incoming one wins)" sentence — that mechanism is gone; `applyAnchor`'s re-pick now serves this path. Keep the anchor-reset rationale.
- `expectation`: the "Last fetch covered to" line reads the store's far edge, not the block on screen (which is nil exactly when this card shows):

```swift
if let end = ChsModelStore.loadOnline(gate.id)?.blocks.last?.end {
    text += " Last fetch covered to \(monthDay(end, tz))."
}
```

- [ ] **Step 5: Switch the list card**

`SlackwaterApp.swift` — rename the state to match its new type; `onlineGateStatus` needs the newest block, not nil, to keep #93's two states:

```swift
@State private var onlineStore: ChsOnlineStore?
...
private func refreshOnlineWindow() {
    guard gate.isOnline else { return }
    onlineStore = ChsModelStore.loadOnline(gate.id)
}
...
@ViewBuilder private var onlineCard: some View {
    let today = todayLocal(gate.tz)
    if let block = onlineStore?.block(covering: today) {
        OnlineGateCardView(gate: gate, window: block, km: km)
    } else {
        ChsPendingCard(name: gate.name, region: gate.region, id: gate.id, km: km,
                       status: onlineGateStatus(onlineStore?.blocks.last, online: net.online))
    }
}
```

Verify `onlineGateStatus`'s parameter type/uses first (the #93 trap above); if it takes `ChsOnlineWindow?`, `blocks.last` preserves "fetched but ran out" (non-nil, carries the real covered-to date) vs "never fetched" (nil store → nil).

- [ ] **Step 6: `ChsFitService` comment truth-up**

`runOnlineFetch`: code unchanged (`saveOnline` still returns what the caller should render). Two comments now lie — fix them:
- the "Returns the window as SAVED — the union of this block with whatever was already stored" paragraph → "Returns the stored block this fetch merged into — never narrower than the disk's copy of this span."
- the one-fetch-per-gate rationale's "disjoint blocks make `merging` return the incoming one outright, so whichever saves LAST wins the whole file" → the store no longer loses a block to that race, but two concurrent read-modify-writes of one file still lose ONE of the two fetches; the coalescing stays for that and for the duplicate round trip.

- [ ] **Step 7: Compile-check, run SlackwaterTests, expect green; then run the two seeded UI tests**

`-only-testing:SlackwaterUITests/ScreenshotTests/testOnlineGateFetchedRendersDetail -only-testing:SlackwaterUITests/ScreenshotTests/testOnlineGateUnfetchedShowsHonestyCard`
The seed writes through `saveOnline`, so this proves the store shape renders end-to-end before Task 4 builds on it.

- [ ] **Step 8: Commit**

```bash
git add -A Slackwater SlackwaterTests
git commit -m "app: online gates persist disjoint blocks; paging back is a disk read (#67 items 4+6)"
```

---

### Task 4: The honesty card keeps the week-range bar (item 2) + hermetic UI proof

**Files:**
- Modify: `Slackwater/Theme.swift:462-470` (`ScrubDetailScaffold.body`)
- Modify: `Slackwater/SlackwaterApp.swift:86-121` (second seed flag; check `SlackwaterApp.init` for where `-seedOnlineWindow` is parsed and mirror it)
- Test: `SlackwaterUITests/ScreenshotTests.swift:2436-2466` (extend the offline test; add one new test)

**Interfaces:**
- Consumes: `WeekRangeBar(anchor:today:tz:onTap:)`, `todayLocal(_:)`, `ChsModelStore.saveOnline` (seed), Task 3's block-per-anchor rendering.

- [ ] **Step 1: Extend the offline UI test (failing first) and add the two-block test**

In `testOnlineGatePagedBeyondItsWindowOffline`, after the honesty-card/strip-gone assertions, add:

```swift
// #67 item 2: the honesty card is not a dead end — the bar survives it,
// and its picker is the way back to a week the app holds.
let bar = app.descendants(matching: .any)["week-range-bar"].firstMatch
XCTAssert(bar.exists, "the honesty card must keep the week-range bar")
bar.tap()
XCTAssert(app.descendants(matching: .any)["week-picker"].firstMatch.waitForExistence(timeout: 5))
app.buttons["Previous Month"].firstMatch.tap()
app.buttons["Previous Month"].firstMatch.tap()
let todayCell = app.collectionViews.buttons.matching(
    NSPredicate(format: "label CONTAINS[c] 'today'")).firstMatch
XCTAssert(todayCell.exists, "the graphical picker labels today's cell")
todayCell.tap()
app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()
XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
          "back on the seeded week, the strip must render from disk — offline")
```

**Unverified claim, check it:** the `label CONTAINS 'today'` predicate for the graphical `DatePicker`'s today cell is this plan's guess. If it doesn't match, print `app.collectionViews.debugDescription` once and target the real label (a date-formatted label is the likely shape). Same applies below.

New test after it:

```swift
/// #67 item 4, hermetically: two DISJOINT seeded blocks, no network. Under
/// the single-window store the far seed's save DISCARDED today's block, so
/// this test's very first strip assertion is red there; and paging into the
/// far block must render from disk, which is the multi-block payoff.
func testOnlineGatePagesBetweenSeededBlocksOffline() throws {
    let app = launch("-seedGate", "-chsResetModels",
                     "-seedOnlineWindow", "chs-sechelt-rapids",
                     "-seedOnlineFarWindow", "chs-sechelt-rapids",
                     "-networkKillSwitch",
                     "-fixLat", "48.4235", "-fixLon", "-123.3705")

    openSearch(app, "skookumchuck")
    let result = app.staticTexts["Sechelt Rapids"].firstMatch
    XCTAssert(result.waitForExistence(timeout: 5))
    result.tap()

    XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
              "today's block must survive the far seed's save (single-window: it did not)")

    // Two months out lands inside the far block ([today+30d, today+85d]:
    // cell 10 of month+2 is today+35..70d, whose ±window fits regardless of
    // today's day-of-month).
    app.descendants(matching: .any)["week-range-bar"].firstMatch.tap()
    XCTAssert(app.descendants(matching: .any)["week-picker"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["Next Month"].firstMatch.tap()
    app.buttons["Next Month"].firstMatch.tap()
    app.collectionViews.buttons.element(boundBy: 10).tap()
    app.descendants(matching: .any)["week-picker-done"].firstMatch.tap()

    XCTAssert(app.otherElements["timeline-strip"].waitForExistence(timeout: 5),
              "a far week the app holds on disk must render offline, not honesty-card")
    XCTAssertFalse(app.descendants(matching: .any)["online-honesty-card"].firstMatch.exists)
    let ink = inkFraction(app.otherElements["timeline-strip"].firstMatch)
    XCTAssert(ink > 0.05, "the far block's strip drew nothing — ink \(ink)")
    save(app, "online-gate-far-block.png")
}
```

- [ ] **Step 2: Add the far-block seed**

`SlackwaterApp.swift` — generalize the seed and add the flag beside `-seedOnlineWindow`'s parsing site (find it in `SlackwaterApp.init`; mirror exactly how the id argument is read):

```swift
/// UI-test hook: like `seedOnlineWindow`, but a DISJOINT far block —
/// [today+30d, today+85d], wide enough that "two months out, cell 10" in the
/// picker always lands a whole strip inside it, and far enough that it can
/// never merge with today's block. Written through `saveOnline` so the test
/// exercises the real disjoint-save path (#67 item 4).
private func seedOnlineFarWindow(stationID: String) {
    seedOnline(stationID: stationID, offsetDays: 30, spanDays: 55)
}
```

Refactor `seedOnlineWindow` so both call one worker (keep its existing doc comment on the today variant):

```swift
private func seedOnlineWindow(stationID: String) {
    seedOnline(stationID: stationID, offsetDays: nil, spanDays: nil)
}

/// nil offset = today's real window (`Timeline.window(anchor: today)`);
/// an offset seeds [today+offset, today+offset+span] instead.
private func seedOnline(stationID: String, offsetDays: Double?, spanDays: Double?) {
    guard let gate = ChsCurrentGateInfo.all.first(where: { $0.id == stationID }) else { return }
    let today = todayLocal(gate.tz)
    let start: Date, end: Date
    if let offsetDays, let spanDays {
        start = today.addingTimeInterval(offsetDays * 86_400)
        end = start.addingTimeInterval(spanDays * 86_400)
    } else {
        let w = Timeline.window(anchor: today)
        start = w.start; end = w.end
    }
    let period = 12.42 * 3600.0   // M2 tidal period, seconds
    let amplitude = 2.0           // kn
    var times: [Double] = [], speeds: [Double] = []
    var t = start
    while t <= end {
        times.append(t.timeIntervalSince1970)
        speeds.append(amplitude * sin(2 * .pi * t.timeIntervalSince(start) / period))
        t = t.addingTimeInterval(900)  // 15-min official-sample cadence
    }
    let window = ChsOnlineWindow(
        stationID: gate.id, iwlsName: "\(gate.name) (seeded)", timezone: gate.timezone,
        fetchedAt: appNow(), start: start, end: end,
        floodDirection: 0, ebbDirection: 180, times: times, speeds: speeds)
    _ = try? ChsModelStore.saveOnline(window)
}
```

- [ ] **Step 3: Run the extended offline test — the bar assertion must be RED**

`-only-testing:SlackwaterUITests/ScreenshotTests/testOnlineGatePagedBeyondItsWindowOffline`
Expected: FAIL at "the honesty card must keep the week-range bar" (the scaffold still drops it). The new two-block test should already PASS here (Task 3 landed the store) — its red state was Task 3's world, noted in its doc comment.

- [ ] **Step 4: Implement the scaffold change**

`Theme.swift` `ScrubDetailScaffold.body` — give the nil-timeline branch the bar, styled like the schedule card it stands in for:

```swift
if let timeline {
    scrubCard(timeline)
    scheduleCard(timeline)
        .padding(.top, 14)
} else {
    // #67 item 2: no timeline means the caller is showing its honesty card
    // below — but the bar (and its picker) need no timeline, and without
    // them that card is a dead end with no way back to a covered week.
    WeekRangeBar(anchor: anchor, today: todayLocal(tz), tz: tz, onTap: { showPicker = true })
        .background(SN.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(SN.cardStroke, lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.top, 14)
}
```

(`todayLocal(tz)` here only feeds the bar's Today/not-this-week label — no coverage decision rides on it.) Also update `testOnlineGatePagedBeyondItsWindowOffline`'s doc comment: the dead-end sentence ("no way to page back except the navigation back button") is now the fixed defect, and the strip-must-be-GONE assertion still stands — the bar is not the strip.

- [ ] **Step 5: Run both UI tests on one sim — green**

Same `-only-testing` pair as above plus the new test. Open the saved screenshots (`/tmp/slackwater-shots` or `$SHOT_DIR`) and look at `online-gate-far-block.png`: a real curve two months out, no honesty card.

- [ ] **Step 6: Commit**

```bash
git add Slackwater/Theme.swift Slackwater/SlackwaterApp.swift SlackwaterUITests/ScreenshotTests.swift
git commit -m "app: the honesty card keeps the week-range bar (#67 item 2)"
```

---

### Task 5: Full suite, push, PR

- [ ] **Step 1: `./scripts/test.sh`** (fast plan, both sims). Read the result bundles on failure (`build/results-fast-*.xcresult`), and re-run any live-network flake in isolation before blaming the branch (CLAUDE.md § shared test machine).
- [ ] **Step 2: Verify only our commits:** `git log --oneline origin/main..HEAD` — spec + plan + 4 implementation commits, nothing foreign. Rebase `--onto` if a foreign commit slipped in.
- [ ] **Step 3: Push and open the PR** (internal repo — no approval gate): title `Picker follow-ups: multi-block store, uniform back-pad, a way back (#67)`. Body: what each of the three changes does, the item 6 side-effect closure, the spec-vs-implementation commit-order note, and the standard generated-with footer. Do NOT merge.
- [ ] **Step 4: Comment on issue #67** mapping items → commits (1, 2, 4 shipped; 6 closed as a side effect — bounded 60d retention; 3 and 5 still open), and note the PR number.
