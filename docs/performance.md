# Performance

This document records measured user-facing performance. It is an evidence log, not a backlog: measurements name the build, device, OS, and boundary they cover; unmeasured paths stay unmeasured rather than inheriting a guess from a similar screen.

## Measurement rules

- Profile an optimized build. Debug timings are not product timings.
- Prefer a physical device. Simulator samples are useful for attribution, not for deciding whether a delay is acceptable.
- State the boundary. “Launch” can mean process start, scene connection, first commit, or first usable content, and those numbers are not interchangeable.
- Separate cold process launch from a repeat presentation in the same process.
- Read inclusive sample times as a call tree. Child costs overlap their parent; they must not be added together.
- Re-measure after every optimization. A stack that explains one run does not
  prove the next bottleneck.

On a simulator, sample immediately after launch as described in [CONTRIBUTING.md](../CONTRIBUTING.md#launch-performance):

```sh
sample <pid> 4 1 -mayDie
```

Look below `-[UIApplication _firstCommitBlock]` for synchronous first-frame work. On a device running iOS 26 or later, use Instruments' SwiftUI template as well: **Long View Body Updates** identifies app code, while **Other Long Updates** includes framework geometry and text layout.

## First load

**Boundary:** cold process launch to the first station-list frame. The UIKit first-commit block is the narrower diagnostic boundary inside it.

[Issue #317](https://github.com/openwatersio/slackwater-ios/issues/317) tracks this path. #319 moved full catalog decoding after the first frame and reduced distance ranking from about 170 ms to 6 ms. On the iPhone 17 simulator, Release, the first-commit block fell from 730–790 ms to about 325 ms.

Two later cold launches on an M2 iPad Pro 12.9-inch (6th generation), iOS 27.0, optimized build, reached the first visible frame in 345 ms and 462 ms including dyld. These runs straddle the usual 400 ms cold-launch target on fast hardware, so an iPhone measurement remains necessary.

### Current attribution

On 2026-10-02, current `main` was profiled in an optimized Release build with the shipping catalog on an iPhone 17 simulator running iOS 27.0. The gate and tour were already complete so the sample covered the station list rather than the first-run flow. Two runs produced:

| Work | Run 1 | Run 2 |
|---|---:|---:|
| UIKit first-commit block | 422 ms | 459 ms |
| SwiftUI hosting/layout | 309 ms | 355 ms |
| `StationListView.body` | 46 ms | 46 ms |
| Station identity-index decode | 18 ms | 17 ms |
| Distance ranking and grouping | 11 ms | 12 ms |

Within SwiftUI layout, roughly 150 ms sampled below `ScrollViewUtilities.sizeThatFits`. `ViewThatFits` and individual card construction accounted for only a few samples. The remaining first-frame cost is therefore dominated by SwiftUI `List` graph construction and scroll-content layout, not station prediction, card data, or ranking.

This matches SwiftUI's documented model: `List` is a feature-rich control that eagerly gathers row identities and creates visible rows plus a system-selected buffer. Keep identifiers cheap and each `ForEach` element's row count constant; Slackwater's measured Near Me rows already follow that shape. See Apple's [Demystify SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/) and [SwiftUI performance guidance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance).

The next useful experiment is a lightweight first frame that mounts the real list on the following run-loop turn. It defers rather than removes list layout, so keep it only if a physical-iPhone A/B trace shows a user-visible improvement. Replacing `List` with `ScrollView`/`LazyVStack` is not equivalent: the list owns the app's native swipe actions.

## Open detail view

**Boundary:** station-card tap to the first complete detail frame. Measure a cold presentation and a second detail in the same process separately.

On 2026-10-02, a cold tide-detail presentation was sampled twice in the same optimized simulator configuration as first load. A profiling-only trigger opened Friday Harbor (`noaa/9449880`) through the production navigation path after the station list settled. It was removed after measurement.

| Main-thread work | Run 1 | Run 2 |
|---|---:|---:|
| SwiftUI navigation update | 97 ms | 402 ms |
| Detail scroll sizing | 17 ms | 48 ms |
| `DetailHeader.body` | 8 ms | 35 ms |
| Initial timeline build | 6 ms | 22 ms |

These are 1 ms sampling counts inside the presentation transaction, not tap-to-pixel wall-clock latency. The four rows are inclusive and overlap; do not add them. Timeline drawing was split across several small branches, none larger than 10 ms. The large run-to-run variance is in SwiftUI navigation and layout, while timeline construction remains small. A physical-device trace with an interaction signpost is still required before setting a latency target or choosing an optimization.

Tide, harmonic-current, derived-gate, and online-gate details have different data paths; record the variant with every result. Attribute record resolution, initial timeline construction, schedule construction, and SwiftUI layout independently before changing the shared scrubber.

## Open map view

**Boundary:** map-button tap to a visible, interactive map with its initial pin state. Separate the first map presentation from later toggles.

Not yet measured. Capture style and resource loading, map-view creation, station-to-pin state construction, source insertion, and the first rendered frame separately. Record whether the run is offline and whether chart packs are already present; those conditions change the path materially.

## Search view

**Boundaries:** search-button tap to a focused, interactive search view; then a query edit to updated results.

Not yet measured. Separate keyboard/focus presentation from result work. Measure the first query after launch independently because it is the first path that needs search-only aliases from the station index; subsequent query edits should be reported as repeat-search latency.
