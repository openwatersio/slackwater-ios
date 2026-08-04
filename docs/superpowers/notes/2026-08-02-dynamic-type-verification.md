# Dynamic Type verification — the SF branch, across the size range on both devices

Task 6 of `docs/superpowers/plans/2026-08-02-sf-and-dynamic-type.md`. The unit
tests in `SlackwaterTests/TypeScaleTests.swift` assert what each tier *contains*.
They cannot assert which tier gets picked, whether anything clips or truncates,
or whether the result reads. This is the record of measuring that.

## Devices — never the suite's

`scripts/test.sh` drives `iPhone 17` and `iPad Pro 11-inch (M5)`. Driving either
while a suite runs collides with it (nine spurious UI-test failures once, an
accumulated-cruft 12-failure run another time). Verification ran on two
throwaway clones created for the purpose and deleted afterwards:

```
sw-verify-phone   iPhone 17            B3381E7D-E5B1-4EE2-9821-6DFE4E8719E1
sw-verify-pad     iPad Pro 11" (M5)    2EAFBBC2-ADD6-412D-9268-7F0744C46B3B
```

Building against the shared destinations is fine — it is driving the device that
collides.

## The matrix

Six content-size categories × two devices × six screens. Every category string
was checked against `simctl help ui`'s enumerated list first, then set and **read
back** — an invalid string makes UIKit fall back to the default silently, which
is how two "different" captures come out identical.

| set | read back |
|---|---|
| `extra-small` | `extra-Small` |
| `small` | `Small` |
| `large` | `large` |
| `extra-extra-large` | `extra-extra-large` |
| `accessibility-large` | `accessibility-large` |
| `accessibility-extra-extra-extra-large` | `accessibility-extra-extra-extra-large` |

`simctl` echoes the first two capitalised. That is a formatting quirk, not a
failed set — a case-insensitive compare is the right check, and a strict one
(the first pass here) silently skips those two cells, which is the same class of
mistake as the trap itself.

Screens per cell, driven by a temporary `SlackwaterUITests/VerifyShots.swift`
harness (deleted before commit) that saved a PNG **and** a frame dump of every
`staticText`/`button`/`image`/`textField` per screen:

- station list, top (tide + current cards, My Location hero, pending CHS cards)
- station list, scrolled to the bottom (the FAB clearance)
- search overlay with `victoria` typed, offline + CHS reset (pending card in the same pass)
- the first-run gate
- a tide detail view (Friday Harbor)
- a same-device width comparison: 320pt iPad sidebar vs the full-width search overlay

86 PNGs and 86 frame dumps in the final pass (plus 62 in the pre-fix pass kept as
before-evidence). Not committed — they live in the session scratchpad.

An early pre-fix pass was captured the same way and then discarded as *the*
matrix: one cell of it landed after a rebuild, which makes it a mixed-binary
matrix, and a matrix spanning two binaries proves nothing. The whole thing was
re-run on the fixed build.

**On proving the matrix is real.** All 86 PNGs hash differently, but that is a
weak proof and should not be leaned on: the status-bar clock alone makes any two
screenshots differ. The real evidence the overrides took is the *geometry*, which
moves monotonically with the category and cannot come from a silent fallback to
the default:

| category | card glyph | gate capsule | search field |
|---|---|---|---|
| `extra-small` | 20.7 | 54.0 | 18.7 |
| `large` | 24.0 | 54.0 | 22.0 |
| `extra-extra-large` | 27.3 | 54.0 | 27.0 |
| `accessibility-large` | 40.3 | 64.0 | 41.3 |
| `accessibility-XXXL` | 56.7 | 149.3 | 65.0 |

(iPhone 17, points. Gate capsule is the `Use My Location` button's measured
height; search field is the `TextField`'s intrinsic height inside its capsule.)

## Which tier got picked

Measured by field presence in the frame dump: a `.distance` line matches
`^\d+\.\d+ nm$`, a `.detail` line is the `High 5.2 ft · 8:22 AM` shape. Both are
absent in `.reduced` and present in `.full`.

The tier is **per card**, not per screen, which is the point of measuring fit
rather than thresholding on `dynamicTypeSize`. In one iPad sidebar capture at
`extra-small`, "Point George" and "Pear Point" are `.full` while "Wasp Passage
narrows" and "Upright Channel narrows" — same column, same instant, same text
size, longer names — are `.reduced`. The card sheds when *its own* content stops
fitting.

The My Location hero, present in every cell, as the constant probe:

| | `xs` | `s` | `L` | `XXL` | `AX-L` | `AX-XXXL` |
|---|---|---|---|---|---|---|
| iPhone 17, 402pt list | full | full | full | full | reduced | reduced |
| iPad sidebar, 320pt | reduced | reduced | reduced | reduced | reduced | reduced |

The phone sheds between `extra-extra-large` and `accessibility-large`. The iPad
sidebar has already shed at `extra-small` — the narrowest cell in the matrix is
narrow enough on width alone.

### Width, not type size — proved inside a single capture

The strongest evidence is one screenshot. iPad Pro 11", search overlay open over
the sidebar, one station — Friday Harbor — rendered twice in the same frame
dump, at `extra-small` (the *smallest* category, so nothing here can be blamed
on enlarged type):

| where | width | name at | `.detail` line | tier |
|---|---|---|---|---|
| search overlay card | ~800pt | `x=68.5 y=62.0` | `High 5.2 ft · 8:22 AM` | **full** |
| sidebar hero card | 320pt | `x=86.5 y=134.8` | *(absent)* | **reduced** |

Same device, same instant, same station, same text size. Only the container
width differs, and the tier differs with it. The split holds identically at
`small`, `large`, `extra-extra-large` and `accessibility-large`. That is exactly
the behaviour the first cut of this type lost, and the reason the card adapts by
measured fit rather than by a `dynamicTypeSize` threshold.

The plan's named risk — `ViewThatFits(in: .horizontal)` inside a `List` row
measuring against an unbounded proposal, so the full tier always wins and the
tiers never engage — did **not** happen. The tiers engage on both devices.

## What the shots exposed, and what changed

### 1. Tier picked by the length of a prose sentence, not by fit — FIXED

`StationCard.content(for:)` carried `message` *inside* both `ViewThatFits`
candidates. `ViewThatFits` compares each candidate's **ideal** width, and a
`Text`'s ideal width is its unwrapped single line — so the message's ~470pt ideal
dominated both candidates, neither ever "fit", and every card carrying a long
message fell through to `.reduced` no matter how wide the container or how small
the type.

Caught as two adjacent Near Me cards disagreeing at identical width: "Victoria
Harbour" (short message, "Downloading Canadian tidal predictions…") kept its
`0.1 nm`; "Selkirk Water", "Gorge at Aaron Point" and "Gorge at Tillicum" (long
message, "Queued — Canadian tidal predictions download once, then work offline.")
all lost theirs — at `extra-small`, on a 402pt phone, where nothing is short of
room. The message is byte-identical in both tiers, so it has no business being
measured by the picker.

Fix: `content(for:)` is now the identity row alone; `message` and the card chrome
moved out to `body`, outside the `ViewThatFits`. Chrome is also now built once
instead of once per candidate.

Measured, iPhone 17 `extra-small`, same three cards:

| card | before | after |
|---|---|---|
| Victoria Harbour | `0.1 nm` | `0.1 nm` |
| Selkirk Water | *(absent)* | `1.0 nm` |
| Gorge at Aaron Point | *(absent)* | `1.6 nm` |
| Gorge at Tillicum | *(absent)* | `2.0 nm` |

The hero card's frames are unchanged to the tenth of a point.

### 2. The station name truncating in the iPad sidebar — FIXED

iPad Pro 11" sidebar at `accessibility-XXXL`: the My Location hero's name came out
`Vi / ct / …`. Frame dump: the name got `w=50.0 h=199.0` — three lines and an
ellipsis — while `region` directly below it got `w=67.5 h=261.0`, five lines,
untouched. This is the silent half of the failure table: a `Text` given too
little room drops content rather than overflowing, and the field it dropped is
the one that identifies the station.

Fix: `.fixedSize(horizontal: false, vertical: true)` on the card's name and
region, so a squeezed column takes the height it actually needs. The pattern is
already used in `StationChooserSheet` for the same reason.

Measured, iPad sidebar at `accessibility-XXXL`, the hero's name `Text`:

| | frame | renders as |
|---|---|---|
| before | `w=50.0 h=199.0` | `Vi / ct / …` |
| after | `w=64.5 h=265.0` | `Vi / ct / ori / a` |

Four lines instead of three, and the name is whole.

### 3. The first-run gate's copy truncating at AX5 — FIXED

`accessibility-XXXL`, both devices: `See tides near you` rendered as
`See tides nea…` and the subtitle as `Turn on location and…`. The gate is a
single screenful of fixed copy laid out with `Spacer()`s; once the type scaled
(Task 1) the screenful stopped fitting, and SwiftUI resolves a too-short `VStack`
by truncating its `Text`s. Silent, and it hit the two lines that explain what the
button does. `accessibility-large` and below were clean.

Fix: the gate content is wrapped in `ScrollView` inside a `GeometryReader`, with
`.frame(minHeight: geo.size.height)` so the centred Spacer layout is unchanged at
every size that still fits and the copy scrolls only when it genuinely cannot.

Measured, iPhone 17, the two `Text` frames:

| | headline `h` | subtitle `h` |
|---|---|---|
| `accessibility-large`, before | 51.3 | 191.3 |
| `accessibility-large`, after | 51.3 | 191.3 |
| `accessibility-XXXL`, before | 69.3 (1 line, `…`) | 119.7 (2 lines, `…`) |
| `accessibility-XXXL`, after | **137.3** (2 lines) | **485.7** (8 lines) |

`accessibility-large` and `extra-small` are byte-identical before and after,
down to the tenth of a point — the wrap costs nothing at any size that already
fitted. At AX5 the `Use My Location` button now sits below the fold and is
reached by scrolling. That is the right trade: a reachable full sentence beats a
truncated one on the screen that explains what the button does.

The `Use My Location` button itself was already correct — Task 5's
`minHeight: 54` (not a pinned height) holds: the capsule grows 54 → 64 → 149.3pt
and the label wraps to two full lines inside it, `Use My Location` intact, at
every size on both devices.

### 4. The chart's own labels scaling inside fixed-point geometry — FIXED

**Found by the whole-branch review, not by this harness, and it is this
branch's defect — not pre-existing.** Nine label sites in `TimelineStrip.swift`
(six `ctx.draw(Text(…))` inside the `Canvas`, three `.position()`-pinned
overlay labels) were fixed custom fonts — `.fraunces(11/10)`, `.geistMono(10/9/8)`
— which do not respond to Dynamic Type at all. Task 1 mapped all nine to
`.caption2`, which does.

They are drawn into `TimelineGeo`, which is entirely literal points: `height`
362/258/286 by case, `dayY = 20`, `sunY = 34`, `tideTop = 48`, extreme labels at
`y ± 11` off their own dot, `slack` at `zeroY + 12`, track labels pinned at
`x: 30` and `x: 42`. At AX5 `.caption2` is ~26pt, so the day label centred at
`y = 20` overprints the sun dot at `y = 34` and reaches `tideTop`, and "Current"
centred at `x: 42` runs off the left edge. Scaling text in fixed-point geometry
does not degrade by wrapping; it overprints the chart.

Fix: all nine reverted to `.font(.system(size: N))` at their pre-branch sizes
(11 day, 10 sun, 10 tide extreme, 8 `slack`, 10 max flood/ebb, 9 × 3 track and
legend labels), with the reasoning recorded on `TimelineGeo`. This is not a
retreat from Dynamic Type — it is the rule this branch already applies three
times, to `MapHeader`'s 44pt buttons, `OfflineStatusButton`'s 34pt circle and
the FABs: chrome in a fixed-size slot does not scale. Making these labels scale
means making the chart geometry scale with them, which is layout design.

**Why Task 6's harness could not have caught this, and what that means for the
matrix above.** The harness measured frame dumps of `staticText` / `button` /
`image` / `textField` elements. **Text drawn with `GraphicsContext.draw` never
enters the accessibility tree** — a `Canvas` is one opaque element, and the six
labels inside it have no `staticText` of their own to dump. They cannot appear
in a frame dump at any size, so no cell of the 86-capture matrix could have
shown the collision however carefully it was read; the PNGs contain it, the
measurements structurally cannot. The three `.position()`-pinned labels *are*
real views and were dumpable, but the harness never opened a paired
tide+current detail view at AX5, which is where they collide.

The general form, worth carrying forward: **a frame-dump harness verifies the
accessibility tree, not the pixels.** Anything drawn — `Canvas`, `Shape` text,
`drawLayer` — is invisible to it and needs either a snapshot comparison or an
eye on the PNG.

## What held

- **FAB clearance, including at the small end.** The direction nobody checks,
  because Dynamic Type is reflexively tested by making text bigger. Scrolled to
  the bottom, gap from the last text to the FAB's top edge:

  | | `xs` | `s` | `L` | `XXL` | `AX-L` | `AX-XXXL` |
  |---|---|---|---|---|---|---|
  | iPhone 17 | **+36.0** | **+36.0** | +36.0 | +53.3 | +114.7 | +210.7 |
  | iPad sidebar | **+406.2** | **+415.0** | +356.5 | +240.0 | +114.5 | +210.5 |

  `extra-small`, `small` and `large` are identical on the phone to the tenth of
  a point. The `max(fabClearance, Self.fabClearanceBase)` clamp is doing exactly
  its job: `@ScaledMetric` shrinks below the default category, the clamp refuses
  to let the clearance follow it down.

  One measurement caution, recorded because it briefly read as a defect: the
  iPad AX5 cell first measured **−36.5**. That was the harness, not the app —
  the lowest thing under the FABs was an unlabelled full-width `other` container
  (a `List` section wrapper spanning `x=0 w=834`, caught by an `x < 320` sidebar
  filter), and a card whose *name alone* is 529pt tall at that size needs more
  than the 12 swipes the harness used to reach the bottom. Filtered to real text
  and re-run with 40 swipes, the gap is +210.5.
- **The FABs themselves** stay 56×56 at every category, as intended — they are
  chrome, not text companions.
- **The card glyph** tracks the text in both directions (20.7 at `extra-small`,
  56.7 at AX5) — proportionate beside the name at every size.
- **The search field capsule.** Task 5's `minHeight: 48` holds: the field's
  intrinsic height goes 18.7 → 65.0pt and the capsule grows with it. Nothing
  crosses the capsule's edge — no caret, no magnifier, no clear button.
- **The 46pt icon tile on the "no predictions yet" card** (`ChsDetailView`, one
  of the six sweep findings). Measured on the iPad detail pane across all six
  categories: 40.5 → 42.5 → 46.0 → 55.0 → 81.0 → 119.5pt. It tracks its
  `.title3` icon in both directions and the triangle stays inside it. The
  search bar's own leading magnifier scales with it (13.5 → 51.5pt) and stays
  inside the capsule; the FAB's magnifier does not scale, correctly — it is
  chrome, in a 56pt circle that also does not scale.
- **Exactly one `minimumScaleFactor`** survives, on the wordmark, and it is
  load-bearing: in the 320pt sidebar at AX5 the wordmark shrinks to its 0.6 floor
  and then truncates to `Slackwat…`. That is the accepted trade the guard exists
  to protect — a brand mark, not information — and it is the only truncation left
  anywhere in the captured matrix.

## Found and deliberately NOT fixed

- **Character-level word breaks in the trailing column at AX5.** In the 320pt
  sidebar and, less severely, on the phone, `Falling` breaks as `Falli / ng` and
  `Waning Gibbous` as `Wani / ng Gib- / bous`. Nothing is lost — these wrap, they
  do not truncate — but they read badly. Fixing it means a third, vertically
  stacking tier where the reading moves below the identity column instead of
  beside it. That is new layout design, and the spec explicitly closes the door
  on a further tier ("nothing above this ever asks for a layout narrower than
  name + region + trailing"). Out of Task 6's remit; worth its own decision.
- **`MultiDaySchedule`'s fixed slots at AX5.** `TimelineStrip.swift`'s schedule
  row pins a day label to `.frame(width: 74)` and its pill to
  `.frame(width: 84)` around text that now scales — the same
  fixed-container-around-scaling-content shape this branch fixed six times
  elsewhere.

  **This entry originally called it "pre-existing". That attribution was wrong
  and is corrected here.** The *frames* predate the branch, but nothing inside
  them scaled before it: the day label was a fixed custom font and the pill's
  text likewise, so a 74pt slot around them was never a mismatch. Task 1 mapped
  them to `.caption`/`.caption2`, and the mismatch is therefore this branch's,
  not inherited debt.

  Left as-is deliberately, which is a different claim from "not ours": these
  degrade by **wrapping** inside their slots, not by overprinting a chart, so
  nothing is lost or made unreadable. Widening the slots is a schedule-layout
  decision rather than a font fix. **This branch's follow-up, on the books.**
- **`ScreenshotTests/testM4PairedTide`** — time-dependent flake, issue #16.

## Not covered — say so rather than imply it was

`ProvisionalBadge` was never exercised. It renders only on a *provisional* CHS
fit, which needs live IWLS; every capture here ran offline or on bundled data,
and the `provisional-badge` identifier appears in none of the 86 frame dumps.
Its 22pt-disc container fix — one of the six sweep findings, and the one that
started the list — is therefore **unverified by this task**, asserted only by
source inspection. The nearest thing that *was* exercised is its sibling, the
46pt tile on `ChsDetailView`'s amber card, which scales correctly. Covering the
badge properly needs a run against live IWLS (the `--full` plan's territory) at
two or three sizes.

## Regression checks

Run on the throwaway devices, never the suite's:

- `SlackwaterTests` — 89 executed, 0 failures (both devices).
- `SlackwaterUITests/ScreenshotTests`, iPhone 17 — 29 executed, 3 skipped
  (iPad-only), 0 failures.
- `SlackwaterUITests/ScreenshotTests`, iPad Pro 11" — 29 executed, 1 skipped,
  0 failures. This is the run that matters for the card change:
  `testM44IPadSplit`, `testM50MatchingStationChooser` and
  `testM52IPadAutoSelectsTheFirstStation` all exercise the 320pt sidebar.

`testM50MatchingStationChooser` is the one to watch on any future change here: it
is the test that caught the first cut's region-shedding tier, and it exercises
the iPad sidebar at default text size — the exact cell where the sidebar's width
alone selects `.reduced`.
