# Picker follow-ups: multi-block storage, uniform back-pad, a way back from the honesty card

**Issue:** #67 items 4, 1, 2 (in that build order). Items 3 and 5 stay open; item 6
closes as a side effect (see Retention).

One branch, one PR, three logical commits — each commit builds on the previous.

## Commit 1 — Multi-block storage (item 4)

The single `ChsOnlineWindow` per station becomes a store of disjoint blocks:

```swift
struct ChsOnlineStore: Codable {
    var schemaVersion = 2
    let stationID: String
    var blocks: [ChsOnlineWindow]   // disjoint, sorted by start
}
```

- **Save** (`ChsModelStore.saveOnline`): insert the incoming block; union any blocks
  that overlap or abut within `ChsOnlineWindow.sampleInterval` slack — the existing
  `merging` sample-union logic minus its disjoint guard. Genuinely disjoint blocks
  stay separate. A far-forward pick no longer discards today's block; paging back
  reads it from disk instead of the network.
- **Coverage**: `covers` answers true only when a *single* block spans the full
  `Timeline.window` for the anchor. A span straddling a gap between blocks must
  never claim coverage — the same "no strip with a dead zone" rule the single
  window enforces today, now enforced across blocks.
- **Reads**: `OnlineGateDetailView` uses the block covering the anchor;
  `cardState` uses the block containing now (no block → same no-reading path as
  no file today).
- **Migration**: decode `ChsOnlineStore`; on failure decode the legacy single
  `ChsOnlineWindow` and wrap it as one block. Old files keep working; the first
  save rewrites in the new shape. UI-test seeds move to the new shape.
- **Retention**: one rule at save — drop samples older than
  `min(today − retentionDays, incoming.start)` across all blocks, delete empty
  blocks. `retentionDays = 60`. The `min(…, incoming.start)` term keeps the
  existing guard: a fetch for a deliberately-picked old week is never pruned by
  its own save, so it renders; the next save for a different anchor may prune it
  once it ages past 60 days. This is issue #67 item 6's named fix ("bounded
  backward retention") — item 6 closes with this commit. The forward direction
  stays uncapped per the existing `ponytail:` note (~90KB per 30 paged days).

## Commit 2 — Unconditional 48h back-pad (item 1)

`Timeline.window` loses its `today` parameter and the `anchor == today`
conditional:

```swift
static func window(anchor: Date) -> (start: Date, end: Date) {
    (anchor.addingTimeInterval(-backHours * 3600),
     anchor.addingTimeInterval(forwardHours * 3600))
}
```

Every window is `[anchor − 48h, anchor + 180h]`.

- **Why**: noon park sits 12h past the window start (216pt at 18pt/h); half a
  full-width 13" iPad pane is ~688pt, so the pad behind noon needs ≥ ~38h of
  data. 48h — the pad today's window already carries — gives noon 60h (1080pt)
  behind it: no dead space on any pane. Clamping the scroll offset stays
  rejected (readout would disagree with a tapped schedule row).
- **Ripples, all simplifications**: `ChsOnlineWindow.covers(anchor:)` loses
  `today` too; the "one snapshot of today" / "two clocks answering one question"
  comment blocks in `OnlineGateDetailView` and `ChsModelStore` reduce to normal
  code; the exact-equality back-pad bug class is gone.
- **Fetch**: the online fetch span follows `Timeline.window`, so a picked week
  fetches 48h more (~192 samples, ~6KB). Commit 1 is what makes that
  non-destructive.
- **UI**: a picked week's strip shows two days of run-in before the picked day —
  exactly what today's strip already does. `WeekPickerSheet.onPick`'s noon-park
  comment updates (216pt claim no longer load-bearing). `weekRangeLabel`,
  `scheduleRange`, and the schedule list are anchor-forward and unchanged
  (item 5 untouched).

## Commit 3 — The honesty card keeps the way back (item 2)

In `ScrubDetailScaffold`, when `timeline == nil`, still render `WeekRangeBar`
as its own card-styled row in the schedule card's slot. The bar needs only
`anchor`, `todayLocal(tz)`, and the picker tap — none require a timeline. It
already carries the "not this week" amber tag and opens the unbounded picker,
so from the amber card the user can jump straight back to any covered week.
No new paging UI. The "Try <nearest> instead" link stays. Only the online gate
ever has a nil timeline; the three `@State`-backed details are untouched.

## Testing

- **Unit**: block union vs disjoint vs abut-within-slack; `covers` refusing to
  span a gap; retention protecting the incoming fetch and pruning a 60-day-old
  block on a later save; legacy-file migration; `window(anchor:)` shape
  (uniform back-pad).
- **UI (hermetic)**: `testOnlineGatePagedBeyondItsWindowOffline` updates — the
  strip stays gone, the week-range bar now survives; new path: from the honesty
  card, open the picker, return to a covered week, the detail renders.
- **Out of scope**: item 3 (the `SLACKWATER_FULL` online paged-beyond-window
  twin) and item 5 (DST schedule range).

## Process

Worktree `../slackwater-ios-wt-picker67`, branch `picker-67-followups`, PR to
`main` (never self-merged). PR notes item 6 closes as a side effect; issue #67
gets a comment mapping what shipped.
