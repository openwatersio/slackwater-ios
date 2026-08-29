# Staged refactor: smaller files, less duplication, one source of truth

*2026-08-29. Slackwater 1.6.0, branch `refactor/file-splits`.*

## What this is

A staged plan for restructuring the app target so the code is easier to understand and change, for people and for agents. The logic itself is in good shape — the comments encode real incidents, the invariants (like `Timeline.window(anchor:)` being the window's only definition) hold, and the test suite asserts real behavior. What gets in the way is organization: four files carry 44% of the app's ~12,500 lines and are also the four highest-churn files of the last six months, the card and detail layer repeats itself structurally, and app-wide state has no seams for tests or previews.

The plan is ordered so every stage stands alone: the test lane gets fast first (every later stage runs it repeatedly), mechanical file moves next, behavior-preserving deduplication after that, state management last and only when it earns its cost. Bug fixes discovered along the way are filed as issues #230–#235 and are deliberately not part of these stages — they can land in any order, independently.

**Ground rules for every stage:**

- File moves are verbatim: types, comments, and blank lines move unchanged. The long comments encode hard-won bugs; every move carries them forward.
- Moved comments get one pass for hygiene: references to planning documents (spec sections, milestone numbers, prototype files, task numbers) are replaced with the constraint they stood for, so every comment makes sense to a reader with no history. Issue numbers and cross-references to live code (this repo's or the web repo's) stay. Watch the trap: M2, K1, Z0 in oceanographic context are tidal constituents, not milestones.
- Three tests scan sources by literal path (`TypeScaleTests`, `PhaseGlossTests`, `ColourAndFormTests` via `repoSource`/`appSources`) — any split updates them in the same commit.
- `project.yml` globs `Slackwater/` for the app target, so new files need no project edits; the widget target lists files explicitly, so check it before moving anything a widget compiles.
- Each split is compile-checked (`build-for-testing`), and the fast suite runs once per stage.

## Stage 0: speed up the fast test lane

First, because every checkbox below pays the suite's cost: each remaining stage runs the fast suite at least once, and stage 2 runs it after every extraction. Measured on CI run 33256671094 (2026-08-29): the fast lane is 1128s of wall clock, of which the 42 executed `ScreenshotTests` are 1041s (92%) — the unit suite is ~31s and the warm build ~56s. Each UI test averages ~25s: a fresh app launch, `waitForExistence` navigation, and hard `sleep()`s. The suite's contents are sound — it is a real assertion suite that also saves screenshots — so the work here is distribution and waiting, not coverage.

- [ ] Parallelize the UI tests across simulator clones, as its own commit with one green baseline run before any further stage work — this suite is stage 2's guard, so it gets proven stable before it starts guarding. XCTest distributes parallel work **per class**, and all 55 UI tests live in one `ScreenshotTests` class — so the test plan's `parallelizable` flag alone changes nothing. Split the class into ~4 similarly weighted classes (the helpers move to a shared base class or extension, tests move verbatim), then set `"parallelizable": true` on `SlackwaterUITests` in `TestPlans/Slackwater.xctestplan`. With 4 workers, ~1041s becomes roughly 300s and the fast lane lands near 7 minutes. The clones are managed inside one `xcodebuild` invocation, so the `/tmp/slackwater-test.lock` serialization is unchanged — this is not the two-xcodebuild SIGKILL trap. Cap the worker count (or keep that leg serial) for the live-IWLS tests in `--full`, so clones do not hit the API in parallel.
- [ ] Replace the hard `sleep(n)` calls in `ScreenshotTests.swift` (91 literal seconds, some in helpers called once per invocation, like `openSearch`) with predicate waits on the thing each sleep is actually waiting for. Saves ~1.5–2 minutes serial and removes the sleeps tuned for an idle machine that break first under load on the shared Studio. Land it right after the split, then watch a couple of runs before relying on the suite as a guard — a subtly wrong wait shows up as intermittent failures, the worst thing to have in the guard mid-refactor. If it flakes, revert and defer; parallelization delivers most of the win alone.
- [ ] Fallback if 4 simulator clones prove too heavy for the shared Mac: batch tests that launch with the same seed into single launch-then-walk-through journeys — 42 fresh launches are ~4–5 minutes of pure launch overhead. Skip this if parallelization lands; it trades per-test granularity for time the clones already recover.
- [ ] Longer term, and in no stage's way: migrate render assertions ("this view shows X") to snapshot tests in the unit target — `WidgetSnapshotTests` already proves the pattern here, and each migrated test goes from ~25s to milliseconds. Gradual, one test at a time.

## Stage 1: split the app and service files

Pure file moves, no signature or access-level changes. The one sanctioned behavior change: UI-test seed hooks move behind `#if DEBUG`, so the seed functions (including a model-store wipe) no longer ship in release binaries.

- [x] `SlackwaterApp.swift` (1,814 lines) → `SlackwaterApp.swift` (app + `RootView`, 59 lines), `TestSeeds.swift` (`#if DEBUG`), `GateView.swift`, `StationListView.swift`, `StationChooser.swift`, and the card views appended to `StationCard.swift`.
- [x] Comment-hygiene pass over the six files above.
- [x] `ChsFitService.swift` (1,134 lines) → the orchestrator stays (queue, fit loop, auto-fit policy, 768 lines); `IwlsClient.swift` (`IwlsFetcher`, `ChsChunkStore`, the IWLS sample types), `ChsFitter.swift` (the JavaScriptCore bridge), and `OnlineGates.swift` (the online-gate fetch extension and its store helpers). None of the extracted types touch the service's actor-isolated state; the file is app-target-only.
- [x] `MapScreen.swift` (837 lines) → `MapPinState.swift` (pin tone derivation + `PinFeaturesCache`, covered by `NationalScaleTests`), `MapStyleBuilder.swift` (the style-JSON builders and the map palette), keeping the delegate and representable as `MapScreen.swift` (224 lines).

## Stage 2: deduplicate the cards and detail views

Behavior-preserving extraction of the copy-paste layer. The screenshot suite is the guard: one mechanical extraction per component, full suite after each. Accessibility identifiers the UI tests key on (`chs-pending-*`, `provisional-reading-badge`, `slack-window`, the card strips) must survive each extraction unchanged.

- [ ] One switch over station kinds. `StationListView` carries five parallel switches over `StationItem` (`open`, `navLink`, `itemCard`, `resultCard`) plus `RecentRowLabel.load`. A `route` property and a `card(imperial:km:)` builder on `StationItem` collapse the view-producing four; `load` keeps its own switch because it produces state, not views. Adding a station kind then means one edit, not five.
- [ ] Shared card pieces. One `SlackPill` (three copies exist, each commented to match the others), one `pending(...)` helper (three verbatim copies), one `CurrentReading` row (speed + `CompassArrow` + cardinal), one `currentNextLine` (two copies differing only by the tilde).
- [ ] `CurrentReadout`, shared by `CurrentDetailView` and `OnlineGateDetailView`. Their readout blocks differ on exactly one axis — the provisional treatment (amber tint + tilde) — which becomes a single optional style parameter instead of eight inline ternaries. The extraction will surface that the amber currently applies at three different opacities; pick one deliberately.
- [ ] `ScrubWindow`, an observable owning `live`/`scrubTime`/`anchor` and the one `returnToNow()`, replacing four verbatim copies across the detail views. This turns the "anchor drives geometry, today drives language" rule from a four-file review checklist into a type.
- [ ] Generic `ChsFitState<Record>` replacing the twin `ChsState`/`ChsCurrentState` enums and their duplicate `state(_:)`/`currentState(_:)` accessors. Callers spell only the method names, never the enum types, so the blast radius is the three files that call them.

## Stage 3: split the timeline and theme files

After stage 2, so the dedup diffs stay readable. Pure moves plus deletion of code nothing ships.

- [ ] Out of `TimelineStrip.swift` (1,724 lines): the current-series analysis (`sampleEvents`, the two segment functions, `currentPeakToPeakRange`) moves beside `SlackWindow.swift`, merging `slackFillSegments`/`currentExcessSegments` — 36-line twins differing by one predicate — into one function; `SchedulePill`/`ScheduleEntry`/`MultiDaySchedule` move to `MultiDaySchedule.swift`. Leaves the file the strip: `Timeline`, `TimelineData`, `TimelineGeo`, `TimelineCanvas`, `TimelineScrubber`, `TimelineScrubStrip`.
- [ ] Out of `Theme.swift` (1,085 lines): `ScrubDetailScaffold` + `ScrubWhen` + `ReturnToNowSlot` + `WeekRangeBar` + `WeekPickerSheet` + `DetailFooter` move to `ScrubDetailScaffold.swift`, giving the shared detail anatomy a filename that says so; `RecentsStore` + `FavoritesStore` move to `Stores.swift`. Leaves the file tokens, the clock, and formatting.
- [ ] Delete dead code: `SN.speedInk` and its test (zero app callers), `currentFillStops`' non-schematic branch and the four tests pinning it (the app always passes `schematic: true`; if the ramp fill is intended to return, keep it and say so where it lives), and the `Timeline.speedRampAnchorsKn` alias (its rationale moves to `currentSpeedRampAnchorsKn`).

## Stage 4: state and seams

Deferred until the work above lands, and worth doing only when the pain is felt. This is also the on-ramp to Swift 6 language mode, where the global mutable state (`gateSearchHandoff`, `pendingDeepLink`, `WidgetReload.trigger`) stops compiling.

- [ ] An `AppSettings` value through `@Environment`, replacing eleven `@AppStorage` declarations across six files and the eight `imperial:` parameter drills — one propagation strategy instead of two opposite ones in the same view tree, and one clamped reader for the slack threshold.
- [ ] Replace `gateSearchHandoff`/`pendingDeepLink` with `@State` on `RootView`, handed down as init parameters.
- [ ] Injectable `arguments:` parameters (the pattern `CurrentFill.swift` and `MapScreen.swift` already use) for the files that parse `CommandLine.arguments` at static init: `LocationService`, `FavoritesCloud`, `ChsFitService`, and the stores in `Theme.swift`.
- [ ] Make `SettingsView` observe `PremiumStore` (the HIG audit's item 13), and give `PremiumView` a smoke UI test — it is the one revenue-facing screen with no coverage of any kind.

## Not part of this plan

The following is in good shape, some of it hard-won, and no stage touches it:

- `Timeline.window(anchor:)` and the anchor/today split — the one-definition rule holds everywhere; keep it that way.
- The `FillField`/`PatchField` binary decoders and their byte-layout documentation.
- `ScrubDetailScaffold`'s slot design (stage 3 only renames its file).
- `TimelineScrubber`'s nudge/magnet coordinator.
- `PinFeaturesCache`'s lock discipline — its own comment explains why it is not an actor.
- `AppGroup`, `DeepLink`, `FavoritesCloud`, `ChsQueue`, `chunkPlan`'s absolute 7-day cache grid.
- `scripts/test.sh`'s lock-based serialization. The UI tests' assertions and method names also stay as they are — stage 0 splits the class only so XCTest can distribute it; test bodies move unchanged, and their comments get the same hygiene pass as any other move.

## Related issues

Bugs found while surveying, filed separately so they can land in any order: #230 (fit windows follow the device's time zone), #231 (online gate detail rebuilds its timeline per scroll frame), #232 (station list rescans the catalog per render), #233 (slack readouts bypass the timeline's threshold), #234 (corrupt catalog loads silently as zero stations), #235 (small scrubber drift across detail views).
