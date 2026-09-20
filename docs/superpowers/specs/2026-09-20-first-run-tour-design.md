# The first-run tour: teaching the detail view on the real thing

Status: approved design, 2026-09-20. Extends the first-run gate (#360, PR #381).
Supersedes nothing. Reopens one decision from #58 and says so.

## The problem

The station detail view is the app. It is also unteachable on sight.

Three of the things it does best are invisible until someone tells you:

- **The backdrop is the real sky.** `brightStars` is the Yale Bright Star
  Catalog cut at magnitude 3.5, and every star is placed through `starAltAz`
  for that station's observer, on every scrub frame (`Theme.swift:150-215`).
  The moon carries its true phase and altitude. Nobody guesses this. It reads
  as decoration.
- **The strip scrubs, horizontally, and nothing says so.** #58 already tried a
  "‹ swipe to scrub ›" label and removed it: testers who read the label still
  did not find the horizontal scroll, and the comment at `Theme.swift:1026`
  records that none is coming back.
- **The moon tile opens.** It is the only `ReadoutTile` with a chevron and a
  sheet (`Theme.swift:742`, `Theme.swift:775-778`). Range and Next max are
  inert. One tappable readout among three that look identical is a coin flip.

The app has no onboarding of any kind. The gate (`GateView.swift`) is a
permission ask with one example card, and after it the user is on their own.

A first run in Canada also has a wait — a Victoria fix queues 99 jobs, about
49 minutes, with the first station ready in roughly 25 seconds. The tour lands
well in that gap, and that is a coincidence worth having. It is not the reason
the tour exists, and **nothing in the tour is conditioned on download state or
sized to the wait.** A user in Seattle has no wait at all and needs the
teaching just as much.

## Shape

Four beats of explanation and one gesture, delivered as coach marks over the
**real** detail view rather than as screens about it. No mockups, no second
copy of the UI to keep in sync, and the gesture is taught by performing it.

### The five steps

| | Anchor | What it says |
|---|---|---|
| 1 `.read` | `detail-reading` (`Theme.swift:626`) | The reading is whatever sits on the centre line |
| 2 `.stars` | `timeline-strip` (`TimelineStrip.swift:1635`) | 👆 "Swipe the curve to move through time" — then it glides past tonight's sunset and the copy swaps to name the stars that appeared |
| 3 `.moon` | `timeline-strip` | Glides on to when the moon is up: that is the real moon, at tonight's phase |
| 4 `.moonCard` | `tile-moon` (new id on `Theme.swift:742`) | Tap the moon for rise, set and phase |
| 5 `.star` | `detail-favorite` (`DetailHeader.swift:95`) | Star a station to keep it at the top of your list |

Steps 2 and 3 share all of their machinery. The marginal cost of the second is
one different target time.

### Why the scrub demo is a journey and not a jiggle

#58's finding was that a *label* fails to teach a gesture, and it is right.
This does not bring the label back; it moves the strip. The demo glides from
now to after tonight's sunset, and the sky turns over as it travels — which
teaches the gesture and the payoff in the same motion. Then it glides again to
the moon.

Both targets are inside `Timeline.snapJumpHours` (`7 * 24` hours,
`TimelineStrip.swift:121`), so `jump(to:)` rides the animated magnet the whole
way rather than snapping.

### Finding the two moments costs nothing

`SkyState` refuses to search for rise and set times on principle — a position
lookup is about 0.005 ms and an Almanac event search about 0.6 ms, and this
initialiser runs every scrub frame (`Theme.swift:196-200`). The tour inherits
that discipline, because it does not need to search either: `TimelineDay`
already carries `sunrise`, `sunset`, `moonrise` and `moonset`, computed once by
the timeline build.

So both targets are pure functions over `[TimelineDay]`:

- **stars** — the next `sunset` in the window, plus an hour for real darkness.
- **moon** — the first intersection of a `[moonrise, moonset]` span with a
  `[sunset, sunrise]` span; its midpoint.

Neither touches Almanac, and both are unit-testable with no view.

**Above the Arctic Circle in summer there is no sunset in the window.** No
stars moment resolves, no dark-moon moment resolves, and steps 2 and 3 are
skipped — the tour runs `.read`, `.moonCard`, `.star`. Nothing is invented and
nothing is shown that is not true.

## The overlay

One `@Observable` `TourCoach`, beside `LinkedInstant` in the same handoff file:

```
enum Step { case read, stars, moon, moonCard, star }
var step: Step?        // nil = not running
var station: String?   // the id the tour belongs to
```

Persistence is one `@AppStorage(seenTourKey)` flag mirroring `seenGate`
exactly, with `-resetTour` and `-seedTour` hooks in `TestSeeds.swift` beside
`-resetGate` and `-seedGate`.

### Anchoring

A `TourAnchorKey: PreferenceKey` mapping `Step` to `Anchor<CGRect>`, set at the
five sites in the table above, and read by a single
`.overlayPreferenceValue` on the scaffold's outer `GeometryReader`
(`Theme.swift:884`). The layer is fixed to the screen while content scrolls
under it, and the nav bar is already hidden there (`Theme.swift:944`), so
nothing obstructs it.

The overlay goes in `ScrubDetailScaffold`, not in `TideDetailView`. CLAUDE.md's
rule that a scrubber presentation change has four consumers is then satisfied
by construction rather than by review, and the anchors have to live in the
scaffold either way because `DetailHeader` and `SummaryTiles` are its children.

### The capsule

The existing house idiom: `.buttonStyle(.glass)` with
`.buttonBorderShape(.capsule)`, the `nowPill` pattern at
`TimelineStrip.swift:1683`, plus an `SN.leaf` ring around the anchor rect. No
custom bubble shape and no new component — there is no callout, tooltip,
TipKit or `.popover` anywhere in the app target today, and this does not add
the first one as a general abstraction.

The swipe glyph is `hand.draw.fill` — a hand with motion arcs, the platform's
own swipe idiom — with `.symbolEffect(.wiggle.left)` for the motion. No asset
ships, and symbol effects honour Reduce Motion without being asked.

Each capsule carries its sentence, a Next (Done on the last step), and a Skip
that is present from the first step.

### Hit testing is what makes step 2 honest

The overlay layer is `allowsHitTesting(false)` everywhere except the capsule
itself, so a real drag passes straight through to the `UIScrollView` underneath.
Step 2 therefore clears on **either** a capsule tap **or** the user's own first
drag.

That is the whole reason no `onUserScrub` callback is added to
`TimelineScrubber`: the coordinator's `scrollViewWillBeginDragging`
(`TimelineStrip.swift:1461`) is the only user-versus-programmatic distinction
in the file and it is not published anywhere, but `.onChange(of: scrubTime)`
after the demo has settled says the same thing from outside, with no UIKit
change.

### Scrolling to each target

The star lives in the header and the moon tile below the strip, both inside the
scaffold's `ScrollView`. Wrapping it in a `ScrollViewReader` and tagging the
five anchored views with `.id(step)` lets the tour bring each target into view
before its capsule appears. This is the only genuinely new machinery in the
feature.

## When it runs

The tour **arms** on first launch and **fires on the first detail view that
has a real timeline on screen**. A CHS waiting page or an unavailable station
has no curve, no sky, no moon tile and no scrubber — nothing to teach — so the
tour stays armed and fires on the next real one.

Arming rather than scripting is what covers the entry paths that skip the
location flow entirely: the gate's "Search for a place" bypass
(`GateView.swift:86`), a widget deep link, and a shared station link all land a
first-time user on a detail with no teaching at all, and those users never
watched the list fill in either.

**On the location path the list also opens one.** After the gate resolves —
with a fix *or* a denial — the list's first `.onAppear` picks a station and
calls the existing `open(_:)` (`StationListView.swift:622`), through the same
one-shot slot `gateSearchHandoff` and `pendingDeepLink` already occupy. No new
navigation machinery.

`tourStation(near:)` takes the nearest bundled tide station to the fix and
falls back to `noaa/9449880` Friday Harbor — the same station the gate just
showed. It reads the ranking the list has already computed, so it adds nothing
to launch (#317). Bundled NOAA and TICON stations need no download, which is
why **the tour depends on neither location nor the network**: a denied fix
still gets Friday Harbor, and an offline first run still gets a full tour.

### Ending it

Leaving the detail ends the tour, and so does a second deep link arriving.
Backgrounding does not — the overlay is state and it survives, so someone
answering a text mid-tour comes back where they were.

There is no resume-later state. A half-finished tour that reappears days
afterwards is worse than one that ended, and regret is covered by replay.

### Replay

One row in `SettingsView`'s existing `section(...)` pattern — "How to read a
station" — calling the same entry path. Without it the tour is a one-shot
nobody can find again, which is not a fair place to put real explanation.

## Accessibility

**Reduce Motion** works without special handling: `jump(to:)` already lands
instantly instead of gliding (`TimelineStrip.swift:1233`), and several hours of
sky still visibly changes. The `hand.draw.fill` symbol effect stills itself.

**VoiceOver skips steps 2 and 3.** The strip is an adjustable element there,
published through `accessibilityValue` (`TimelineStrip.swift:1382`), so "swipe
the curve" is the wrong advice and the animated glide is not the affordance.
The other three steps run.

Each capsule is a single accessibility element reading its sentence, with Next
and Skip as its actions.

## Testing

**Unit.** `TourCoach` is a pure state machine — advance, skip, finish, the
arctic skip of steps 2 and 3 — tested with no view. The two target-time
functions over `[TimelineDay]` are pure and get the interesting cases: no
sunset in the window, a moon that is only ever up in daylight, a moon span
that straddles the window edge. `tourStation(near:)` gets a Canadian fix, a
US fix, and no fix.

**UI.** `-resetTour` walks all five capsules and asserts `seenTour` survives a
relaunch. The assertion that earns its keep is that `scrubStrip(app)`
(`ScreenshotTestCase.swift:212`) advances step 2 — that is the proof the
pass-through hit testing works, and it is the one thing in this design that
fails silently if it regresses.

CLAUDE.md's "no UI test can tap during momentum" applies here. The demo glide
is about 0.3 s and the capsule lives outside the scroll view, so taps should
not be deferred by it — but that is a claim to **verify on device and say so
in the PR**, not to assume.

**First run.** `scripts/first-run.sh` erases a dedicated simulator, because
uninstalling keeps the location grant and the App Group defaults. Any manual
pass on this feature uses it.

## Verified, no change needed

The queued-station row already does what this design would have asked of it.
`StationCard.swift:151` passes `cardStatusDetail(id:status:)` into
`ChsPendingCard`, which resolves through `cardDownloadLabel` to "3 of 40 to
go", "Next" or "2nd in line", at 0.82 opacity with the leaf tint only on the
station actually downloading. It was checked against the code and left alone.

## Out of scope

The downloads UI — its placement, its summary, and whether the status rises
when active — is being redesigned separately and this spec touches none of it.
Background downloads (#421), the 150 km auto-download radius and the 60-day
tide fit window are all untouched and none of this design assumes they change.

**#423 is not a dependency.** The chunk-boundary yield regression makes tapping
a queued station wait up to 157 s, but the tour only ever runs on a detail that
already has a timeline, so it never taps a queued station. If #423 lands, the
tour behaves identically.

**#317 is not a dependency either**, and the tour does not make it worse: the
station pick reads the ranking the list has already computed.

## Files

New: `TourCoach.swift`.

Edited: `Theme.swift` (the scaffold's overlay, the anchors, `ScrollViewReader`,
the `tile-moon` identifier), `DetailHeader.swift` and `TimelineStrip.swift`
(one anchor each), `StationListView.swift` (the location-path open),
`SettingsView.swift` (the replay row), `TestSeeds.swift` (the launch hooks),
and their tests.
