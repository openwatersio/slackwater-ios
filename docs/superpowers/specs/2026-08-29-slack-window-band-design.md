# Slack window as band and inked curve

**Status:** spiked on `currents/slack-window-band` 2026-08-29, approved visually in chat. Not
yet a PR — `main` is mid-reorganisation, so this is filed to pick up later.

## The problem

The current track drew slack as *area under the curve*: a green fill bounded above by the
sine, between the interpolated `±slackThreshold` crossings, with a sine-envelope gradient
along its length and dashed vertical rails at the window ends.

Bounding the fill by the curve was a deliberate honesty move — a rectangle up to the
threshold line would claim "slack" for water that is measurably not slack. But it made the
mark's height a function of how steep the curve happened to be there, so the *same* window
drew a tall lens at a lazy gate and a sliver at a violent one. The reader cannot compare two
windows, and the space between the dashed rails read as empty rather than as the answer.

The sine envelope compounded it: a long window faded at both ends for no reason the data
supports, and a short one never reached full colour at all.

## The change

Two marks, split by what they each claim.

**The band — what "slack" is set to.** One flat `SN.go` rectangle spanning `+slackThreshold`
to `-slackThreshold` vertically and the *entire* strip width horizontally. It is the user's
slack-speed setting made visible everywhere at once, not just where a window happens to fall,
so changing the setting in Settings has a legible effect across the whole chart. It claims
nothing about time. Replaces the two 1pt threshold rules, which are now the fill's own edges.

**The curve — when it is happening.** Between each window's start and end the pale
`0xDFEEE0` track is overdrawn in `SN.go` at width 4 (against 2 elsewhere). Endpoints come
from `velocityAt` on the interpolated crossings, so the green begins and ends exactly where
the curve meets the band edge rather than at the nearest 10-minute sample.

Drawing the window *on* the curve rather than behind it is what resolves the original
tension. The mark is the water, so it cannot over-claim: a peak that rises out of the band
breaks the green, and a peak that stays inside keeps it unbroken. Height is no longer part of
the encoding, so two windows are comparable by length alone. Both marks derive from
`slackThreshold`, so they cannot drift apart.

**Colour.** `SN.go` (`goHex = 0x88B868`) at `0.56` for the band and full opacity for the
curve — the same green `StationGlyph.colour(for: .slack)` returns for the SLACK pill, so the
chart and the schedule pill are visibly one claim.

Removed with no replacement: the sine-envelope gradient, the dashed rails, and the two
threshold rules. Windows come from `data.slackWindows` (real slack events) rather than every
sub-threshold crossing, which is why adjacent windows separated by a sub-threshold blip stay
one continuous green run — the property `suppressesSlackLabel` already assumes.

## The slack time label

`TimelineStrip.swift`, the `.slack` case of `drawCurrent`: drop the label from
`.system(size: 18, weight: .semibold).monospacedDigit()` in `SN.foam` to
`.system(size: 12).monospaced()` in `.white.opacity(0.6)` — exactly the treatment the max
flood/ebb times already use under the track.

The 18pt semibold was sized when the exact zero crossing was the answer the screen existed to
give. It no longer is. The window is what a passage is planned around, it is now carried
visually by the band and the inked curve, and the magnet already snaps to it. An instant
rendered louder than its own window inverts the hierarchy.

Position is unchanged: `slackRangeY` stays `curTop - 18`, which mirrors `maxTimeY`'s
`curBottom + 18` and gives the smaller label the same optical gap the bottom row has.

## Scope

`TimelineStrip.swift` only, inside `drawCurrent`. Per CLAUDE.md the strip has four
presentation consumers — `TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView`,
`OnlineGateDetailView` — and all four must be reviewed, though only the current track is
touched, so the tide-only detail is unaffected by construction.

The schematic branch (`data.speedsAreSchematic`) is untouched: a schematic gate has no
certified speeds to put a threshold band against.

The widget extension consumes `WidgetSnapshot` and draws no curve. Out of scope.

Derived gates have no `slackWindows`, so they show the band with no inked run and keep the
existing hairline tick at the slack instant. Confirm this reads as "no measurable window"
rather than as a rendering failure.

## Follow-ups

- **`slackFillSegments` is now dead app code.** `TimelineStrip.swift:261`, kept alive only by
  its own test at `TimelineTests.swift:655`. It existed for the sine-envelope fill. Delete
  both. `currentExcessSegments` stays — the yellow/red excess fill still uses it.
- **Tune constants.** `bandGreen = 0.56`, `slackInk = SN.go`, `slackInkWidth = 4`, all marked
  `ponytail:` at their use sites. Settled by eye on an iPhone 17 simulator, not measured.
- **Contrast check.** The pale curve and the `SN.foam` slack dot draw over a 0.56 green band.
  Verify against the accessibility contrast floor, and check the band under Increase Contrast.
  Note the window encoding is not colour-only — stroke width carries it too.
- **Headroom.** With a 12pt slack label instead of 18pt there may be spare height above
  `curTop` worth reclaiming. Cosmetic, and it changes shared geometry, so not in this change.
- **Screenshots.** CONTRIBUTING requires before/after on a visual PR.
- **Suite.** Only compile-checked so far (`** TEST BUILD SUCCEEDED **`). `./scripts/test.sh`
  is the gate, and the snapshot/UI tests are the ones most likely to move.
