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
removed. Pins become SDF symbol icons: `icon-image` keyed on kind, `icon-color` on state, with a halo.

`StationItem.pinKind` (`CurrentStation.swift:198-204`) stays — it is the kind discriminator feeding
the icon expression, exactly as web's `kind` feature property does.

Three things the web port learned the hard way come with it, and each silently produces a broken map
if dropped:

- **The SDF edge encodes at 0.75, not 0.5.** MapLibre's shader thresholds icon fill at
  `inner_edge = (256-64)/256`. Encode the edge at the intuitive 0.5 midpoint and the glyph sits below
  the threshold and renders **invisible**, with geometry that is entirely correct.
- **Read the cache; never fetch.** State comes from what is already stored on device. Left to fetch,
  opening the map fires one request per unsynced CHS station through the IWLS client's 2.5s pacing —
  a request storm, and a map that stays neutral for minutes.
- **Reapply on style load.** Setting a style discards registered images and rebuilds sources, so pins
  must be re-registered and re-applied rather than painted once.

A station whose state is not knowable draws neutral. That is an honest "unknown", not a guess — on a
boat a wrong slack is worse than an admitted grey.

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
