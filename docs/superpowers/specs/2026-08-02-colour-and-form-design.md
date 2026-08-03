# Colour is state, form is kind — the iOS port

*Design spec, 2026-08-02. Ports the language established in
`slackwater-web/docs/superpowers/specs/2026-08-01-slackwater-design-language-design.md`
and extended in `2026-08-01-map-pin-glyphs-design.md`.*

## Why

An outside design review of **this app** found the list hard to scan, the type distracting and too
small, and the card backgrounds meaningless. Working through it on the web app first surfaced a root
defect that turned out to be present here too, independently arrived at:

| Where | Value | Meaning |
|---|---|---|
| `MapScreen.swift:33` | `PIN_CURRENT = "#8fd0a0"` | station **kind** = current |
| `MapScreen.swift:33` | `PIN_TIDE = "#7fb3d5"` | station **kind** = tide |
| `Theme.swift:25` | `rising = leaf` (`0x88B868`) | **direction** = rising / flood |
| `Theme.swift:26` | `falling = 0x7FB4D8` | **direction** = falling / ebb |

The map paints station kind in green and blue; every other surface paints water direction in the same
green and blue. A green dot means "current station" on one screen and "flooding" on the next. This is
the same two-axis collision the web app had, in the same two hue families, reached separately — which
is what makes it worth fixing as a rule rather than as a bug.

The web app now states that rule and enforces it with tests. This spec ports it.

## Decisions

1. **Colour encodes state. Form encodes kind.** Nothing derives colour from station kind.
2. **Direction is a signed diverging axis** — flood/rising blue, ebb/falling amber — and green
   narrows to mean slack alone.
3. **The list card takes layout A** — identity left, state right — with a kind glyph and a flat
   background.
4. **Map pins reach parity with web**: shape is kind, colour is state.

## Scope

**In:** the four decisions above.

**Deliberately out, each its own piece:**

- **Typography.** SF plus Dynamic Type, retiring the three bundled families across 117 call sites in
  10 files. Decided, specced separately, and by far the largest part of the port — folding it in here
  would produce a diff nobody can review.
- **Behaviour.** The launch rule and the `MapHeader` height. Not visual language.
- **The starred ring and the tap-preview card.** Genuinely new interaction rather than a port: a form
  cue for starred stations, a first-tap card carrying the glyph with a minimal location and state
  word, and a second tap opening the detail view. iOS first, then web follows. Held back so this spec
  stays a port.

## 1. Tokens — `Theme.swift`

```swift
// Direction is one signed diverging axis; green means only slack.
static let flood   = Color(hex: 0x4A9FD8)
static let ebb     = Color(hex: 0xE8A33D)
static let go      = Color(hex: 0x88B868)
static let rising  = flood   // tide stations speak rising/falling,
static let falling = ebb     // current stations flood/ebb/slack
```

`rising` and `falling` currently point at leaf green and `0x7FB4D8` (`Theme.swift:25-26`); both
retarget. `PIN_TIDE` / `PIN_CURRENT` (`MapScreen.swift:33`) are deleted outright, not retinted.

Amber/blue replaces green/blue for direction because it is the standard colourblind-safe diverging
pair, it holds up on the navy ground, and it frees green. Green mattering is the point: for an app
called Slackwater the moment you are waiting for is slack, and green now names it.

### `SN.amber` must move

`SN.amber` (`0xE0B45A`, `Theme.swift:33`) is the warning/provisional tone. It sits close enough to the
new ebb `0xE8A33D` to be confusable at a glance — and this is not hypothetical: on web the warning
colour and the ebb colour were briefly the *same hex*, and collided in the event list where a sunset
pill and a max-ebb pill became indistinguishable. They had to be split apart.

`SN.amber` becomes `0xEF6F4A` — the value the web app settled on for the same job, measured there at
5.89:1 on the navy ground and clearly separated from ebb in hue. Reusing it keeps one warning colour
across both apps rather than inventing a second. Every consumer is checked: `ProvisionalBadge`, and
`OfflineDownloads.swift:107,109,242,243`.

## 2. Direction call sites

All of these currently read `SN.rising` / `SN.falling` and need no edit once the tokens retarget —
but each must be *verified* rather than assumed, because a retarget that silently misses one leaves a
surface speaking the retired language:

- `DerivedGateDetailView.swift:73-77` and `CurrentDetailView.swift:95-99` — `phaseColor`
- `TideDetailView.swift:96` — the rising/falling foreground
- `TimelineStrip.swift:744,750,759` — high/low and flood/ebb pills

**Slack must become `SN.go` wherever it is currently neutral.** On web, `--go` had exactly one
consumer while chart dots, event pills and phase pills all still drew slack in a neutral ink — so a
gate at slack showed a green glyph beside a grey "slack" pill *in the same card*. Do not reproduce
that: audit every slack rendering.

**The list cards do not colour by direction today.** `StationCardView` (`SlackwaterApp.swift:1069`)
and `CurrentCardView` (`:1323`) render the arrow and phase word in plain `SN.foam`. Adding the
diverging colour there is additive, not a correction.

## 3. The list card — layout A

Five variants share one shell (`StationCardView`, `ChsCardView`, `ChsGateCardView`,
`ChsCurrentGateCardView`, `CurrentCardView`), so layout A is applied to the shell once:

```
┌─────────────────────────────────────────┐
│ ~  Boundary Pass              2.4 kn    │
│    Salish Sea                 ↘ Flood   │
│    3.2 NM                Slack 2:14 PM  │
└─────────────────────────────────────────┘
  ^ glyph      ^ identity          ^ state
```

The skeleton already matches — identity left, state right. Two things change:

- **Distance joins the identity column.** Today it is `DistancePill` (`Theme.swift:263-274`), a
  floating overlay pinned to the card's corner with `.offset(x: -14, y: -8)`. Distance is station
  identity, not a reading; it belongs with the location it qualifies.
- **Backgrounds go flat.** `stationGradient(id:)` (`Theme.swift:87-99`) tints **per station**, so the
  reviewer's "I'm not sure I understand the meaning of the colours for the list item backgrounds" was
  about a tint that genuinely varies and genuinely encodes nothing. `stationGradient` and
  `gradientTrios` are deleted, not merely unused.

## 4. The kind glyph — new

iOS has no kind indicator on cards today, in any form — not by colour, not by shape. Kind is implied
only by which card variant renders. A small SwiftUI `Shape`:

| Glyph | Kind |
|---|---|
| wave | current station |
| dome over a datum line | tide station |

Tinted by state through `.foregroundStyle`, never by kind. Same language as web's `StationGlyph`,
drawn natively rather than shared — the two surfaces mean the same thing, which is what consistency
requires here.

## 5. Map pins — parity

`MapScreen.swift:96,107-108` currently match `circle-color` against `["get", "kind"]`. That match is
removed. ~~Pins become SDF symbol icons: `icon-image` keyed on kind, `icon-color` on state, with a
halo.~~ *Corrected 2026-08-02, as shipped:* **only the tide layer** is an SDF symbol icon. Current
pins stay a `circle` layer with `circle-color` — a disc needs no image, and both layers carry the
identical state expression, which is what the rule actually requires.

**The map's marks are a circle and a square, not the card's glyphs.** *Amended 2026-08-02, after the
web version was used.* The wave and dome were tried on the map there and rejected: thin curved
strokes over bathymetry contours make a dense chart denser, and the map stops being calm enough to
scan. Use the oldest cartographic convention instead — one shape per feature class:

| Kind | Map mark |
|---|---|
| current station | **filled circle** |
| tide station | **filled square** |

Square versus circle is a *silhouette* difference, visible at any size and in peripheral vision,
where the interior difference of a ring versus a disc is not. Solid shapes also carry the state
colour far better than strokes, which matters because colour is the map's primary signal. Draw the
square to equal **area** rather than equal width — a same-width square always reads heavier.

So the two surfaces deliberately differ: the card keeps the expressive wave and dome of §4, because a
list row is roomy and calm; the map takes the plain marker, because a chart at zoom 12 is neither.

**The popup carries the words.** Since the map's only signal is colour, the preview popup names the
station kind and spells the state out — "Flooding", "Ebbing", "Slack", or an honest wording where
state is not known. That is what makes the palette self-teaching and lets the map do without a
legend. On web the first tap previews and the second opens; iOS should match.

> **What is in force, and what is not.** *Added 2026-08-02, closing a contradiction in this
> section.* The paragraph above is the **target state**, not this piece: the first-tap preview card
> is explicitly deferred in § Scope, and this spec cannot both defer the popup and lean on it as the
> reason the map needs no legend.
>
> **So iOS ships the map colour-only** — no legend, no popup, no state word anywhere, and no
> accessibility label on a pin. Only the list card announces kind (`StationGlyph.swift:60`); the map
> announces nothing. **That is an accepted interim, not an oversight**, and it is the argument for
> the preview card being the next piece rather than a nice-to-have: until it lands, the map's colour
> is unlabelled and unreadable to VoiceOver. Everything above this box is in force; the popup
> paragraph is not.

`StationItem.pinKind` (`CurrentStation.swift:198-204`) stays — it is the kind discriminator feeding
the icon expression, exactly as web's `kind` feature property does.

Three things the web port learned the hard way come with it, and each silently produces a broken map
if dropped:

- **The SDF edge encodes at 0.75, not 0.5.** MapLibre's shader thresholds icon fill at
  `inner_edge = (256-64)/256`. Encode the edge at the intuitive 0.5 midpoint and the glyph sits below
  the threshold and renders **invisible**, with geometry that is entirely correct. *Corrected
  2026-08-02: this is a **web-only** hazard.* It bites when you hand-encode a distance field. iOS
  never does — the square is a `UIImage` registered with `withRenderingMode(.alwaysTemplate)` and
  MapLibre Native derives the field itself. Carried here for the web port's record only.
- **Read the cache; never fetch.** State comes from what is already stored on device. Left to fetch,
  opening the map fires one request per unsynced CHS station through the IWLS client's 2.5s pacing —
  a request storm, and a map that stays neutral for minutes.
- **Reapply on style load.** Setting a style discards registered images and rebuilds sources, so pins
  must be re-registered and re-applied rather than painted once.

A station whose state is not knowable draws neutral. That is an honest "unknown", not a guess — on a
boat a wrong slack is worse than an admitted grey.

**Scope limit on state, deliberate.** Only stations that resolve *synchronously on device* get a
colour in this piece: bundled NOAA tide and current stations — **not** derived gates, correcting
this spec's own earlier claim. A derived gate has no `cardState(at:)`; resolving one needs
`ChsFitService.shared.state(gate.reference)` to be `.fitted`, and the single bundled gate's
reference is itself a CHS port. So gates are async like the CHS stations they depend on, and draw
neutral with them. The synchronous set is what resolves through the
`cardState(at:)` helpers that already exist. **CHS stations draw neutral**, because their readings sit
behind an async cache and wiring that in is a subsystem rather than a step — it would roughly double
this piece for the half of the map that is already the hardest. The rule is unaffected: neutral means
unknown, which for an unsynced CHS station is exactly true. The async CHS cache read is a follow-on,
and it is the one that makes the Canadian side of the map light up.

## 6. Testing

This repo has **no** test asserting anything about colour or kind — nothing analogous to web's
`tokens.test.ts`, `StationGlyph.test.tsx` or `mapStyle.test.ts`. The port adds the one that carries
the rule:

> A current station at slack and a tide station at slack render the **same colour** and **different
> glyphs**. The same current station at flood renders the **same glyph** and a **different colour**.

That is the two-axis separation stated as an executable check, and it fails loudly if anyone
reintroduces colour-means-kind. It belongs in `SlackwaterTests`, run by `./scripts/test.sh` (fast
plan, ~9 min per simulator).

A second, cheaper guard: assert no source file references the retired `PIN_TIDE` / `PIN_CURRENT`
values or the old `0x7FB4D8` falling hue.

## 7. Order of work

1. Tokens (§1), including the `SN.amber` split — lands first so nothing is built against the old
   language.
2. Direction and slack call sites (§2), with the audit.
3. The kind glyph (§4) and the card (§3).
4. Map pins (§5).

Each step leaves the app building and the fast test plan green.

## 8. Process

`CONTRIBUTING.md` governs: no direct pushes to `main`, work lands through a pull request, rebase or
squash rather than merge commits, and **an agent never merges its own PR** — it opens one, pushes to
its branch, and responds to review. The merge is a human decision.
