# slackwater-ios

Read [CONTRIBUTING.md](CONTRIBUTING.md) first for policy and basics: branching, PRs, review, CI, and how to run the tests.

## Plans and specs are intent, not source

The Swift in `docs/superpowers/` plans and specs has never been compiled. Treat it as a statement of what to build, not known-good code — verify its code and factual claims against the repo before following them, and say so when a brief is wrong.

Before enforcing a "rule", find it in this repo's tests or code. Sibling repos (`slackwater-web` especially) have different conventions, and plans sometimes import them.

## Generated data is a chain

The JSON files in `Slackwater/Resources/` are committed generated artifacts (see `Slackwater/Resources/README.md`). The generators depend on each other's committed output: CHS stations → tides → NOAA currents → CHS gates. Any change to one means `cd tools && npm run build:data` and committing every changed artifact together. CI regenerates and `git diff --exit-code`s `stations.json` and `currents.json`, but nothing checks what the diff _means_ — a tide station leaving `stations.json` silently unpairs current stations whose `tideReference` pointed at it. Read the regenerated diff before assuming it is noise.

## The window: `anchor` drives geometry, `today` drives language

`anchor` — the local midnight the window hangs from — drives `start`, `end`, `days`, `scheduleRange`, `visibleDays`. `today` — the real local midnight — drives only Today/Tomorrow labels, the now-marker, and return-to-now. Never geometry. `Timeline.window(anchor:)` (`Slackwater/TimelineStrip.swift:131`) is the **only** definition of the window; do not re-derive it. The width is a constant 228h with an unconditional 48h back-pad, for every anchor.

## A scrubber change has four consumers

Review every scrubber presentation change in `TideDetailView`, `CurrentDetailView`, `DerivedGateDetailView`, and `OnlineGateDetailView`. `ChsDetailView` is a routing wrapper, not a fifth presentation.

## Calendar days are not 86,400 seconds

Anything meaning _a day_ goes through `Calendar` with its `timeZone` set. `addingTimeInterval` is only for durations — local days are 23 or 25 hours across a DST transition, and a 48-hour look-back can span three calendar days.

## The test machine is shared

`scripts/test.sh` self-serializes on `/tmp/slackwater-test.lock` and explains the contention failure modes in its header comments. What the script cannot tell you:

- **Compile-check before (and instead of) the suite** — a minute versus fifteen:

  ```sh
  lockf -t 0 /tmp/slackwater-test.lock xcodebuild build-for-testing \
    -project Slackwater.xcodeproj -scheme Slackwater \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tail -20
  ```

  `lockf -t 0` fails immediately if a run holds the machine — wait, never force it.

- **Screenshots land in `/tmp` under a bare `xcodebuild`.** `scripts/test.sh` sets `TEST_RUNNER_M1_SHOT_DIR` (default `/tmp/slackwater-shots`); pass it yourself otherwise. For anything visual, open the screenshot.
- **Read the result bundle, not just the exit code** — `build/results-$MODE-$sim.xcresult`. A run killed by contention reports "Test crashed with signal kill" with zero assertion failures; a bundle with no `Info.plist` means the run died mid-write.
- **A `scripts/test.sh --live` smoke that fails under load may pass alone.** Routine suites are offline; re-run the live selection before blaming your change.
- **"Timed out trying to boot simulator after waiting 60.00s" is a stale `Simulator.app`, not your code.** `killall Simulator` clears it and is safe while headless tests run — the app is only a viewer.
- **Shut down every simulator you boot** (`xcrun simctl shutdown <udid>` — never `shutdown all`; another session or CI may be mid-test on its own device).

## The archive signs differently from everything you tested

Debug-on-simulator and Release-archive differ in signing, entitlements, StoreKit source, and version numbering. Signing and provisioning traps are documented where they live (`project.yml` comments, `docs/testflight.md`, the `releasing-to-testflight` skill). Two that aren't:

- The `.storekit` file is wired to the scheme's `run:` action, so StoreKit works in the simulator and silently does not in an archive, where `Product.products(for:)` goes to real App Store Connect. Check `inAppPurchasesV2` and `subscriptionGroups` on the app before writing a word about a purchase.
- App Groups are not in the App Store Connect API (`/v1/appGroups` is a 404). Creating one is developer.apple.com UI work; budget a human for it.
- **The widget's station picker never applies in the simulator.** linkd cannot read a simulator process's team id, so the App Intents runtime logs "StationChoice is not a registered AppEntity identifier" and resolves the configured station to nil — every widget shows the default station. Re-signing the simulator build with a real identity does not help. Verify the picker on a device.

## Working with subagents here

A subagent's backgrounded job dies when its turn ends — a `./scripts/test.sh` started that way leaves a 0-byte log and a corrupt result bundle. Implementers write code and compile-check; the coordinator runs the suite and relays results. Ask subagents for what they _observed_, not what they believe.
