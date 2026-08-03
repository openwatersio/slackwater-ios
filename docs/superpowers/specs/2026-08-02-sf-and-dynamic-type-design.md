# SF and Dynamic Type — the type system

*Design spec, 2026-08-02. The second piece of the design-language port; the first was
`2026-08-02-colour-and-form-design.md` (colour is state, form is kind).*

## Why

An outside design review of this app said the type was distracting, inconsistently applied, and
**"way too small for my old man eyes in bright light."**

The web app answered that with a system font stack and a 14px floor. That was the right answer
*there*, because a webfont is a network dependency in an app whose whole promise is not needing one.
It is the wrong answer here, and it took a spike to see why.

**iOS has a better answer than a floor: Dynamic Type.** A fixed minimum helps a reader whose eyes
need 15pt and fails one who needs 22pt. Dynamic Type respects the size the reader already told their
phone, which is both the accessible thing and the thing every other iOS app does. It is also the one
capability the web version structurally cannot have.

So this piece is not "swap the fonts". It is: adopt the system font, adopt Dynamic Type, and make the
layout survive a reader at 300%.

## What the spike found

A spike (`type/dynamic-type-spike`, commit `304d4bc`) converted **one** card — `StationCardView` — and
rendered it across the size range on both devices. Its findings reshaped this spec:

**The fonts were not the risk.** The `.fraunces(42)` hero numeral — the thing most feared, tuned to a
serif's metrics — never broke at any size.

**The two-column layout was.** At accessibility sizes there is no horizontal room for identity-left
and state-right. "Falling" hyphenates to "Fall-/ing", names truncate from `AccessibilityL`, cards grow
past their container, and on iPad a single card fills the whole sidebar viewport.

**A 14pt floor is meaningless here.** No such constant exists in the code — it described the
default-rendered sizes of the old fixed points. Under Dynamic Type a hardcoded minimum would fight the
reader's own setting rather than help them.

**`minimumScaleFactor(0.7)` is now harmful.** With `lineLimit(1)` it shrinks the name, gives up, and
truncates — producing "Selkir…". Shrinking text is precisely what a reader who set 300% asked you not
to do.

**Rough split:** ~60% mechanical, ~40% layout judgement on that one card, and worse elsewhere.
`SlackwaterApp.swift` is the file to fear: five card variants plus list and search chrome, and the
FAB-overlap problem is list-level, so it recurs across every variant rather than being fixed once.

## Decisions

1. **SF via Dynamic Type semantic styles.** The three bundled families retire.
2. **The card adapts by measured fit**, not by a type-size threshold — because it must also handle
   narrow width.
3. **Three tiers**, shedding facts as room disappears.
4. **No size floor.** Dynamic Type is the mechanism; a floor would contradict it.

## 1. Type

Replace `.fraunces(_:_:)`, `.geist(_:_:)` and `.geistMono(_:_:)` with semantic Dynamic Type styles —
`.largeTitle`, `.title2`, `.subheadline`, `.caption` and so on — chosen to approximate the existing
hierarchy rather than to preserve exact point sizes.

`.monospacedDigit()` goes on every numeric reading. A column of heights that shifts as digits change
is harder to read than one that does not, and there are currently **zero** uses of it in the app.

Retire `Fraunces`, `Geist` and `GeistMono`: the `Font` extension in `Theme.swift`, the `UIAppFonts`
entries in `project.yml`, and the bundled `.ttf` files.

**Do not add a minimum size.** See above.

## 2. The card adapts by fit

```swift
ViewThatFits {
    fullCard        // 6 facts, two columns
    reducedCard     // 5 facts, one column
    essentialCard   // 4 facts, one column
}
```

`ViewThatFits` measures available space, so it responds to **width as well as type size**. That
matters beyond accessibility: the iPad's ~320pt sidebar truncates station names *at default text
size* today. A `dynamicTypeSize` threshold would never catch that; measured fit catches both with one
mechanism, and degrades at every intermediate size rather than snapping at one boundary.

All five card variants share one shell, so this is applied once.

## 3. The three tiers

| Tier | Shows |
|---|---|
| **Full** | glyph · name · region · distance · value · direction · next extreme |
| **Reduced** | glyph · name · region · value · direction |
| **Essential** | glyph · name · value · direction |

**Shed order: distance first, next extreme second, region last.**

- **Distance** goes first because the list's own grouping already answers "which of these is near me"
  — Near Me is a section header.
- **Next extreme** goes second because "when" is the detail view's entire job, one tap away.
- **Region survives longest** because it is the only thing separating "Victoria" from "Victoria
  Harbour" from "Victoria Inner Harbour". A truncated ambiguous name is worse than a missing one.

Nothing is lost, only deferred: every shed fact is on the detail view.

## 4. Three details that follow

**The glyph scales.** `@ScaledMetric` on `StationGlyph`'s size, so it grows with the text instead of
sitting as a 24pt mark beside 40pt type.

**`minimumScaleFactor` comes off** the name treatments (`SlackwaterApp.swift:1088, 1198, 1276`,
`MapHeader.swift:67`, and the others). Names wrap instead.

**The FAB clearance scales.** The list's `Color.clear.frame(height: 96)` bottom spacer must grow with
type, or the last card sits under the buttons however well the card itself reflows. This is
list-level, not card-level, and it is why `SlackwaterApp.swift` is the hard file.

## 5. Testing

`ViewThatFits` is genuinely awkward to assert against — there is no supported way to ask which
candidate it chose. So the coverage splits:

- **Unit tests over the tiers.** Each tier is a separately-callable builder. Assert what each
  contains: the essential tier has the name and the reading and does **not** have the distance. That
  is testable without rendering.
- **Screenshots over the selection.** Which candidate renders at a given size and width is verified
  by screenshot at a few sizes on both devices, not by unit test.

Write that split into the code as a comment. Otherwise someone will try to unit-test the picker,
fail, and quietly weaken the test — which is how this project's colour guard ended up wrong four
times.

**A trap the spike hit, recorded so nobody repeats it:** an invalid content-size-category launch
argument (e.g. `UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge`, which is not a real
category) makes UIKit **silently fall back to the default** with no error. Two screenshots at
supposedly different sizes come out byte-identical. Verify category strings against
`UIContentSizeCategory`, and compare file sizes if two size steps look suspiciously alike.

## 6. Scope

**In:** the type swap across all call sites, the adaptive card, the three details in §4, and the
testing split.

**Out:** the launch rule and `MapHeader` height (the third piece); the starred ring and tap-preview
card; anything in the colour and form spec.

**Sequencing:** this lands after `colour-and-form`, which introduces `StationGlyph` and layout A —
both of which this piece then makes adaptive.
