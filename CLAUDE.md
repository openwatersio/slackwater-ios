# slackwater-ios

Read [CONTRIBUTING.md](CONTRIBUTING.md) first for policy and basics: branching, PRs, review, CI, and how to run the tests.

## Keep only lasting documentation

Follow CONTRIBUTING.md's documentation policy. Use ignored `.superpowers/` for plans, task briefs, and spike output, including when a workflow suggests `docs/superpowers/`. Keep proposed work in its issue or PR; a merged proposal is not evidence that the behavior ships. Promote lasting decisions into the relevant living document and reusable experiment code into `tools/` with checks. Do not commit completed implementation diaries or obsolete prototypes.

Verify claims against this repo's tests and code. Sibling repos can have different conventions. The detail scrubber's maintained contract is [docs/scrubber.md](docs/scrubber.md).

## Generated data is a chain

The JSON files in `Slackwater/Resources/` are committed generated artifacts (see `Slackwater/Resources/README.md`). The generators depend on each other's committed output: CHS stations → tides → NOAA currents → CHS gates. Any change to one means `cd tools && npm run build:data` and committing every changed artifact together. CI regenerates and `git diff --exit-code`s `stations.json` and `currents.json`, but nothing checks what the diff _means_ — a tide station leaving `stations.json` silently unpairs current stations whose `tideReference` pointed at it. Read the regenerated diff before assuming it is noise.

A stale `@slackwater/database` pin is a slug hazard. A bump can swap stations in the bundle (one multi-week bump traded `noaa/8723887` for `noaa/8655875`), and `tools/gen-slugs.mjs` fails outright on a station with no published slug. Fix it upstream: run station-metadata's `slugs` command, release, then bump the pin here. Bumped often, each swap is a one-station fix.

## The window: `anchor` drives the schedule, `today` drives language

`anchor` is the station-local midnight of the schedule week. `today` drives Today/Tomorrow labels; `now` drives the reference dot and return-to-now. Tide, harmonic-current, and derived-gate details use `TimelineWindowStore`'s seven-calendar-day chunks for continuous scrolling. Their loaded span is independent of the schedule anchor. The online-current detail remains bounded by `Timeline.window(anchor:)`: 228 elapsed hours with an unconditional 48-hour back-pad. That function also defines when the continuous details re-anchor their schedule after a settled scrub. Do not re-derive either window.

## A scrubber change has four consumers

Review every scrubber presentation change in `TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView`, and `OnlineGateDetailView`. `ChsDetailView` is a routing wrapper, not a fifth presentation.

## Calendar days are not 86,400 seconds

Anything meaning _a day_ goes through `Calendar` with its `timeZone` set. `addingTimeInterval` is only for durations — local days are 23 or 25 hours across a DST transition, and a 48-hour look-back can span three calendar days.

## Yearly tidal claims need an annual constituent

Gate yearly and absolute claims (LAT/HAT, "highest of the year") on the station having a non-zero `SA` or `SSA`, never on whether it is CHS. The bundle encodes this already: `astronomicalBounds` in `tools/gen-tides.mjs` emits `latDatum`/`hatDatum` only where `@slackwater/database` publishes LAT/HAT, which it omits when Sa and Ssa are both zero. CHS on-device fits never have them (`tideFitDays` is 60 and separating Sa/Ssa needs 183; see `ChsFitter.basis`), and about a fifth of NOAA's harmonic references lack them too. Fortnightly and perigean claims hold everywhere.

A subordinate's reduced LAT/HAT is the floor of a prediction, not a datum. It belongs in `latDatum`/`hatDatum`, never in `datums`, where tide-database's datum-ordering gate rejects it.

## Astronomy belongs in Almanac

When the app needs something [Almanac](https://github.com/openwatersio/almanac) lacks, file the issue there instead of porting the math into the app. almanac#6 and almanac#12 were each filled the same day.

## `.task` work lands on the first frame

SwiftUI's `.task` runs inside UIKit's first-commit block, so synchronous work there still delays the first frame. Hop off the main actor with `Task.detached`, as `StationIndexInfo.resolveTideRecord` does. To measure launch, run `sample <pid> 4 1 -mayDie` right after `simctl launch` and look under `_firstCommitBlock`; xctrace's App Launch template hangs against the simulator.

## The test machine is shared

Not with CI — every lane is GitHub-hosted since #327. Shared with the other worktrees and sessions on this Mac, of which there are usually several: two `xcodebuild test` runs here still SIGKILL each other. `scripts/test.sh` self-serializes on `/tmp/slackwater-test.lock` and explains the contention failure modes in its header comments. What the script cannot tell you:

- **Compile-check before (and instead of) the suite** — a minute versus fifteen:

  ```sh
  lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
    -project Slackwater.xcodeproj -scheme Slackwater \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
  ```

  `lockf -t 0` fails immediately if a run holds the machine — wait, never force it.

- **The first `xcodebuild` in a new worktree can hang silently.** SwiftPM downloads MapLibre's xcframework and reads github.com credentials from the login keychain, which raises a macOS permission dialog that a detached shell has nowhere to show. `sample <xcodebuild pid>` shows `SecItemCopyMatching` under `BinaryArtifactsManager.download`. Don't wait it out: hand the command to the human to run in their own terminal and choose Always Allow. Seeding `build/SourcePackages` from a sibling worktree doesn't avoid it, because `workspace-state.json` records absolute paths.
- **One package path per worktree.** Pointing `-clonedSourcePackagesDirPath` at another checkout's `build/SourcePackages` and back re-copies MapLibre's headers, and the next build fails with "MLNShapeSource.h has been modified since the module file … was built", which is not a code error. Delete that worktree's DerivedData after confirming its `info.plist` `WorkspacePath` names the worktree.

- **Screenshots land in `/tmp` under a bare `xcodebuild`.** `scripts/test.sh` sets `TEST_RUNNER_M1_SHOT_DIR` (default `/tmp/slackwater-shots`); pass it yourself otherwise. For anything visual, open the screenshot.
- **Read the result bundle, not just the exit code** — `build/results-$MODE-$sim.xcresult`. A run killed by contention reports "Test crashed with signal kill" with zero assertion failures; a bundle with no `Info.plist` means the run died mid-write.
- **A `scripts/test.sh --live` smoke that fails under load may pass alone.** Routine suites are offline; re-run the live selection before blaming your change.
- **"Timed out trying to boot simulator after waiting 60.00s" is a stale simulator viewer, not your code.** `killall DeviceHub 2>/dev/null || killall Simulator` clears it and is safe while headless tests run — the app is only a viewer.
- **Shut down every simulator you boot** (`xcrun simctl shutdown <udid>` — never `shutdown all`; another session may be mid-test on its own device).

## Reading a CI failure

`scripts/test.sh` pipes `xcodebuild` through `tail`, so a job log holds only the "Failing tests:" block, where names repeat even for a single attempt. The failure itself is in the `test-evidence-<shard>` artifact:

```sh
gh run download <run-id> -D <dir>
xcrun xcresulttool get test-results tests --path <bundle>                    # assertion text
xcrun xcresulttool export attachments --path <bundle> --output-path <dir>    # UI hierarchy at the failure
```

- **`gh run watch --exit-status` can exit 0 for a failed run.** Confirm with `gh run view <run-id> --json conclusion`.
- **Classify by the message before re-running.** An assertion string is a test defect. `Failed to get screenshot`, `Failed to get matching snapshots`, and `Failed to terminate` are XCUITest's own services timing out on the runner, so re-run. The same test failing at the same line on unrelated branches is not flake. Before blaming a branch, check whether `main` failed the same lane recently (#331, #378).
- **For a tap that did nothing,** line up the timestamps from `xcrun xcresulttool get test-results activities --test-id <id>` against frames from the screen-recording attachment. Recordings are variable-frame-rate, so list the real frame times with `ffprobe -show_entries frame=pts_time` before sampling.

## What a UI test cannot control

- **Every location state a UI test asserts on comes from a launch flag:** `-locDenied`, `-locAuthorizedNoFix`, or `-locUndetermined` (`LocationService.swift`). A simulator that has ever answered the prompt keeps an `Authorization` key in locationd's `clients.plist` for good, and local simulators also carry grants, a simulated fix, and App Group favorites that survive an uninstall. A flagless location test passes or fails by device.
- **No UI test can tap during momentum.** XCUITest defers every synthesized event until the app is quiescent, and a decelerating scroll view is not. A test written to tap mid-glide cannot fail, so verify that behavior on a device and say so in the PR.
- **Test state cannot ride on the map view.** `MLNMapView` answers `accessibilityValue` with its own zoom string.

## The archive signs differently from everything you tested

Debug-on-simulator and Release-archive differ in signing, entitlements, StoreKit source, and version numbering. Signing and provisioning traps are documented where they live (`project.yml` comments, `docs/testflight.md`, the `releasing-to-testflight` skill). Two that aren't:

- The `.storekit` file is wired to the scheme's `run:` action, so StoreKit works in the simulator and silently does not in an archive, where `Product.products(for:)` goes to real App Store Connect. Check `inAppPurchasesV2` and `subscriptionGroups` on the app before writing a word about a purchase.
- App Groups are not in the App Store Connect API (`/v1/appGroups` is a 404). Creating one is developer.apple.com UI work; budget a human for it.
- **The widget's station picker never applies in the simulator.** linkd cannot read a simulator process's team id, so the App Intents runtime logs "StationChoice is not a registered AppEntity identifier" and resolves the configured station to nil — every widget shows the default station. Re-signing the simulator build with a real identity does not help. Verify the picker on a device.

## Working with subagents here

A subagent's backgrounded job dies when its turn ends — a `./scripts/test.sh` started that way leaves a 0-byte log and a corrupt result bundle. Implementers write code and compile-check; the coordinator runs the suite and relays results. Ask subagents for what they _observed_, not what they believe.
