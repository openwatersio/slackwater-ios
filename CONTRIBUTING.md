# Contributing

Slackwater is a tide and current app that runs its predictions on the device. Bug reports, data corrections, and pull requests are all welcome.

## Getting started

You need **Xcode 26** or later (the app targets iOS 26) and **XcodeGen** (`brew install xcodegen`). The `.xcodeproj` and `Info.plist` are generated rather than committed, so generate them first:

```sh
git config core.hooksPath .githooks   # regenerates the project after every pull
xcodegen generate
open Slackwater.xcodeproj
```

Build and run the `Slackwater` scheme. There is no other setup — the app ships its station data, so it works offline from first launch.

All app and test targets use Swift 6 language mode. Keep UI-owned state on `MainActor` and prediction work off it. Values passed to background work should conform to `Sendable`; any `nonisolated(unsafe)` boundary needs a comment explaining the synchronization or thread-safety guarantee.

Changing the bundled data additionally needs **Node 24** and a `npm install` in `tools/`.

## Trying a first launch

Deleting the app from a simulator does not give you a first launch: the simulator keeps the location permission, the App Group defaults (favorites and recents), and iCloud. Erase a dedicated simulator instead, then build and run onto it:

```sh
./scripts/first-run.sh                            # erases and boots "SW First Run iPhone 17"
./scripts/first-run.sh "iPad Pro 11-inch (M5)"    # the same for any device type
```

An erased simulator is signed out of iCloud, so it starts with no favorites. Each of these is worth its own run: answering the location prompt both ways, Location Services switched off in Settings, and Features ▸ Location ▸ None.

For quick iteration on the gate itself, the `Slackwater First Run` scheme relaunches into first-run state without erasing anything. It clears the gate, recents, favorites, and downloaded CHS models on every launch. Location is left real, so the permission prompt only appears on a simulator that has never answered it.

## Running the watch app

Run the `SlackwaterWatch` scheme on a watch simulator; the phone schemes cannot deploy to a watch. Its UI tests run the same way, `xcodebuild test -scheme SlackwaterWatch -destination 'platform=watchOS Simulator,name=<watch>'`, under the [worktree test lock](#local-test-runs). `-locDenied` skips the location prompt, as on the phone.

The watch targets do not extract strings (`SWIFT_EMIT_LOC_STRINGS: NO` in `project.yml`), because extracting from the watch alone would drop the translator comments that only the phone's code supplies for shared keys. Building the watch scheme therefore leaves `Slackwater/Localizable.xcstrings` untouched, and a new watch string goes into the catalog by hand.

## Running on the iPhone Duo

The `iPhone Duo` simulator (iOS 27.1 and later) boots folded, on its cover screen. Only Xcode's device view can fold, half-fold, or unfold it. `simctl` has no fold control, and powering the panels on and off with `simctl io <udid> screenConfig` crashes SpringBoard. XCUITest has no fold API either, so fold behavior has no UI test; check it by hand in Xcode.

- The status bar sits in a rail on the right edge in every posture, which gives the app a trailing-only safe-area inset. Unfolded, the app runs landscape in the split layout, with the sidebar as a leading inset.
- `simctl io <udid> screenshot --display=1` captures the cover screen and `--display=3` the inner screen. The inner screen's captures are the panel's portrait framebuffer, so rotate them (`ffmpeg -vf transpose=1`) before reading them.
- `recordVideo` records one display per device at a time, so record the inner screen while someone folds it in Xcode. The recording is variable-frame-rate and writes no frames while that panel is dark, so find the folds from packet times (`ffprobe -show_entries packet=pts_time`) rather than by scrubbing through it.
- The simulator does report the hinge through `UIHingeInteraction`: the angle runs from 0 (closed) to π (flat) at about 30 Hz. Its fold control jumps between postures, though, and goes quiet for about 0.67 s at the switch to the inner screen, so judge how anything that follows the hinge feels on a device.
- `xcrun simctl launch --console-pty <udid> io.openwaters.slackwater` streams the app's `print` output while you fold.

## Screenshotting a deep-linked screen

`xcrun simctl openurl` with a `slackwater://` link (for example `slackwater://premium`, which opens the dedicated Support Slackwater sheet) raises a system "Open in “Slackwater”?" prompt that nothing on the command line can accept. The prompt stays up and covers later screenshots.

Use a throwaway UI test instead. Subclass `ScreenshotTestCase`, launch with `testArguments(["-seedGate", "-locDenied"])` (`-seedGate` skips the first-run gate), open the link with `XCUIDevice.shared.system.open(url)`, then tap `XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]` for as long as it exists. Run only that test with `-only-testing:`, passing `TEST_RUNNER_M1_SHOT_DIR` for the screenshot, and under the [worktree test lock](#local-test-runs). Delete the file and run `xcodegen generate` again before committing.

## User-facing copy

Use familiar terms such as tides, currents, and places in prominent headings, buttons, and permission copy. Reserve “station” for a specific data source or an example whose meaning is clear from context; new users should not need to know how predictions are measured.

Never write “scrub” in a string the reader sees — titles, coach marks, labels, accessibility labels. It is a developer word for the gesture, not a word people know. Say “swipe to see more”, “move through time”, or name the result instead. Code identifiers and these docs keep it. Before pushing copy near the timeline, grep `Slackwater/` for `scrub` inside string literals.

Use the SF Symbol `sparkles` beside Premium labels, headings, and purchase options. Keep the icon separate from localized text; compact widgets can use “Premium” alone as the label.

## Localization

Every user-facing string ships in English, Danish (`da`), German (`de`), Spanish (`es-ES`), Finnish (`fi`), Canadian French (`fr-CA`), Italian (`it`), Japanese (`ja`), Korean (`ko`), Norwegian Bokmål (`nb`), Dutch (`nl`), Brazilian Portuguese (`pt-BR`), European Portuguese (`pt-PT`), and Swedish (`sv`). Include translations in the same pull request as any new or changed copy, including accessibility labels and system notifications. Use SwiftUI's localized string APIs or `String(localized:)`; plain Swift strings passed to system APIs are not localized automatically.

Update `Slackwater/Localizable.xcstrings` with translator context and complete translations for every supported locale. Permission prompts live in `InfoPlist.xcstrings`, shared with the watch; Siri invocation phrases live in `AppShortcuts.xcstrings`. Preserve format placeholders and Siri's `${applicationName}` token, add plural variants where the wording requires them, and remove unused keys when deleting copy. Review the catalog diff for missing translations, then build and check the changed screens in the affected languages before opening the pull request. English fallback is not a completed translation.

A phone scheme extracts strings into the catalog on every build, which is how a new key first appears. Write a hand-added entry's locales in alphabetical order, the order Xcode itself writes. An entry stored the other way round is re-sorted by the next build, and a handful of them turns an ordinary review into a thousand-line diff carrying no content change.

Builds also rewrite the catalogs when no copy changed. Xcode reorders fields and plural variants within an entry, drops the final newline, marks keys `"extractionState" : "stale"` when the branch is behind `main`, and a watch build sets `CFBundleName` in `InfoPlist.xcstrings` to `SlackwaterWatch`. None of that is a content change, so `scripts/localization.py` passes it and only review catches it. Before committing, run `git diff --stat -- '*.xcstrings'`. If your change adds, edits, or removes no copy, revert the catalogs with `git checkout -- '*.xcstrings'`. If it does, stage only your own entries with `git add -p`.

The macOS build lane runs `python3 scripts/localization.py` after generating the project. It exports current source keys with empty temporary catalogs and extraction enabled for the phone, widgets, and watch, then restores each catalog byte for byte. Missing or stale keys, missing or unfinished translations (including plural variants), and changed format arguments or Siri app-name tokens fail the check. Only `shouldTranslate: false` exempts an entry. Translation locales come from `knownRegions` in `project.yml`, excluding `Base` and the source language. Export diagnostics are saved to `build/localization-export.log`. The small fixture check runs with `python3 scripts/localization.test.py`.

## Running the tests

One test plan, driven by `scripts/test.sh`. Fixture preparation requires Node 24;
no npm install is needed for it.

```sh
./scripts/test.sh          # offline unit + UI tests, iPhone. Use while iterating.
./scripts/test.sh --full   # offline, both reference simulators + exhaustive data test.
./scripts/test.sh --unit   # unit target only, one simulator.
./scripts/test.sh --live   # live IWLS smoke only, one simulator.
```

Routine modes validate and reuse the committed `SlackwaterTests/Fixtures/iwls-recording.json`, including on fresh CI runners. They never download test data. To update the recording explicitly, run `node scripts/iwls-fixtures.mjs refresh` and review the resulting Git diff. `SLACKWATER_FIXTURE_DIR` can supply a different recording for the offline `prepare` command to stage. Missing or corrupt recordings fail validation.

`--live` is the separate compatibility smoke for the real IWLS service. It does
not use the recording. `--full` stays offline and is the pre-release suite.

Every `xcodebuild` invocation, by hand or by script, needs `-clonedSourcePackagesDirPath build/SourcePackages`.

Tests for the bundled data are separate and fast: `cd tools && node --test`. (`npm test` regenerates everything first, including the generator that needs network access.)

### Local test runs

Local test runs share this Mac with other worktrees and sessions. CI runs on GitHub-hosted runners. Runs in different worktrees run at once: each takes only its own `build/xcodebuild.lock`, and overlapped runs on their own devices do not kill each other (measured; `scripts/test.sh` has the numbers and the history). Overlap makes UI waits ~2× slower, which the script's `TEST_RUNNER_SLACKWATER_PERF_SCALE` default absorbs; if a test fails only under overlap, re-run it alone to check whether the wait budget is responsible. What the script cannot tell you:

- **Run the shard you touched, not the suite.** CI's shard variables work locally: `SLACKWATER_ONLY=SlackwaterUITests/DetailAndScrubTests ./scripts/test.sh` is ~8 minutes against 17 for the fast run. `--full` is 65 minutes and holds the worktree's lock for all of it; it is the pre-release check, and every push to `main` runs it on hosted runners, so it is not a local gate for a PR.
- **Compile-check before (and instead of) the suite** — a minute versus fifteen, and it takes only this worktree's lock, so another worktree's test run never blocks it:

  ```sh
  mkdir -p build && lockf -t 0 build/xcodebuild.lock xcodebuild build-for-testing \
    -project Slackwater.xcodeproj -scheme Slackwater \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -derivedDataPath build/DerivedData \
    -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
  ```

  `lockf -t 0` fails immediately if a test run holds this worktree — wait, never force it. `-derivedDataPath build/DerivedData` is the path `scripts/test.sh` builds into, so the suite that follows is incremental; without it the build lands in `~/Library/Developer/Xcode/DerivedData` and the suite rebuilds from scratch.

- **The first `xcodebuild` in a new worktree can hang silently.** SwiftPM downloads MapLibre's xcframework and reads github.com credentials from the login keychain, which raises a macOS permission dialog that a detached shell has nowhere to show. `sample <xcodebuild pid>` shows `SecItemCopyMatching` under `BinaryArtifactsManager.download`. Don't wait it out: hand the command to the human to run in their own terminal and choose Always Allow. Seeding `build/SourcePackages` from a sibling worktree doesn't avoid it, because `workspace-state.json` records absolute paths.
- **One package path per worktree.** Pointing `-clonedSourcePackagesDirPath` at another checkout's `build/SourcePackages` and back re-copies MapLibre's headers, and the next build fails with "MLNShapeSource.h has been modified since the module file … was built", which is not a code error. Delete that worktree's DerivedData after confirming its `info.plist` `WorkspacePath` names the worktree.

- **Screenshots land in `/tmp` under a bare `xcodebuild`.** `scripts/test.sh` sets `TEST_RUNNER_M1_SHOT_DIR` (default `/tmp/slackwater-shots`); pass it yourself otherwise. For anything visual, open the screenshot.
- **Read the result bundle, not just the exit code** — `build/results-$MODE-$sim.xcresult`. A run killed by contention reports "Test crashed with signal kill" with zero assertion failures; a bundle with no `Info.plist` means the run died mid-write.
- **A `scripts/test.sh --live` smoke that fails under load may pass alone.** Routine suites are offline; re-run the live selection before blaming your change.
- **"Timed out trying to boot simulator after waiting 60.00s" is a stale simulator viewer, not your code.** `killall DeviceHub 2>/dev/null || killall Simulator` clears it and is safe while headless tests run — the app is only a viewer.
- **Shut down every simulator you boot** (`xcrun simctl shutdown <udid>` — never `shutdown all`; another session may be mid-test on its own device).

### Source-wide checks

Several unit tests walk every app source through `appSources()` (`SlackwaterTests/TestSources.swift`) and fail on banned text, so a brand-new file under `Slackwater/` trips them while changing nothing that exists: `TimelineTests.testNoSourceFileSpellsATwentyFourHourPattern` (no `HH:mm` — one clock, use `chartTime`), `TypeScaleTests` (retired fonts; `formatHeight(`, `formatSpeed(`, `formatNm(` and `cardTime(` must sit near `monospacedDigit()`), `ColourAndFormTests` (no `Color(hex:)` outside Theme), `HeroChromeTests` (no material imitation of glass). Run those four classes alongside your own when you add a file; they are unit tests and take seconds.

Never baseline a suspected-flaky failure by stashing your changes. A scan whose offender is your new file passes the moment the file is gone, which reads as "pre-existing" and is the exact opposite of the truth. Baseline by checking out the parent commit, and run `xcodegen generate` afterwards or the build fails on a project file still naming the removed source.

### UI test state

- **Every location state a UI test asserts on comes from a launch flag:** `-locDenied`, `-locAuthorizedNoFix`, or `-locUndetermined` (`LocationService.swift`). A simulator that has ever answered the prompt keeps an `Authorization` key in locationd's `clients.plist` for good, and local simulators also carry grants, a simulated fix, and App Group favorites that survive an uninstall. A flagless location test passes or fails by device.
- **No UI test can tap during momentum.** XCUITest defers every synthesized event until the app is quiescent, and a decelerating scroll view is not. A test written to tap mid-glide cannot fail, so verify that behavior on a device and say so in the PR.
- **Test state cannot ride on the map view.** `MLNMapView` answers `accessibilityValue` with its own zoom string.

## Reporting bugs

Open an issue. For a wrong prediction, include the station, the date and time, what the app showed, and what the official source (NOAA or CHS) showed — that is usually enough to tell a data problem from an engine problem. For anything else, the device and iOS version help.

## Pull requests

Work on a branch and open a pull request.

```sh
git switch -c <area>/<short-description>    # e.g. tides/ticon-licence-gate
git push -u origin HEAD
gh pr create --fill
```

Before you open it, run the relevant tests with `./scripts/test.sh` and say in the description what you changed and why. Small PRs get reviewed faster. Rebase or squash rather than merge-commit, and never force-push `main` — your own branches, freely.

## License and CLA

Slackwater is licensed under [GPL-3.0](LICENSE.md). All contributors must sign the [Contributor License Agreement](CLA.md) before their pull request can be merged. The CLA grants Open Water Software, LLC the rights needed to distribute your contributions (including through the iOS App Store) while you retain full copyright ownership of your work — [docs/licensing.md](docs/licensing.md) explains why a GPL app on the App Store needs this.

You will be prompted to sign the CLA automatically when you open your first pull request.

## Changing bundled station data

The JSON files in `Slackwater/Resources/` are generated artifacts, not source; [their README](Slackwater/Resources/README.md) describes the inputs. Edit the generator or its upstream input, then regenerate:

```sh
cd tools && npm run build:data
```

The generators run as a chain — CHS stations, then tides, then NOAA currents, then CHS gates — and each reads the one before it, so a change anywhere means regenerating all of them and committing every changed artifact together. CI regenerates `stations.json` and `currents.json` and fails if the committed copies differ.

Because the diff is one enormous line of JSON, say in the PR description what the counts went from and to. Nothing checks what the diff _means_, so read it: dropping a tide station can silently unpair the current stations that referenced it.

A stale `@slackwater/database` pin is a slug hazard. A bump can swap stations in the bundle, and `tools/gen-slugs.mjs` fails outright on a station with no published slug. Fix it upstream: run station-metadata's `slugs` command, release, then bump the pin here. Frequent bumps keep station swaps small.

Every bump goes to [slackwater.xyz](https://github.com/openwatersio/slackwater.xyz) too, pinned to the same release, so the site and the app name, place, and credit every station alike. slackwater-database's [CONTRIBUTING](https://github.com/openwatersio/slackwater-database/blob/main/CONTRIBUTING.md#releases) owns the rule.

A PR with a visual change must upload before and after screenshots in its
description so the reviewer can see the change without checking out the branch.
Present them side by side:

```md
| Before | After |
|---|---|
| ![Before](uploaded-image-url) | ![After](uploaded-image-url) |
```

Non-visual changes do not need screenshots.

## Implementation constraints

### Timeline windows

`anchor` is the station-local midnight of the schedule week. `today` drives Today/Tomorrow labels; `now` drives the reference dot and return-to-now. Tide, harmonic-current, and derived-gate details use `TimelineWindowStore`'s seven-calendar-day chunks for continuous scrolling. Their loaded span is independent of the schedule anchor. The online-current detail remains bounded by `Timeline.window(anchor:)`: 228 elapsed hours with an unconditional 48-hour back-pad. That function also defines when the continuous details re-anchor their schedule after a settled scrub. Do not re-derive either window.

### Calendar days

Anything meaning _a day_ goes through `Calendar` with its `timeZone` set. `addingTimeInterval` is only for durations — local days are 23 or 25 hours across a DST transition, and a 48-hour look-back can span three calendar days.

### Yearly tidal claims

Gate yearly and absolute claims about water **level** (LAT/HAT, "the lowest low of the year") on the station having a non-zero `SA` or `SSA`, never on whether it is CHS. The bundle encodes this already: `astronomicalBounds` in `tools/gen-tides.mjs` emits `latDatum`/`hatDatum` only where `@slackwater/database` publishes LAT/HAT, which it omits when Sa and Ssa are both zero. CHS on-device fits never have them (`tideFitDays` is 60 and separating Sa/Ssa needs 183; see `ChsFitter.basis`), and about a fifth of NOAA's harmonic references lack them too. Fortnightly and perigean claims hold everywhere.

**The same gate is wrong for a claim about range**, and applying it there is a mistake this app has already made and reverted (#640, then #641, which hid the Range sheet's year section at every CHS station and the fifth of NOAA references without bounds). The physics, the measurements and the rule for both kinds of claim live with the engine that does the ranking — [slackwater `docs/CONTRACT.md`, "What a ranking window can claim"](https://github.com/openwatersio/slackwater/blob/main/docs/CONTRACT.md). Read it before gating anything seasonal.

What is this repo's own: `YearFigureTests.testTheSeasonalShapeDoesNotNeedAnAnnualConstituent` pins the counter-example — Chignik, which has no bounds, varies more across the year than Portland, which has them — so reintroducing the gate on the Sa/Ssa theory fails here with the evidence in hand. `docs/detail.md` §6.4 and §6.5 record which sections are gated and which are not.

A subordinate's reduced LAT/HAT is the floor of a prediction, not a datum. It belongs in `latDatum`/`hatDatum`, never in `datums`, where tide-database's datum-ordering gate rejects it.

### Astronomy belongs in Almanac

When the app needs something [Almanac](https://github.com/openwatersio/almanac) lacks, file the issue there instead of porting the math into the app.

### Launch performance

SwiftUI's `.task` runs inside UIKit's first-commit block, so synchronous work there still delays the first frame. Hop off the main actor with `Task.detached`, as `StationIndexInfo.resolveTideRecord` does. To measure launch, run `sample <pid> 4 1 -mayDie` right after `simctl launch` and look under `_firstCommitBlock`; xctrace's App Launch template hangs against the simulator.

## CI

`Required checks` in `.github/workflows/ci.yml` is the protected-branch merge gate. It requires the change filter, data generators, TestFlight intake, and app build/tests to succeed; a docs-only app skip is accepted. The branch rule does not require an up-to-date PR branch.

| Job             | Where         | What it does                                                  |
| --------------- | ------------- | ------------------------------------------------------------- |
| What changed    | GitHub-hosted | Decides whether the app lane needs to run                     |
| Data generators | GitHub-hosted | Regenerates the bundles, checks committed copies, and runs CI/release tooling checks |
| TestFlight intake | GitHub-hosted | Tests and type-checks the TestFlight feedback service (`services/testflight-feedback`) |
| Build for testing | GitHub-hosted | Builds the app and its test bundles once and uploads them |
| App tests       | GitHub-hosted | Runs `scripts/test.sh` against that upload in five shards: iPhone only for PRs; `--full` on iPhone and iPad for pushes to `main` |

The five shard names remain offline, list, transition, detail, and rest. Settings methods are spread across the first four using measured iPhone/iPad durations; rest skips only the selected tests and catches new classes and methods. `ruby scripts/test-shards.test.rb` checks that source test methods run exactly once. Alert popup tests run in offline; accessibility audits and tour tests run in detail. Each hosted runner uses one simulator worker.

New app PR commits cancel obsolete build and shard jobs. Main build and shard jobs use a separate concurrency group for each workflow run, so newer pushes cannot replace pending siblings of a full validation attempt. This preserves complete results for each SHA and can queue more main work within the five macOS slots. Docs-only changes never enter those concurrency groups. Full main validation remains exhaustive on both devices. PR validation remains exhaustive on iPhone; no extra iPad job is booked into the five macOS slots. iPad-specific failures therefore still require main validation or a targeted local check before merge.

Closing or merging a PR cancels its unfinished CI runs for the closing head commit. Cleanup matches the CI workflow, PR number, head repository, branch, and commit; it leaves main runs and attempts started after closure untouched. Reopened PRs are checked again before cancellation. CI runs without a PR number in their run name are left alone.

Nightly checks out the triggering immutable commit and requires a completed successful main CI run at that exact SHA, with the build and all ten iPhone/iPad app jobs successful. A docs-only green run cannot authorize a release. Test summary artifacts are retained for every attempt, failure artifacts include raw logs and result bundles, and the shared build upload remains available for seven days.

Every lane runs on ephemeral GitHub-hosted runners — no shared machine, no lock contention with local test runs. Public-repo macOS pools can queue a few minutes at peak; annoying, not blocking.

Every generator reads local files only, so CI regenerates all of them with `npm run build:data`.

### Reading a CI failure

`scripts/test.sh` pipes `xcodebuild` through `tail`, so the test step's log holds only the "Failing tests:" block, where names repeat even for a single attempt. The assertion text is in the job's "Failure messages" step and its step summary; the UI hierarchy and screen recording are in the `test-evidence-<shard>` artifact:

```sh
gh run download <run-id> -D <dir>
xcrun xcresulttool get test-results tests --path <bundle>                    # assertion text
xcrun xcresulttool export attachments --path <bundle> --output-path <dir>    # UI hierarchy at the failure
```

- **`gh run watch --exit-status` can exit 0 for a failed run.** Confirm with `gh run view <run-id> --json conclusion`.
- **Match a run's sha to the PR head before rerunning it.** `gh run rerun` on a run whose sha is no longer the head re-enters the concurrency group and cancels the live run for the current commit, so you lose the result you were waiting for and re-create one you no longer need. `gh pr view <n> --json headRefOid` against `gh run view <id> --json headSha`. Take a job's duration from its `started_at` and `completed_at`, never from an estimate — a 60-minute job that hit `timeout-minutes` and one cancelled at 43 minutes by a newer push look identical in the UI.
- **Check `main`'s most recent run when you open a pull request and when one merges.** A pull request runs `iPhone 17` only; a push to `main` runs `--full` on both devices, so the iPad leg can only ever go red after a merge, and a PR that was green tells you nothing about it. `gh run list --workflow=ci.yml --branch main --limit 1`, then report what is there rather than fixing it silently — a `· iPad` job may be a standing failure that is not yours.
- **A slow green lane may be a stalled one.** XCUITest waits for the app to report its animations complete before every synthesized event and every query, and spends 60 s on the wait when that report never comes — six of them in one test on run 36790016201, 494 s against 39 s locally (#556). The run still passes, so grep the job log for the line `scripts/test.sh` prints when it finds any: `warning: N XCUITest idle timeouts`. A test whose excess over its usual time is a whole multiple of 60 s is this and not a slow runner, and the dropped taps it causes report as ordinary assertion failures. The UI tests launch with `-uiTestQuiet` so the app has no animations to finish; the screenshot walks do not.
- **A job log that comes back empty is `gh` refusing colour codes, not a missing log.** xcodebuild writes terminal escape sequences, and `gh api …/jobs/<id>/logs` prints nothing (exit 0) unless given `--allow-escape-sequences`; `gh run view --job <id> --log` has the same silence. Strip them with `sed 's/\x1b\[[0-9;]*m//g'` before grepping.
- **Classify by the message before re-running.** An assertion string is a test defect. `Failed to get screenshot`, `Failed to get matching snapshots`, and `Failed to terminate` are XCUITest's own services timing out on the runner; CI reruns just the failed tests once when every message in a shard is one of those or a native execution timeout (`ci.yml`, "Rerun tests that timed out"), so a shard that is still red has either an assertion or a second timeout, and the job log shows which. The same test failing at the same line on unrelated branches is not flake. Before blaming a branch, check whether `main` failed the same lane recently (#331, #378).
- **For a tap that did nothing,** line up the timestamps from `xcrun xcresulttool get test-results activities --test-id <id>` against frames from the screen-recording attachment. Recordings are variable-frame-rate, so list the real frame times with `ffprobe -show_entries frame=pts_time` before sampling.

## Release and device validation

A check that only a person can make goes in an issue labelled `manual testing`: anything that needs a device or a watch, or a simulator state no UI test can reach, such as a folded iPhone Duo. A pull request's checklist stops being tracked once it merges, so move any device check still open at merge into an issue, the way #610 collects the phone's. `gh issue list --label "manual testing"` is the queue.

Debug-on-simulator and Release-archive differ in signing, entitlements, StoreKit source, and version numbering. Signing and provisioning traps are documented where they live (`project.yml` comments, `docs/testflight.md`, the `releasing-to-testflight` skill). Also check these constraints:

- The `.storekit` file is wired to the scheme's `run:` action, so StoreKit works in the simulator and silently does not in an archive, where `Product.products(for:)` goes to real App Store Connect. Check `inAppPurchasesV2` and `subscriptionGroups` on the app before writing a word about a purchase.
- App Groups are not in the App Store Connect API (`/v1/appGroups` is a 404). Creating one is developer.apple.com UI work; budget a human for it.
- **The widget's station picker never applies in the simulator.** linkd cannot read a simulator process's team id, so the App Intents runtime logs "StationChoice is not a registered AppEntity identifier" and resolves the configured station to nil — every widget shows the default station. Re-signing the simulator build with a real identity does not help. Verify the picker on a device.

## Documentation

Keep documentation that has an ongoing reader: product contracts, architecture constraints, operating procedures, release notes, and validation evidence. Describe the current behavior and update the existing document when it changes. [docs/README.md](docs/README.md) is the index.

Put implementation plans, task checklists, session reports, and spike scratch in ignored `.superpowers/` or `/tmp`, including when a workflow suggests `docs/superpowers/`. Use issues and PRs for proposed work and review history; a merged proposal is not evidence that the behavior ships. Do not commit completed implementation diaries or obsolete prototypes. Before removing a completed experiment, move any lasting constraints or measurements into the appropriate living document. Code imported by a maintained pipeline belongs under `tools/`, with its reproduction instructions and checks. Generated data provenance and release records remain durable evidence.

Verify claims against this repo's tests and code; sibling repos can have different conventions. A scrubber behavior change updates [docs/scrubber.md](docs/scrubber.md) in the same PR. A list or detail behavior change updates [docs/list.md](docs/list.md) or [docs/detail.md](docs/detail.md) the same way. These three are the reference contracts other platforms build from.

Review every scrubber presentation change in `TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView`, `OnlineGateDetailView`, and the watch's `PlaceDetail` (`SlackwaterWatch/`), which draws the same canvas under the Digital Crown. `ChsDetailView` is a routing wrapper, not a sixth presentation.

## AI agents

Agents work here under the same policy as everyone else, with one addition: an agent never merges its own PR. Docs-only work gets a PR like anything else — the `What changed` job keeps it off the macOS lane, and a docs PR that books one is a bug in that job, not a reason to skip review.

A subagent's backgrounded job dies when its turn ends — a `./scripts/test.sh` started that way leaves a 0-byte log and a corrupt result bundle. Implementers write code and compile-check; the coordinator runs the suite and relays results. Ask subagents for what they _observed_, not what they believe.
