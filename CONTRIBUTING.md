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

Run the `SlackwaterWatch` scheme on a watch simulator; the phone schemes cannot deploy to a watch. Its UI tests run the same way, `xcodebuild test -scheme SlackwaterWatch -destination 'platform=watchOS Simulator,name=<watch>'`, under the test lock described in CLAUDE.md. `-locDenied` skips the location prompt, as on the phone.

The watch targets do not extract strings (`SWIFT_EMIT_LOC_STRINGS: NO` in `project.yml`), because extracting from the watch alone would drop the translator comments that only the phone's code supplies for shared keys. Building the watch scheme therefore leaves `Slackwater/Localizable.xcstrings` untouched, and a new watch string goes into the catalog by hand.

## Screenshotting a deep-linked screen

`xcrun simctl openurl` with a `slackwater://` link (for example `slackwater://premium`, which opens Settings at Premium) raises a system "Open in “Slackwater”?" prompt that nothing on the command line can accept. The prompt stays up and covers later screenshots.

Use a throwaway UI test instead. Subclass `ScreenshotTestCase`, launch with `testArguments(["-seedGate", "-locDenied"])` (`-seedGate` skips the first-run gate), open the link with `XCUIDevice.shared.system.open(url)`, then tap `XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]` for as long as it exists. Run only that test with `-only-testing:`, passing `TEST_RUNNER_M1_SHOT_DIR` for the screenshot, and under the test lock described in CLAUDE.md. Delete the file and run `xcodegen generate` again before committing.

## User-facing copy

Use familiar terms such as tides, currents, and places in prominent headings, buttons, and permission copy. Reserve “station” for a specific data source or an example whose meaning is clear from context; new users should not need to know how predictions are measured.

Never write “scrub” in a string the reader sees — titles, coach marks, labels, accessibility labels. It is a developer word for the gesture, not a word people know. Say “swipe to see more”, “move through time”, or name the result instead. Code identifiers and these docs keep it. Before pushing copy near the timeline, grep `Slackwater/` for `scrub` inside string literals.

Use the SF Symbol `sparkles` beside Premium labels, headings, and purchase options. Keep the icon separate from localized text; compact widgets can use “Premium” alone as the label.

## Localization

Every user-facing string ships in English, Danish (`da`), German (`de`), Spanish (`es-ES`), Finnish (`fi`), Canadian French (`fr-CA`), Italian (`it`), Japanese (`ja`), Korean (`ko`), Norwegian Bokmål (`nb`), Dutch (`nl`), Brazilian Portuguese (`pt-BR`), European Portuguese (`pt-PT`), and Swedish (`sv`). Include translations in the same pull request as any new or changed copy, including accessibility labels and system notifications. Use SwiftUI's localized string APIs or `String(localized:)`; plain Swift strings passed to system APIs are not localized automatically.

Update `Slackwater/Localizable.xcstrings` with translator context and complete translations for every supported locale. Permission prompts live in `InfoPlist.xcstrings`, shared with the watch; Siri invocation phrases live in `AppShortcuts.xcstrings`. Preserve format placeholders and Siri's `${applicationName}` token, add plural variants where the wording requires them, and remove unused keys when deleting copy. Review the catalog diff for missing translations, then build and check the changed screens in the affected languages before opening the pull request. English fallback is not a completed translation.

A phone scheme extracts strings into the catalog on every build, which is how a new key first appears. Write a hand-added entry's locales in alphabetical order, the order Xcode itself writes. An entry stored the other way round is re-sorted by the next build, and a handful of them turns an ordinary review into a thousand-line diff carrying no content change.

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

## Reporting bugs

Open an issue. For a wrong prediction, include the station, the date and time, what the app showed, and what the official source (NOAA or CHS) showed — that is usually enough to tell a data problem from an engine problem. For anything else, the device and iOS version help.

## Pull requests

Work on a branch and open a pull request.

```sh
git switch -c <area>/<short-description>    # e.g. tides/ticon-licence-gate
git push -u origin HEAD
gh pr create --fill
```

Before you open it, run `./scripts/test.sh` and say in the description what you changed and why. Small PRs get reviewed faster. Rebase or squash rather than merge-commit, and never force-push `main` — your own branches, freely.

## License and CLA

Slackwater is licensed under [GPL-3.0](LICENSE.md). All contributors must sign the [Contributor License Agreement](CLA.md) before their pull request can be merged. The CLA grants Open Water Software, LLC the rights needed to distribute your contributions (including through the iOS App Store) while you retain full copyright ownership of your work — [docs/licensing.md](docs/licensing.md) explains why a GPL app on the App Store needs this.

You will be prompted to sign the CLA automatically when you open your first pull request.

## Changing bundled station data

The JSON files in `Slackwater/Resources/` are generated artifacts, not source. Edit the generator or its upstream input, then regenerate:

```sh
cd tools && npm run build:data
```

The generators run as a chain — CHS stations, then tides, then NOAA currents, then CHS gates — and each reads the one before it, so a change anywhere means regenerating all of them and committing every changed artifact together. CI regenerates `stations.json` and `currents.json` and fails if the committed copies differ.

Because the diff is one enormous line of JSON, say in the PR description what the counts went from and to. Nothing checks what the diff _means_, so read it: dropping a tide station can silently unpair the current stations that referenced it.

A PR with a visual change must upload before and after screenshots in its
description so the reviewer can see the change without checking out the branch.
Present them side by side:

```md
| Before | After |
|---|---|
| ![Before](uploaded-image-url) | ![After](uploaded-image-url) |
```

Non-visual changes do not need screenshots.

## CI

`Required checks` in `.github/workflows/ci.yml` is the protected-branch merge gate. It requires the change filter, data generators, TestFlight intake, and app build/tests to succeed; a docs-only app skip is accepted. The branch rule does not require an up-to-date PR branch.

| Job             | Where         | What it does                                                  |
| --------------- | ------------- | ------------------------------------------------------------- |
| What changed    | GitHub-hosted | Decides whether the app lane needs to run                     |
| Data generators | GitHub-hosted | Regenerates the bundles, checks committed copies, and runs CI/release tooling checks |
| TestFlight intake | GitHub-hosted | Tests and type-checks the TestFlight feedback service (`services/testflight-feedback`) |
| Build for testing | GitHub-hosted | Builds the app and its test bundles once and uploads them |
| App tests       | GitHub-hosted | Runs `scripts/test.sh` against that upload in five shards: iPhone only for PRs; `--full` on iPhone and iPad for pushes to `main` |

The five shard names remain offline, list, transition, detail, and rest. Settings methods are spread across the first four using measured iPhone/iPad durations; rest skips only the selected tests and catches new classes and methods. `ruby scripts/test-shards.test.rb` checks that source test methods run exactly once. Each hosted runner uses one simulator worker.

New app PR commits cancel obsolete build and shard jobs. Main build and shard jobs use a separate concurrency group for each workflow run, so newer pushes cannot replace pending siblings of a full validation attempt. This preserves complete results for each SHA and can queue more main work within the five macOS slots. Docs-only changes never enter those concurrency groups. Full main validation remains exhaustive on both devices. PR validation remains exhaustive on iPhone; no extra iPad job is booked into the five macOS slots. iPad-specific failures therefore still require main validation or a targeted local check before merge.

Nightly checks out the triggering immutable commit and requires a completed successful main CI run at that exact SHA, with the build and all ten iPhone/iPad app jobs successful. A docs-only green run cannot authorize a release. Test summary artifacts are retained for every attempt, failure artifacts include raw logs and result bundles, and the shared build upload remains available for seven days.

Every lane runs on ephemeral GitHub-hosted runners — no shared machine, no lock contention with local test runs. Public-repo macOS pools can queue a few minutes at peak; annoying, not blocking.

Every generator reads local files only, so CI regenerates all of them with `npm run build:data`.

## Documentation

Keep documentation that has an ongoing reader: product contracts, architecture constraints, operating procedures, release notes, and validation evidence. Describe the current behavior and update the existing document when it changes. [docs/README.md](docs/README.md) is the index.

Put implementation plans, task checklists, session reports, and spike scratch in ignored `.superpowers/` or `/tmp`. Use issues and PRs for proposed work and review history. Before removing a completed experiment, move any lasting constraints or measurements into the appropriate living document. Code imported by a maintained pipeline belongs under `tools/`, with its reproduction instructions and checks. Generated data provenance and release records remain durable evidence.

A scrubber behavior change updates [docs/scrubber.md](docs/scrubber.md) in the same PR and reviews all four detail consumers. A list or detail behavior change updates [docs/list.md](docs/list.md) or [docs/detail.md](docs/detail.md) the same way. These three are the reference contracts other platforms build from.

## AI agents

Agents work here under the same policy as everyone else, with one addition: an agent never merges its own PR. Docs-only work gets a PR like anything else — the `What changed` job keeps it off the macOS lane, and a docs PR that books one is a bug in that job, not a reason to skip review. `CLAUDE.md` at the repo root carries the rest — the constraints that aren't discoverable from the code itself.
