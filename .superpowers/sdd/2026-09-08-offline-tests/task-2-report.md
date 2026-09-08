# Task 2 report

Implemented deterministic UI state coverage without replacing the production CHS queue or fitter.

## Hook interface

- Ordinary `ScreenshotTestCase` launches add `-networkKillSwitch`, `-chartPacksOff`, `-currentFillOff`, `-noCloudSync`, and fixed `-nowEpoch 1788868800`.
- A launch containing `-chsFixture <UUID>` omits the kill switch and `IwlsFetcher` serves generated harmonic station, metadata, and sample responses. Every fetch method is intercepted; fixture mode has no live fallback.
- `-chsFixtureScenario provisional-final` pauses immediately after production `publishProvisional`; the UI runner releases the uniquely named Darwin notification `org.openwaters.slackwater.ui.<UUID>.after-provisional`.
- `-chsFixtureScenario yield-resume` pauses Dodd and Tofino at their first production chunk boundaries. Releases are `dodd-first-chunk` and `tofino-first-chunk`. Production `queue.shouldYield`, catch/requeue, claim, and resume paths run unchanged.
- `-chsFixtureScenario hold-first` holds a real claimed job for stable manager assertions.
- `-seedCurrentModel <id>` stores a synthetic current model before service init. `-seedCurrentProvisional` selects 60 days; service init uses its real `isProvisional` classification.
- Fixture checkpoints use cross-process Darwin notifications, are bounded to 60 seconds, and are scoped by a fresh UUID, preventing stale or cross-test releases.

## Coverage mapping

- Victoria pending → fit → offline next-day persistence: `OfflineTransitionTests.testTideFitPersistsOffline`.
- Active Pass direct-to-final with no provisional UI: `testValidatedGateGoesStraightToFinal`.
- Dodd list/detail provisional and in-place final replacement: `testProvisionalGateRefinesInOpenDetail`.
- Dodd yield to promoted Tofino and resume: `testPromotionYieldsAndThenResumesDownload`.
- Manager geometry/order/exclusion/promotion: `testDownloadsManagerOrdersAndPromotesRealQueue`.
- Halifax on-demand add/promote/open-detail fill: `testOnDemandStationFillsOpenDetail`.
- Final current seed rendering: `testSeededFinalCurrentModelRendersOffline`; next-day persistence of a production-fitted Dodd final is proved by the relaunch leg of `testProvisionalGateRefinesInOpenDetail`.
- Provisional manager wording/tolerance: `testSeededProvisionalModelAppearsInManager`.
- Malibu derived gate and online-window behavior remain in existing seeded `OfflineCoverageTests` cases.
- `LiveFetchTests` now contains only Victoria tide, Active Pass current, and Sechelt online compatibility smoke checks gated by `SLACKWATER_LIVE`.

All direct launch/relaunch sites now use the common argument composer. Graphical picker calculations use the fixed fixture date rather than the UI runner's wall clock. Unit-hosted app code disables incidental IWLS when XCTest is loaded.

## Validation

- `git diff --check` passed.
- No Xcode build or simulator test was run, per task instructions. Coordinator should select `OfflineTransitionTests`, changed `OfflineCoverageTests` picker cases, and the existing direct-launch classes before the full offline suite.
- The notification handshake was not separately probed; the coordinator's focused transition UI run is the cross-process validation.
