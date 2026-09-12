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

**Docs-only changes don't need a PR.** If your change touches no Swift, no `project.yml`, and no generated data, push the branch and share its URL instead of opening a PR:

```sh
git push -u origin docs/<topic>
```

CI skips the app lane for those automatically, so opening one is not expensive — it's just rarely useful when there's nothing to review.

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

Three jobs, in `.github/workflows/ci.yml`, which documents its own mechanics in comments. CI is advisory today — it reports, it cannot block a merge.

| Job             | Where         | What it does                                                  |
| --------------- | ------------- | ------------------------------------------------------------- |
| What changed    | GitHub-hosted | Decides whether the app lane needs to run                     |
| Data generators | GitHub-hosted | Regenerates the bundles and checks the committed copies match |
| App tests       | GitHub-hosted | `scripts/test.sh` on the iPhone simulator                     |

Every lane runs on ephemeral GitHub-hosted runners — no shared machine, no lock contention with local test runs. Public-repo macOS pools can queue a few minutes at peak; annoying, not blocking.

`gen-chs-stations.mjs` stays out of CI because it is the only generator that needs the network; its artifact is trusted as committed.

## AI agents

Agents work here under the same policy as everyone else, with one addition: an agent never merges its own PR. Docs-only work gets a PR like anything else — the `What changed` job keeps it off the macOS lane, and a docs PR that books one is a bug in that job, not a reason to skip review. `CLAUDE.md` at the repo root carries the rest — the constraints that aren't discoverable from the code itself.
