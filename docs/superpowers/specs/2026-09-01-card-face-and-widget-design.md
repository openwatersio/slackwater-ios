# Card face on the list and the medium widget — design

Follows `2026-09-01-detail-strip-card-look-design.md`, which brought the
station-card curve to the detail scrubber and then refined both. This spec
closes the loop: the card adopts the two rules the detail settled on
(readings hang off the turn; the set is always shown), and the medium
home-screen widget renders the card itself instead of its own sparkline.

Normative references: `docs/current-charts.md` and the detail-strip spec
above. Where they disagree with this document, they win and the
disagreement is listed in §6.

## 1. What does not change

- `StationCardGraph`'s window and geometry: one swing back, three ahead,
  the past faded, the green run per merged window with the opening dot,
  the axis times at each run's opening (current) or each turn (tide).
- The card's header: name, region or distance line, reading top-right.
- The small "Next Event" widget and the lock-screen accessories.
- `WidgetSnapshot` and the small widget's provider: the medium widget
  stops reading `sparkline`, `tideMovements`, `state` and `value`, but the
  snapshot keeps them for the small widget until a later cleanup.
- The four detail views.

## 2. Card graph readings

The reading hangs off the turn or peak toward the plot middle, exactly as
the detail strip does since its §4 and §5 amendments, using the same
`CurveStyle.hang*` constants: the value `hangOffset` toward the middle,
`hangValueRise` above that point, the pointer `hangGlyphDrop` below it.

- **Value only, no unit.** The card's top-right reading carries the unit
  once; "3.0 kn / 1.3 kn / 1.5 kn" along the curve becomes "3.0 / 1.3 / 1.5".
  The tilde for a provisional gate stays on the value.
- **Tide**: dot, value, to-bar arrow (`⤒`/`⤓`) under it, as the detail.
- **Current**: no dot; the value with the set arrow (the SF `arrow.up`
  rotated to the bearing) under it, as the detail.
- The middle band, `bandY`, and the card's private `pointerOffset`,
  `valueFontSize`, `pointerFontSize` go; the card reads the hang constants.
- The `labelEdgeMargin` rule (an extreme near the card edge keeps its dot
  and axis time, drops its value) stays.
- VoiceOver keeps reading "value with unit at time": the accessibility
  value is built from the formatted strings, which keep their unit.

## 3. Card header for currents

The SLACK pill goes. The current card's reading behaves like the detail's
floating readout: always the speed with its unit, and under it the set.

- Line one: `formatSpeed(abs(signed))` + unit, bold, as today for
  flood/ebb. Tilde for a provisional gate.
- Line two: phase word, cardinal, compass arrow — the sign of the velocity
  picks the flood or ebb bearing. Inside a slack window (`currentPhase ==
  .slack`) the word is "Slack" in the go colour and the cardinal and arrow
  still show which way the water is setting. Under 0.05 kn the cardinal
  and arrow give way to a dim neutral mark of the same footprint so the
  header never resizes.
- The derived-gate `.gate(phase)` pill is unchanged: it knows no speed and
  no set (current spec §9).
- The recents row's "slack" word (`RecentRowLabel.reading`) is unchanged;
  it is a one-line text row, not the card face.

## 4. The medium widget renders the card

"Today's Curve" (`DayCurveWidget`, `.systemMedium`) shows the list card:
`StationCard(name:region:km:graph:)` with `ConditionsItem` as its trailing
reading, built from the same record builders the list uses. The widget's
own `DayCurveContentView` becomes a thin wrapper and its sparkline canvas,
`stateColor`, warning text and `curveAccessibilityValue` are deleted.

### 4.1 What moves into the widget target

- A new `Slackwater/Palette.swift`, listed in the widget target's sources:
  `extension Color` (hex init), `enum SN`, `enum CurveStyle`,
  `CanvasBackground` if the card uses it, the formatter cache with
  `cardTime`, `clockTime`, `chartTime`, `shortWeekday`, and `CompassArrow`.
  Everything else in `Theme.swift` stays where it is. The
  `ColourAndFormTests` file allowlist that names `Theme.swift` for colour
  literals adds `Palette.swift`.
- `Slackwater/StationCardGraph.swift`, listed in the widget sources. Its
  `extension ChsOnlineWindow { cardGraph }` needs `sampleEvents`, which
  lives in `TimelineStrip.swift`; `sampleEvents` moves to
  `SlackWindow.swift` (a pure function over `CurrentPoint`, already the
  home of the window predicate, already in the widget target).
- `StationCard` and `ConditionsItem` move out of `StationCard.swift` into
  a new `Slackwater/StationCardFace.swift`, listed in the widget sources,
  together with whatever small value types they need that are not already
  there (`CardState`, `CurrentCardState` live with the records;
  `DerivedPhase` with the gates — the implementer verifies each symbol's
  file against the widget's source list before adding one). `StationCard.swift`
  keeps the list-only views: `RecentRowLabel`, `StationCardView`,
  `CurrentCardView`, the derived-gate card, previews.
- `StationCard` gains one flag, `chrome: Bool = true`. The list keeps the
  rounded clip and shadow; the widget passes `false` and supplies
  `SN.cardFill` through `containerBackground(_:for:)` so the widget's own
  rounded corners do the clipping. Nothing else about the card changes.

### 4.2 Data

The widget provider already loads a `WidgetStation` per entry. It now also
needs the record so it can call `cardGraph(at:)` and `cardState(at:)`:
`WidgetStationLoader` returns the record alongside the engine station (or a
closure that builds the graph), keeping one builder per record kind — no
second implementation of the graph in the extension. The graph is built at
the entry's date, so each hourly entry shows the curve as of that hour,
with `now` at the entry date.

Distance: the widget has no fix; `km` is nil and the region line shows as
the list does for a card without a distance.

### 4.3 Sizing

The medium family is about 158pt tall on a phone; the list card is 168
minimum. `StationCard`'s `minHeight` becomes a parameter with the list's
values as defaults; the widget passes the family's height by letting the
card fill its container (`maxHeight: .infinity`) and the graph's top inset
stays 54 so the header keeps its room. If the graph's axis row lands under
the widget's safe margin on a real device, the inset is the one knob to
turn; it is not turned pre-emptively.

### 4.4 Memory and time

The card builder samples about 150 points and a handful of extremes per
graph; well inside the extension's budget. CHS records still come from
`ChsModelStore` as today.

## 5. Tests

- `SlackWindowTests` gains nothing new: the label placement is drawing.
- `TypeScaleTests` allowlist entry `StationCardGraph.swift:cardGraph` stays;
  the value strings still carry the unit for VoiceOver and the axis time,
  and the canvas applies the mono trait.
- `ColourAndFormTests`: the hex-literal file allowlist adds `Palette.swift`;
  the direction-colour tripwires keep passing (the card's tide tints are
  the graph tokens, not `SN.flood`/`SN.ebb`).
- `WidgetSnapshotTests` keep passing unchanged.
- A compile of the `SlackwaterWidgets` target is part of every task's
  check (`xcodebuild build-for-testing` builds it as an embedded target).
- Screenshots: the list (`m2-list-mixed.png`, `m1-list.png`) and the
  widget gallery (`WidgetsGalleryView` in the app) are opened and checked:
  values without units near the curve, the current header showing speed
  and set with no pill, the medium widget indistinguishable from the card.

## 6. Deviations

- Current spec §5.4 asks for a dot at each peak; the card, like the detail,
  draws none (product decision, recorded in the detail-strip spec §8).
- Current spec §6.4 warns against hue restating direction; the card's tide
  turn dots stay teal/amber as PR #252 shipped them. Tide is not the
  current spec's subject.

## 7. Out of scope

- The small widget and accessories.
- Trimming `WidgetSnapshot` of the fields only the old medium view read.
- VoiceOver for the strip and the card's slack windows (PR #252's open item).
