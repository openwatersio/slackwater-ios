# Task 3 report: offline runner modes

## Result

`scripts/test.sh` now provides four explicit modes from the existing XCTest plan:

- default: offline unit and UI targets on iPhone, excluding live smoke and the exhaustive national sweep
- `--full`: offline unit and UI targets on iPhone and iPad, including the exhaustive sweep
- `--unit`: unit target only on exactly one simulator, including the exhaustive sweep
- `--live`: `LiveFetchTests` only on exactly one simulator with `TEST_RUNNER_SLACKWATER_LIVE=1`

Unit-containing modes run the offline `node scripts/iwls-fixtures.mjs prepare` before XcodeGen. Live mode is independent of fixtures. Every invocation clears inherited live and retired full opt-ins; invalid/multiple flags and invalid simulator overrides fail before the lock or tools run. The existing machine lock, result bundles, screenshot route, worker control, and repository-local package cache remain.

Current contributor, CI, release, PR, and TestFlight guidance now documents the explicit capture, cached reuse, missing-fixture failure, and separated offline/live modes. Historical plans were left unchanged.

## Verification

- `rtk test zsh -n scripts/test.sh scripts/test-modes.test.sh`
- `rtk test ./scripts/test-modes.test.sh`
- `rtk git diff --check`

The stubbed test covers target/device selection for every mode, fixture preparation order and failure, inherited environment clearing, invalid/conflicting arguments, one-device enforcement, and the lock probe/re-exec path. No Xcode build or simulator test was run; coordinator validation remains pending.
