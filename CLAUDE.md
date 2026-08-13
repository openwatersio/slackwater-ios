# slackwater-ios

Policy (branch, PR, review, CI) is in `CONTRIBUTING.md`. Basics (branching, the test
script) are in `README.md`'s `(agents: read this)` sections. **This file is the stuff
that has actually gone wrong here** — each entry earned its place by costing a cycle,
and says what failure it prevents.

## Plans and briefs are intent, not source

Every implementation plan and task brief in `docs/superpowers/` contains hand-written
Swift that **has never been compiled**. Treat it as a precise statement of *what to
build*, not as known-good code.

Across the two plans that built the week window and the date picker, about ten defects
traced to the plan documents and roughly zero to the implementations built from them.
A representative sample:

- A `switch` written with implicit returns that only compile when the function body is
  a single expression. Cost a full test cycle to learn.
- A minimum-font-size constraint borrowed from **`slackwater-web`** and asserted as this
  repo's rule. It is not — see below.
- A flat claim that a view observed `ChsFitService.onlineFetchStamp`. It did not; the
  *list card* does. Had the implementer believed it, the whole prefetch feature would
  have been inert.
- The reassurance that the scrubber "self-corrects to something sane" when the window
  moves. It does not, and that sentence is why a **blank chart** survived four reviews.

**So: if a brief's code or a stated fact looks wrong, check it and say so rather than
complying.** Implementers refused instructions and were right at least six times in that
work. The most productive single line in any dispatch was telling them the brief was
unverified and to go looking for its bugs.

## A green suite is not a working feature

Twice, a full two-simulator run against live IWLS certified a feature that was visibly
broken. Both times the test asserted something *adjacent* to the thing that mattered.

The picker's first version moved the window's anchor correctly — label, readout, schedule
and return-to-now button all right — while the chart drew **nothing**. The test asserted
that the return-to-now control existed. It does exist, on a blank chart.

Three habits follow:

- **Assert the thing, not its neighbour.** "The control appeared" is not "the feature
  works."
- **Prove a new assertion red.** Remove the fix, watch the test fail, put it back. The
  ink-coverage check on the strip (`inkFraction`, `ScreenshotTests.swift`) was proven
  this way; the assertion it replaced was not.
- **For anything visual, open the screenshot.** `scripts/test.sh` writes them to
  `$SHOT_DIR` (default `/tmp/slackwater-shots`). A bare `xcodebuild` will not set that —
  pass `TEST_RUNNER_M1_SHOT_DIR` yourself or the images land in `/tmp`.

## This repo's conventions are not `slackwater-web`'s

Eight sibling repos share a workspace `CLAUDE.md`, which makes cross-contamination easy
and hard to spot. A real example: `slackwater-web` enforces a 14px minimum font size with
an `.eyebrow` exception (`src/tokens.test.ts`). **The iOS app has no such rule**,
`.eyebrow` is not a token here, and `.caption2` is used in 20+ places for secondary
annotation. A plan asserted the web rule as iOS law; an implementer read all 267 lines of
`TypeScaleTests.swift`, found nothing, and correctly ignored it.

Before enforcing a "rule", find it in *this* repo's tests or code.

## Calendar days are not 86,400 seconds

`addingTimeInterval` is for durations. Anything meaning *a day* goes through `Calendar`
with its `timeZone` set — local days are 23 or 25 hours across a DST transition.

Four tests once advanced an anchor by `34 * 86_400`; on **68 of 365 dates in 2026** that
lands at 01:00 or 23:00 instead of midnight, so the suite would have gone red one day in
five with no code change. Open issue #62 tracks the remaining production sites.

A related trap in the same family: a 48-hour look-back spans **three** calendar days
whenever a spring-forward sits inside it, which is why `dayChrome`'s range is `-3...8`
and not `-2...8`.

## The test machine is shared, and that shapes everything

`scripts/test.sh` self-serializes on `/tmp/slackwater-test.lock`, but the self-hosted CI
runner competes for the same Mac. Consequences worth knowing before you diagnose a
failure as yours:

- **Two concurrent `xcodebuild test` runs SIGKILL each other's test runner.** The loser
  reports "Test crashed with signal kill" with zero assertion failures, which reads
  exactly like a real failure.
- **Result bundles are `build/results-$MODE-$sim.xcresult`** — e.g.
  `results-fast-iPhone_17.xcresult`. Read the bundle, not just the exit code; a run
  killed mid-write leaves a bundle with no `Info.plist`.
- **Live-network tests with fixed timeouts fail under load.**
  `testM51PromotionInterruptsAnInFlightDownload` fails roughly two of three full runs on
  the iPad leg — which starts ~1600s in — and passes alone every time in 49 seconds
  (issue #65). **Before blaming your change: re-run the single test in isolation.**

**Fast feedback without the suite:** a compile-check takes a minute and catches most of
what a 15-minute cycle would.

```sh
lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
  -project Slackwater.xcodeproj -scheme Slackwater \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
```

`lockf -t 0` fails immediately if a run holds the machine — wait, never force it. Run it
*before* implementing too: the real compile error is better RED evidence than a
reasoned-about one.

## The window: `anchor` drives geometry, `today` drives language

The single most erodable invariant in this codebase, established in #61.

- **`anchor`** — the local midnight the window hangs from. Drives `start`, `end`, `days`,
  `scheduleRange`, `visibleDays`.
- **`today`** — the real local midnight. Drives Today/Tomorrow labels, the now-marker,
  return-to-now. **Never geometry.**

`Timeline.window(anchor:today:)` is the **only** definition of the window; four sites
once re-derived `today ± hours` by hand. The failure that prevents is a coverage check
passing on a window with a hole in it, which renders as a strip with a dead zone.

**One clock per decision.** `Timeline.window` applies the 48h back-pad on exact
`anchor == today` equality, so two independent `todayLocal(tz)` reads either side of a
local midnight silently drop it. Three instances of that were fixed in #61 and one more
in #64.

**The window's width changes with the anchor** — 228h on the current week (the back-pad
applies), 180h on any other. `TimelineScrubber.updateUIView` must resize the host frame
and `contentSize` when `totalWidth` changes; not doing so is what rendered the blank
chart.

## Working with subagents here

- **A subagent's backgrounded job dies when its turn ends.** A `./scripts/test.sh` started
  with the harness's background mechanism leaves a 0-byte log and a corrupt result bundle.
  The workable split: implementers write code and compile-check; the coordinator runs the
  suite and relays results.
- **Ask for what was *observed*, not what is believed.** Implementers here have been
  consistently honest about not having seen a run when told that an honest gap beats a
  plausible transcript. One reviewer described relayed results as "independently
  confirmed via the reviewer's own run" — worth watching for.
- **File what you leave behind.** `README.md` already says this; it matters most for the
  things a green suite hides.
