# Fill graduation: the speed fill ships, green means transitable, streaks stay spiked

**Owner ruling (2026-08-21, #57 thread):** fill-first graduation; the particle/streak
channel stays a spike until field advection makes it earn its battery cost; the
green-as-transitable-now state ships in the same release as the fill, because it is the
story the fill release tells.

Consumes: `FillField` (#141, merged), the #97 ramp (`SN.speedRampStops` /
`Timeline.rampT`), the composite spec's §1 render channels, and the spike findings on
`spike/current-fill` (antialias-off, speed-riding opacity, land-clip-by-layer-order —
each recorded on #57 with the screenshot that forced it).

## 1. Packaging — already ruled, not re-decided here

The widgets-premium spec's canonical line (§2: "the entire offline core … free forever")
decides this: the fill evaluates a bundled 2.61 MB resource offline, so it is **free**.
The green transitable state is the same slack-window data the strip already shows free —
"what is the water doing" — so it is **free**. Boat-relative go-windows (vessel-specific
thresholds, "can *my boat* go") remain the Premium item they already are in that spec.
Nothing here moves the line in either direction.

## 2. What graduates, exactly

- `CurrentFill.swift` loses the `-currentParticles`-style launch-arg gate and becomes a
  **map layer with a user toggle**, default **on**. The launch arg stays as a UI-test
  override only (`-currentFillOff`), same pattern as `-networkKillSwitch`.
- Toggle home: the map screen's existing control surface (with the search/list FABs) —
  a small layers affordance, one switch: "Currents". No settings-screen round trip to
  turn a map layer off; no per-tier submenu until there is a second layer.
- Everything the spike proved carries unchanged: antialias off, opacity riding speed
  (floor 0.18 so certified coverage never reads as no-data), colour strictly
  `SN.speedRGB(Timeline.rampT(...))`, insertion under the land layers (free shoreline
  clip), 60 s off-main refresh, absence stays absence.
- The no-green-ramp invariant test graduates with it and stays the executable form of
  the composite spec's §1 ruling.

## 3. Green means transitable (the same release)

Green appears on the map only as a per-gate/station **state**: *transitable now* — the
instant is inside the station's slack window, the window the strip already draws free.

- **Pins (#13):** `currentPinTone` retires flood/ebb hue. New language: **pin colour =
  speed through the ramp** (one language with the fill beneath it); **green = inside
  the slack window**, replacing the current slack-instant green. Direction is not lost:
  it was already redundant on the pins (the detail card's arrow + cardinal carries it,
  per the #97 decision's own argument), and tide pins are untouched.
- **Window source:** the same slack-window computation the strip uses. The
  widgets-premium spec (§technical) already requires hoisting `slackWindow` out of
  `TimelineStrip` into a shared testable unit — this feature consumes that same hoist
  rather than duplicating it; whichever lands first does the extraction.
- **The fill never goes green** — unchanged, enforced by test. Only a station that can
  answer "is this instant inside a slack window" may say go; the fill can only say how
  fast the water is moving.

## 4. Explicitly out of scope

- **Streaks/particles** — stay behind `-currentParticles` on the spike branch until the
  point-in-triangle advection upgrade (`FillField` additive method, agreed with the
  Phase B session) makes motion worth its battery. No streak code ships.
- **Grown patches** (Dodd/Seymour/Sechelt throats) — separate phase, separate go.
- **Shore-margin pruning** — data-side (`pack.py` drops nearshore cells); noted on #57;
  rides the next bundle regeneration, not this release.
- **Scrubber** — reopened by the fill's existence per the original deferral logic, but a
  roadmap item, not a rider on this release.
- **Fill above vs below depth relief** — ships below (as spiked); revisit only if field
  feedback says the wash is too quiet.

## 5. Tests

- Flag-off/toggle-off emits a byte-identical style (the spike's invariant, re-keyed to
  the toggle).
- Layer inserts under land; per-feature colour; opacity floor > 0.
- No speed reaches green (ramp sweep — unchanged).
- Pin tone: inside-window → `SN.go`; outside → ramp colour at current speed; unknown →
  neutral. Prove the new assertions red first (repo TDD rule).
- Slack-window unit: shared extraction gets its own tests when hoisted.

## 6. Sequencing

1. **PR A — fill layer + toggle** (this spec's §2): graduates `CurrentFill.swift` from
   the spike branch onto main, toggle UI, tests.
2. **PR B — green state + pin language** (§3, closes #13): the slack-window hoist (or
   consumes it if widgets landed it first), pin tone rewrite, tests.
3. Release note copy leads with the green story: "see which passes you can transit right
   now"; the fill is the supporting picture.
