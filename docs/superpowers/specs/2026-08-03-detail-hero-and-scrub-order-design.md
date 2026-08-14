# The hero shrinks, the readout leads, the calendar goes last

*Design spec, 2026-08-03. Changes the detail-view anatomy shared by
`TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView` and (header only)
`ChsDetailView`.*

## Why

The detail view spends 420 of ~874pt — nearly half the screen — on a map that is
looked at once, on arrival, to confirm you opened the right station. Everything
you actually came for (how much water there is, which way it is going, when it
turns) starts below the fold and the scrubber is half off-screen.

Two smaller things follow from the same cause. The scrub card opens with the
date, the time, and the moon phase — a calendar row — before it says the height.
And the hero chrome (back, title pill, star) sits on `.ultraThinMaterial` with a
second opaque `0x05122A` fill stacked behind it, which cancels most of what the
material is for: the buttons read as flat navy discs on a map instead of glass
over it.

The chrome fix pulls a fourth decision in with it: the deployment target rises
from 17 to 26. The 17 floor was XcodeGen scaffolding from the first commit
(`e41cf76`), never a decision — the app builds against the iOS 26 SDK, has zero
`#available` checks, and is not on the App Store yet, so the floor is free to
set now and expensive to raise later. Raising it means the chrome uses Liquid
Glass proper instead of a material imitation of it. (Retired lower-floor iPads
matter for a chartplotter surface someday; a tides app should be further
ahead — Bryan, 2026-08-05.)

## Decisions

1. **The hero crops to roughly a third** — enough for the status bar, the title
   pill, and a band of chart underneath it. The map becomes the texture behind
   the station's name, not a locator.
2. **The chrome becomes Liquid Glass** — deployment target rises to 26, the
   opaque backing goes, and the map shows through.
3. **The scrub card leads with state.** Height/speed and direction sit directly
   under the hero; the strip is flush against them with no gap.
4. **Date, time and moon go last** — the bottom of the scrub card, below the
   strip. They are the *when* of the reading, secondary to the *what*.
5. **One `ScrubWhen` view**, used by all three scrub cards, instead of three
   identical copies.

Mock (pixel composite of a real screenshot, so type sizes are honest):
`2026-08-03-detail-relayout-mock.png`.

## 1. `MapHeader` — height and material

**Height.** `mapHeaderHeight: CGFloat = 420` (`MapHeader.swift:11`) does not
become `140`. It stops being a fixed number at all: the header's height is the
top safe-area clearance plus the title pill plus a bottom margin, and the pill
scales with Dynamic Type. A hard 140 clips the region line at AX3 the same way
the pinned heights fixed last week did (`docs/superpowers/notes/2026-08-02-dynamic-type-verification.md`).

```swift
/// Bottom band of map kept below the title pill — the border the name sits on,
/// not a viewport. The header's height is pill + clearance, so it scales.
let mapHeaderBottomMargin: CGFloat = 24
```

The `.frame(height: mapHeaderHeight)` at `MapHeader.swift:106` becomes the
`VStack`'s intrinsic height plus that margin; the `MLNMapView` fills behind it
in the `ZStack` as it already does. At the default text size this lands near
140pt — a third of the old hero — and grows only when the type does.

**Scrim.** The four-stop gradient (`MapHeader.swift:40-45`) was tuned for a
420pt hero: dark at top for the title, light in the middle where the pin was,
dark again into the card. Over ~140pt the middle stops never get room to breathe
and the whole thing reads as a flat wash. Collapse to two stops — 0.80 at the
top, 0.35 at the bottom — and keep it doing the one job it still has, which is
making the title pill legible over bright chart fill.

**Material.** Every piece of hero chrome currently stacks two backgrounds:

```swift
.background(.ultraThinMaterial, in: Circle())
.background(Color(hex: 0x05122A, opacity: 0.55), in: Circle())
```

Both layers go, on all four (back `:63`, title pill `:79`, star `:96`,
return-to-now `:118`), replaced with the system material at its default
opacity:

```swift
.glassEffect(.regular.interactive(), in: Circle())        // the three buttons
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))  // title pill
```

The buttons and pill sit in one `GlassEffectContainer` so adjacent glass blends
rather than double-refracting where the pill nears a button on narrow widths.
The pill's hand-rolled `strokeBorder(Color.white.opacity(0.10))` (`:81-82`) and
return-to-now's (`:119`) are deleted too — edge treatment is glass's job now.
Glass adapts its own legibility to what is under it, which is exactly the job
the deleted navy fill was doing badly.

The same two-layer stack appears twice outside the hero
(`SlackwaterApp.swift:764`, `:877` — search FAB and close-search). They convert
in the same commit: half-converted chrome is worse than either state.

`ChsDetailView`, `CurrentDetailView` and the schedule cards keep their flat
`SN.cardFill` surfaces — glass is for chrome floating over content, not for
content cards. Nothing else converts.

Editable inputs are content, not chrome: the search *field*'s flat capsule
stays flat, deliberately, even beside the glass close button (decided in #52).
An input is a thing you touch and type into, like a card — glass stays for the
actionable chrome floating around it.

**The station pin goes** (`MapHeader.swift:31-37`). It is centered, and at this
crop the center is behind the title pill. At a third of the height the map is no
longer answering "where is this" — the name is.

**Return-to-now moves** out of the hero's `bottomTrailing` overlay
(`MapHeader.swift:110-126`) and into the scrub card's readout row, trailing edge,
beside NEXT LOW. In the cropped hero it would overlap the star. In the readout
row it sits next to the thing that changes when you scrub, which is where you
look when you want to undo a scrub.

This means `showReturn`/`onReturn` leave `MapHeader`'s signature and move to the
readout. `ChsDetailView` passes them today (`:114`) and has no scrub card — it
loses the parameters and gains nothing, which is correct: there is nothing to
return from while a station is still downloading.

Keep the fixed 44pt hit targets and the comment at `MapHeader.swift:50-55`
explaining why they do not scale. That reasoning is untouched by this change.

## 2. Anatomy — the order in each scrub card

Today the three cards disagree about where the primary reading lives. Tide puts
it above the strip; current and derived gate put it below (with a secondary
"tide at port" block above). All three open with the calendar row. After this:

| | Tide | Current / derived gate |
|---|---|---|
| hero | map ⅓ | map ⅓ |
| | **height + direction · next high/low · ↺** | tide at port · next high/low |
| | strip *(flush)* | strip *(flush)* |
| | swipe hint | **speed + phase · ↺** |
| | **when: date · time · moon** | swipe hint |
| | | **when: date · time · moon** |

The rule that makes those two columns the same rule: **the `when` row is always
the last thing in the scrub card.** Where the primary reading sits relative to
the strip is a per-type decision that already exists and this spec does not
relitigate — current's speed reads below the strip because the phase colour has
to sit next to the curve it describes.

**Flush.** `VStack(spacing: 14)` in each detail body and the card's
`.padding(.top, 16)` currently put 30pt of page between the map and the card.
Both go to 0 for the hero→card seam; the card keeps its own horizontal padding
and its spacing to the schedule card below. The strip already has
`.padding(.top, 12)` from the readout — keep that, the "no gap" is specifically
the hero seam.

## 3. `ScrubWhen` — one view, three callers

`TideDetailView.swift:65-85`, `CurrentDetailView.swift:106-125` and
`DerivedGateDetailView.swift:82-101` are the same twenty lines three times. They
are all moving to the bottom of their card, so this is the cheapest moment it
will ever be to collapse them.

```swift
/// The *when* of a scrub reading: relative day, clock time, moon for that day.
/// Bottom of every scrub card — secondary to what the water is doing.
struct ScrubWhen: View {
    let scrubTime: Date
    let dayOffset: Int
    let tz: TimeZone
}
```

Lives in `Theme.swift` beside `MoonGlyph` and `MonoLabel`. Same content as
today, one layout change: at the bottom of the card it is a single row —
`TODAY · MON, AUG 3 · 8:08 PM` on the leading edge, moon glyph and phase name
trailing — rather than the stacked block it is at the top. The time stays
`.title` weight-medium monospaced-digit with `.contentTransition(.numericText())`;
it is still the thing that ticks while you scrub.

`dayOffset` is computed identically in all three views (`TideDetailView.swift:26-31`
and twins). It moves into `ScrubWhen` as a private computed property off
`scrubTime`/`live`, and the three copies go with it.

## Scope

**In:** the five decisions, across `MapHeader` (four callers), the three scrub
cards, the two FAB conversions in `SlackwaterApp.swift`, and the
`project.yml` deployment-target bump.

**Out:**

- **The `tide at port` block** in the current and gate cards. It is secondary
  information sitting above the strip, which by the logic of this spec wants
  moving too — but it is a different judgement (it is *context for* the primary
  reading, not the calendar) and folding it in doubles the diff. Its own piece.
- **The schedule card and footer.** Unchanged.
- **A map that does anything.** The hero stays non-interactive. Making the
  cropped map tappable-to-expand is an obvious follow-on and is not this.

## Verification

The change is layout, so the check is visual and the repo already has the
harness for it:

1. `scripts/test.sh` — `TypeScaleTests` must stay green; the header's new
   intrinsic height is the thing most likely to break it.
2. `ScreenshotTests` at default and AX3, iPhone and iPad split. The AX3 pass is
   the real assertion: the title pill must not clip and the hero must grow, not
   crop. Run on an iOS 26 simulator — after the target bump there is no other
   kind.
3. Glass legibility over the brightest chart fill (sand-coloured land at the top
   of a station like Sesuit Harbor) — the deleted navy layer existed for this;
   confirm the scrim alone still carries it.
4. On device: scrub away and confirm return-to-now appears in the readout row
   without reflowing the row (the same overlay-not-layout trick it uses in the
   hero today — `MapHeader.swift:107-109` explains why, and the reason survives
   the move).

One new unit assertion, since a constant is doing load-bearing work:
`mapHeaderBottomMargin` is small enough that pill + margin lands under 200pt at
default type — the "it is a third, not a half" claim, executable.
