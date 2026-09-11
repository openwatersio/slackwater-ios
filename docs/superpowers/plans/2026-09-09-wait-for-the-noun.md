# Wait for the noun the next line reads (#341) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop three UI-test assertions in `DetailAndScrubTests` from reading the commentary pill's label before anything has waited for that label to change.

**Architecture:** Test-only change. Each `waitFor(pill, …)` that precedes a label assertion gets the label condition folded into its predicate, alongside `isHittable`, so the wait ends only when the strip has come to rest *and* the pill says what the next line asserts. No app code moves. The rule lands as one paragraph on `waitFor`'s doc comment.

**Tech Stack:** XCTest / XCUITest, `NSPredicate` format strings evaluated against `XCUIElement` (`isHittable`, `label` are KVC-readable — `stepMonth` already waits on `value`).

**Spec:** https://github.com/openwatersio/slackwater-ios/issues/341

## Global Constraints

- Line numbers below are for `origin/main` at `fd39b19` and match the issue's exactly.
- Implementers compile-check only (`build-for-testing` under `lockf -t 0`, see CLAUDE.md "The test machine is shared"). The coordinator runs the suite. A subagent's backgrounded `xcodebuild test` dies with its turn and corrupts the result bundle.
- Run `xcodegen generate` before any `xcodebuild` in a fresh worktree — `Slackwater.xcodeproj` is generated.
- Commit messages and the PR follow the `pr-writing` skill. No `Claude-Session` trailers (public repo).

---

## Root cause (read before editing)

The strip's chrome row (`Slackwater/TimelineStrip.swift:1319-1352`) is hittable only while `settled` is true. `settled` flips false on every `scrubTime` write and back to true 450 ms after the last one. So "hittable" *is* the at-rest signal — but only once motion has started.

Both jump actions write `scrubTime` synchronously (`TideDetailView.returnToNow` sets it to `live`; `scrubToCommentary` sets it to the next stop), then the scrubber animates the scroll and `scrollViewDidScroll` rewrites `scrubTime` from the offset every frame until `didEndScrollingAnimation` parks it (`TimelineStrip.swift:1240-1264`). Those intermediate times are "scrubbed away", so the pill reads `… later` mid-flight.

`XCTNSPredicateExpectation` evaluates once immediately. Right after `tap()` the app may not have processed the action: the pill is still hittable with the *old* label, `exists == true AND isHittable == true` is already true, the wait returns at t=0, and the next line reads the label mid-animation. That is the `'High 7h 43m later'` in the issue's run. #332's timeout scaling cannot reach it: scaling a wait that ends at t=0 changes nothing.

Waiting on `isHittable == true AND label <condition>` closes it: hittable is false from the first animation frame until 450 ms after parking, and the label condition rejects the one pre-action snapshot where the old label is still up.

### Site verdicts (`origin/main` line numbers)

| Site | What follows the wait | Verdict |
|---|---|---|
| `DetailAndScrubTests.swift:370` | `pill.tap()` | Sound. The same pre-intro hittable window as :439 exists here (`settleLayout` settles the strip's frame, which the intro never moves), but no label is read until after the tap and `settleScrub`, and the drag fallback re-stages. Leave. |
| `DetailAndScrubTests.swift:411` | `scrubClock != parked`, then the rate regex on the label | Sound, but load-bearing on the `settleScrub` at :410, not on the predicate: the 0.5 s hold at rest re-settles the pill with the finger still down, and it is the magnet's animated scroll after release (rewriting `scrubTime` every frame) plus `settleScrub`'s ≥250 ms that make the wait real. Delete :410 and this becomes the old :460. Leave. |
| `DetailAndScrubTests.swift:439` | `saidBefore.contains(" in ")`, then `pill.tap()` | **Fix.** First appearance; the intro seeds `scrubTime` two hours back (`Timeline.introStart`), so a slow machine that lets 450 ms pass before the intro's first frame shows a hittable pill reading `… later`. |
| `DetailAndScrubTests.swift:450` | `label != saidBefore`, `label.hasSuffix("later")` | **Fix.** Same race as :460 after the commentary tap. |
| `DetailAndScrubTests.swift:460` | `label.contains(" in ")` | **Fix.** The one that failed. |
| `MapSearchAndNavigationTests.swift:122` | prefix check `Slack/Max/Flood/Ebb` | Sound. The assertion holds at any scrub position; the wait only needs the pill to exist. Leave. |
| `OfflineCoverageTests.swift:381` | same prefix check | Sound, same reason. Leave. |

`ScreenshotTestCase.swift:436` (`tapDay`) uses the same predicate to guard a tap, not a label read. Not in scope.

Found in review, fixed in the same PR: `DetailAndScrubTests.swift:146-148` taps `week-picker-done` and reads `bar.label` with no wait at all — the same shape with the wait missing. Noted, not fixed (live lane, needs `--full`): `LiveFetchTests.swift:437-439` reads `dodd.label.contains("Downloading")` behind `appears(within:)` alone; its sibling at :416 waits on the label correctly.

---

### Task 1: Fold the label into the three commentary waits

**Files:**
- Modify: `SlackwaterUITests/DetailAndScrubTests.swift:436-467`
- Modify: `SlackwaterUITests/ScreenshotTestCase.swift:22-29` (doc comment only)

**Interfaces:**
- Consumes: `ScreenshotTestCase.waitFor(_:_:timeout:) -> Bool` (unchanged), `commentaryPill(_:)`.
- Produces: nothing new.

- [ ] **Step 1: Generate the project and confirm the baseline compiles**

```sh
cd /Users/clarkbw/src/openwaters/slackwater-ios-wt-341-waits
xcodegen generate
lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -5
```

Expected: `** TEST BUILD SUCCEEDED **`. If `lockf` fails immediately, a test run holds the machine — wait and retry; never force it.

- [ ] **Step 2: First appearance — wait for the reader's phrasing, not just the pill**

In `testCommentaryTapScrubsToTheStopItNames`, replace lines 436-442:

```swift
        // The pill fades in once the scrub rests, so hittability is the wait,
        // not existence.
        let pill = commentaryPill(app)
        XCTAssert(waitFor(pill, "exists == true AND isHittable == true"),
                  "no commentary pill on the tide detail")
        let saidBefore = pill.label
        XCTAssert(saidBefore.contains(" in "),
                  "parked on now, the commentary counts from the reader: '\(saidBefore)'")
```

with:

```swift
        // The pill fades in once the scrub rests, so hittability is the wait,
        // not existence — and the intro seeds the scrub two hours back, so a
        // pill that rests before the slide's first frame reads "later". Wait
        // for the phrasing the next line asserts.
        let pill = commentaryPill(app)
        XCTAssert(waitFor(pill, "isHittable == true AND label CONTAINS ' in '"),
                  "no commentary pill parked on now: '\(pill.label)'")
        let saidBefore = pill.label
        XCTAssert(saidBefore.contains(" in "),
                  "parked on now, the commentary counts from the reader: '\(saidBefore)'")
```

- [ ] **Step 3: After the commentary tap — wait for the strip's phrasing**

Replace lines 450-455:

```swift
        XCTAssert(waitFor(pill, "exists == true AND isHittable == true"),
                  "the commentary did not come back after the jump")
        XCTAssertNotEqual(pill.label, saidBefore,
                          "the commentary must name the next stop, not the one just landed on")
        XCTAssert(pill.label.hasSuffix("later"),
                  "scrubbed away, the commentary counts from the strip: '\(pill.label)'")
```

with:

```swift
        // Hittable alone is true at t=0: the jump writes `scrubTime` and the
        // pill only leaves hit-testing once the scroll's first frame lands.
        // The label is the noun the next lines read, so it is the wait.
        XCTAssert(waitFor(pill, "isHittable == true AND label ENDSWITH 'later'"),
                  "the commentary did not come back after the jump: '\(pill.label)'")
        XCTAssertNotEqual(pill.label, saidBefore,
                          "the commentary must name the next stop, not the one just landed on")
        XCTAssert(pill.label.hasSuffix("later"),
                  "scrubbed away, the commentary counts from the strip: '\(pill.label)'")
```

- [ ] **Step 4: After return-to-now — wait for the reader's phrasing**

Replace lines 459-463:

```swift
        app.buttons["detail-return-now"].firstMatch.tap()
        XCTAssert(waitFor(pill, "exists == true AND isHittable == true"),
                  "the commentary did not come back after returning to now")
        XCTAssert(pill.label.contains(" in "),
                  "back on now, the commentary counts from the reader: '\(pill.label)'")
```

with:

```swift
        app.buttons["detail-return-now"].firstMatch.tap()
        XCTAssert(waitFor(pill, "isHittable == true AND label CONTAINS ' in '"),
                  "the commentary did not come back after returning to now: '\(pill.label)'")
        XCTAssert(pill.label.contains(" in "),
                  "back on now, the commentary counts from the reader: '\(pill.label)'")
```

- [ ] **Step 5: Land the rule on `waitFor`'s doc comment**

In `SlackwaterUITests/ScreenshotTestCase.swift`, the doc comment above `waitFor` currently ends:

```swift
    /// Returns rather than asserts — the caller's own assertion, taken after
    /// the wait, is what reports the failure and names it.
```

Append one paragraph after it (before `@discardableResult`):

```swift
    ///
    /// Wait for the noun the next line reads. An element that stays in the
    /// tree and rewrites itself — the commentary pill on a jump — is hittable
    /// before the app has processed the tap, so `isHittable == true` alone is
    /// satisfied at t=0 and the label is read mid-transition (#341). Put the
    /// label condition in the predicate: `"isHittable == true AND label
    /// CONTAINS ' in '"`. Timeout scaling cannot reach a wait that never waits.
```

- [ ] **Step 6: Compile-check**

```sh
lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -5
```

Expected: `** TEST BUILD SUCCEEDED **`, no warnings in `DetailAndScrubTests.swift` or `ScreenshotTestCase.swift`.

- [ ] **Step 7: Commit**

```sh
git add SlackwaterUITests/DetailAndScrubTests.swift SlackwaterUITests/ScreenshotTestCase.swift
git commit -m "test: wait for the commentary's phrasing, not just its pill

A wait on 'exists AND isHittable' is already true the instant after a
jump tap, before the app has processed it: the pill stays in the tree
and rewrites itself. The wait returned at t=0 and the next line read the
label mid-scroll ('High 7h 43m later' on a return-to-now). Fold the
phrasing the next assertion reads into the predicate.

Closes #341"
```

Do **not** run the UI suite from this task. Report what compiled.

---

### Task 2: Re-trace the four sites the plan leaves unchanged (read-only, parallel with Task 1)

**Files:**
- Read: `SlackwaterUITests/DetailAndScrubTests.swift:360-430`
- Read: `SlackwaterUITests/MapSearchAndNavigationTests.swift:100-130`
- Read: `SlackwaterUITests/OfflineCoverageTests.swift:365-390`
- Read: `Slackwater/TimelineStrip.swift:1060-1095, 1195-1265, 1295-1352`
- Read: `Slackwater/TideDetailView.swift:15-20, 58-70, 238-250`

**Interfaces:** none. Output is a verdict per site, with the line in the app code that justifies it.

- [ ] **Step 1: For `:379` and `:420`**, trace what writes `scrubTime` between the preceding gesture and the wait, and state whether `settled` can still be true (hittable) when the wait first evaluates. For `:420` specifically: the press-and-hold is 0.3 s + drag + 0.5 s hold; `settled` returns true after 450 ms of rest — does the hold at rest re-settle the pill *before* release, and if so does the magnet's animated scroll after release write `scrubTime` before `settleScrub` and the wait run?
- [ ] **Step 2: For the Map and Offline sites**, confirm the assertion that follows is invariant under scrub position (prefix in `Slack/Max/Flood/Ebb`), so a t=0 return cannot produce a wrong label.
- [ ] **Step 3: Report** one line per site: `sound` / `unsound because <trace>`, plus any fifth shape you notice of the same class (`settleScrub` followed by `XCTAssertNotEqual(scrubClock…)` is a candidate — say whether its first 250 ms read can straddle an unprocessed tap). Do not edit files.

---

### Task 3 (coordinator): Run the class, tick the issue, open the PR

- [ ] **Step 1: Run `DetailAndScrubTests` on the iPhone simulator** (takes the lock; do not run from a subagent):

```sh
cd /Users/clarkbw/src/openwaters/slackwater-ios-wt-341-waits
SHOT_DIR=/tmp/slackwater-shots-341 lockf /tmp/slackwater-test.lock xcodebuild test \
  -project Slackwater.xcodeproj -scheme Slackwater -testPlan Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:SlackwaterUITests/DetailAndScrubTests \
  -resultBundlePath build/results-341.xcresult 2>&1 | grep -E 'Test Case|error:|\*\* TEST'
```

Expected: every `Test Case … passed`, `** TEST SUCCEEDED **`. Read the bundle if anything says "crashed with signal kill" — that is contention, not the change.

- [ ] **Step 2: Push and open the PR** against `main`, body per `pr-writing`, `Closes #341`, and tick the issue's seven checkboxes with the verdict table above as the comment.
