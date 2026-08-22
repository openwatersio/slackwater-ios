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

## Editing `chs-stations.json` changes `stations.json` too

The generators are not independent. `gen-tides.mjs` reads the **committed**
`chs-stations.json` and cedes Canadian water to CHS within `CHS_COVERAGE_KM`, so a
TICON gap-fill only ships where CHS has nothing nearby. Add or remove a CHS station
and the set of TICON stations that survive changes with it.

So **any change to `chs-stations.json` needs `node gen-tides.mjs` re-run and its
artefact committed in the same PR.** The CI data job regenerates and
`git diff --exit-code`s exactly this, which is how a PR that dropped 28 dead CHS
stations went red after a green local `node --test` — the tests assert on the
committed artefact, and nothing local had regenerated it.

Worth knowing when it happens: the un-suppressed TICON rows are real stations, and
the result was five Great Lakes and St. Lawrence gauges going from unusable to
usable. Read the regenerated diff before assuming it is noise.

**And `stations.json` changes `currents.json` too** — the same coupling one link
further down the chain. `gen-noaa-currents.mjs` resolves each current station's
**region line** *and* its **`tideReference`** against the committed tide bundle
(`:95`, `:105-110`), so a tide station leaving `stations.json` silently unpairs the
current stations that pointed at it. The world-coverage datum gate dropped Fire
Island and Port MacKenzie; four NOAA Cook Inlet current stations (`noaa/COI1209`,
`COI0301`, `COI0302`, `COI0303`) lost their `tideReference` as a result, and
`CurrentStation.swift:69` / `OnlineGateDetailView.swift:29` render that pairing —
so those views quietly fell back to current-only. Two more (`SEA0307`, `PWS0710`)
changed region line. **So: `node gen-tides.mjs` is always followed by
`node gen-noaa-currents.mjs`, and both artefacts go in the same commit.** CI's
`git diff --exit-code` catches the omission; nothing catches the *meaning* of the
diff, so read it.

The same trap in miniature: `untrail()` keys on the row's own state code, and
upstream mislabels several Ontario gauges as `MI` or a bare GeoNames number, so a
newly-surfaced station can ship "Tecumseh Ontario · ON" and trip the name invariant.
It now also tries the code the region line ends in.

## `tile-join` drops features and widens bounds, both silently

`pmtiles extract` clips by bbox and zoom only, so cutting a tileset down to the source-layers
a style actually reads needs a `tile-join` pass. #107 took `seamap.pmtiles` from 25.9 MB to
4.1 that way — two thirds of the artifact was layers nothing drew. Two traps in that one
command, and neither says anything when it bites:

- **The default 500 KB tile ceiling DROPS features to stay under it.** `-pk` disables it.
  Nothing in the seamap cuts is near the limit — with and without the flag the output differs
  by exactly the six bytes the flag adds to the metadata, which is the cheap way to re-check
  it — but the failure mode is a chart quietly missing buoys behind a green build.
- **The output header's bounds become the whole planet**, whatever the input's were.
  MapLibre builds its TileJSON from that header, so a Salish-only artifact starts advertising
  global coverage and gets asked for tiles that cannot exist. `pmtiles show --header-json` on
  the extract, `pmtiles edit --header-json` onto the result — copy the real header back rather
  than recomputing one from the bbox.

Both are handled in `tools/build-seamap.sh`. The note is here because the next tileset that
wants stripping will not be built by reading that file first.

Third, smaller: **`tile-join` output is not byte-deterministic.** The same inputs give
archives differing by a few bytes (8,505,255 / …256 / …260 across three runs of the same
script), so a rebuild always shows a diff on the artifact. That is not content drift, and a
rebuild that changes nothing else does not need committing.

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
  the iPad leg — which starts late, after the whole iPhone leg — and passes alone every
  time in 49 seconds (issue #65). **Before blaming your change: re-run the single test
  in isolation.** This is a `--full` problem only: the fast run is iPhone-only, so the
  iPad leg no longer exists there at all.
- **"Timed out trying to boot simulator after waiting 60.00s" means a stale
  Simulator.app, not your code.** A long-running Simulator.app wedges every new device
  boot — a 12-day-old instance did this on the Studio (2026-08-21), and the same
  symptom+fix showed on a MacBook the same day. `killall Simulator` clears it, and is
  safe while another session's headless `xcodebuild test` is mid-run: its booted
  devices re-boot headless under CoreSimulatorService (verified against a live run).
  The app is only a viewer; nothing on this machine needs it running.
- **Shut down every simulator you boot when you're done with it** (`xcrun simctl
  shutdown <udid>` — never `shutdown all`; another session or CI may be mid-test on
  its own device). Left-behind sims accumulate: the Studio reached 608 CoreSimulator
  processes holding 60.8 GB RSS, most of them 7 days old, before anyone noticed.

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

## A workflow verified locally is not verified

The docs-only gate in `ci.yml` — the job that skips the Studio lane when a PR touches
nothing but `docs/` and top-level `.md` — took **three** PRs to work. Each time it was
"verified locally" first, and each time the local run differed from CI in exactly the
dimension that hid the bug.

- **GitHub runs `run:` blocks as `bash -e {0}`. Your shell does not.** `grep -v` exits
  **1** when it filters everything out — which is precisely the docs-only case the gate
  exists to detect — so the step aborted before writing its decision. The gate went red
  on `main` on the very first case it got right: `App tests` correctly skipped, but
  because the job had died, not because it had decided. Test workflow shell with
  `bash -e`, not `bash`.
- **The workflow's `GITHUB_TOKEN` is not your `gh` token.** This repo's
  `default_workflow_permissions` is `read` — GitHub's *restrictive* setting, contents and
  packages only, **no `pull-requests` scope**. So `gh api .../pulls/N/files` 403s unless
  the job asks for it. Locally it worked, because a personal token has the scope. The
  gate shipped completely inert and every docs PR still booked the Studio for 25 minutes.
  Check `gh api /repos/OWNER/REPO/actions/permissions/workflow` before assuming an API
  call will work in a job.
- **A fail-safe that succeeds silently is indistinguishable from a working feature.**
  Both bugs above were invisible because the job went green either way — falling through
  to "run the suite" is the *safe* direction, and it hid two consecutive failures. The
  step now emits a `::warning::` when it cannot decide. Any guard whose failure mode is
  "quietly do the conservative thing" needs to say so out loud, or nobody learns it
  broke.

The generalisable bit: for CI logic, "I ran it locally" is worth much less than it feels,
because the interesting failures live in the *differences* between the two environments —
shell flags, token scopes, event payloads. Replay the real inputs (`gh api` the actual PR
number, the actual base/head SHAs) under the real flags, or accept that you have tested
something adjacent.

## The window: `anchor` drives geometry, `today` drives language

The single most erodable invariant in this codebase, established in #61.

- **`anchor`** — the local midnight the window hangs from. Drives `start`, `end`, `days`,
  `scheduleRange`, `visibleDays`.
- **`today`** — the real local midnight. Drives Today/Tomorrow labels, the now-marker,
  return-to-now. **Never geometry.**

`Timeline.window(anchor:)` is the **only** definition of the window; four sites once
re-derived `today ± hours` by hand. The failure that prevents is a coverage check
passing on a window with a hole in it, which renders as a strip with a dead zone.

**The 48h back-pad is unconditional (#67 item 1).** Every window carries it, not just
today's — it used to apply only on exact `anchor == today` equality, so two independent
`todayLocal(tz)` reads either side of a local midnight could silently drop it. Three
instances of that were fixed in #61 and one more in #64; the unconditional shape retires
the whole defect class rather than fixing the next instance of it.

**The window's width is a constant 228h, for every anchor** — the back-pad no longer
varies it. `TimelineScrubber.updateUIView` still resizes the host frame and
`contentSize` whenever `totalWidth` changes; that guard is what rendered the blank
chart the one time it was missing, and stays in place even though an anchor pick alone
can no longer trigger it.

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
