# Offline test fixtures implementation plan

> For agentic workers: use subagent-driven-development. The user approved the design in the preceding testing review and requested Sol subagents.

**Goal:** Routine unit and UI tests run without downloading CHS data or racing live downloads.

**Architecture:** Capture a small versioned local IWLS recording explicitly, then reuse it for deterministic tests through the production decoder and JSCore fitter. UI checks use seeded state and controlled transitions. Keep real IWLS compatibility checks explicitly opt-in and on one simulator.

**Tech stack:** Existing Swift/XCTest, JavaScriptCore, Node built-ins, zsh/XcodeGen.

**Spec:** User-approved testing review in this thread: fixed recordings, offline default, controlled pending/provisional/final UI states, separate live smoke, unit-only runner.

## Global constraints

- No new dependencies, no downloaded CHS samples committed to Git, and no network fallback during routine tests.
- Keep immutable fixture files outside mutable model/chunk stores; missing/corrupt recordings fail clearly with the explicit setup command.
- Preserve coverage of real fitting, decoding/projection, persistence/relaunch, provisional-to-final transitions, promotion/resume, and online-gate rendering.
- Pin recording time bounds and test clocks; never regenerate expected results from the implementation under test at assertion time.
- Test hooks must not alter Release behavior. Prefer existing hooks and small concrete seams over protocols/frameworks.
- All shell commands use rtk. Every Xcode build/test respects /tmp/slackwater-test.lock and uses a worktree-local package cache. Coordinator runs simulator tests; workers do not launch competing builds.
- No merge or publish. Do not modify other worktrees. Sol for all requested workers.

## Task 1: Recorded IWLS inputs and real fitter checks

**Files:** scripts/iwls-fixtures.mjs, scripts/iwls-fixtures.test.mjs, SlackwaterTests/IwlsFixtureTests.swift, Slackwater/IwlsClient.swift if a concrete injection seam is necessary, .gitignore.

**Interface:** `node scripts/iwls-fixtures.mjs refresh` explicitly downloads a recording; `node scripts/iwls-fixtures.mjs prepare` validates and stages it at `SlackwaterTests/Fixtures/iwls-recording.json` without network. `SLACKWATER_FIXTURE_DIR` overrides the persistent directory; default to `.test-fixtures/iwls` beside the shared Git common directory so linked worktrees and the self-hosted checkout reuse it. Recording file carries schema, capture/bounds/station metadata, and raw response samples. XcodeGen includes the staged JSON through the existing test source directory. Missing recording is an actionable failure, never a skip.

- [ ] Write the fixture tooling regression first: preparation never fetches, refuses missing/corrupt input, atomic refresh preserves the previous recording on failure.
- [ ] Implement minimal recorder with bounded requests/timeouts, polite live pacing, fixed explicit bounds (default pinned date), Victoria tide, Active Pass current, Dodd full/provisional current, and Sechelt online samples/metadata. Resolve against the actual catalog. Validate expected series coverage and finite sample values before publishing. Avoid a general-purpose recorder framework.
- [ ] Add XCTest coverage using staged samples through production parsing/projection and actual ChsFitter. Assert meaningful outputs against fixed tolerances/baselines and fit sample counts. Include offline transport/error coverage using small synthetic HTTP responses where appropriate. Isolate mutable cache so stale simulator data cannot mask decoding failures.
- [ ] Run tooling checks. Report exact changed paths, interface/schema and assertions to coordinator for simulator verification.

## Task 2: Offline UI states and migration

**Files:** Slackwater/TestSeeds.swift, Slackwater/ChsFitService.swift, Slackwater/Palette.swift, SlackwaterUITests/*.swift and minimal DEBUG-only supporting hook if needed.

**Interface:** Standard UI launches use a fixed clock and disable network consistently, including direct launches/relaunches. Only LiveFetchTests explicitly opts into real networking. After migration LiveFetchTests contains a small network-compatibility smoke subset, and behavior coverage runs in ordinary fixture UI classes. New app hooks remain DEBUG-only.

- [ ] Add or adapt deterministic checks first for final model persistence and provisional-to-final replacement.
- [ ] Reuse seeds for final tide/current models and online windows; explicitly hold and release asynchronous state transitions so UI assertions cannot miss a transient state. Preserve real queue selection/yield behavior rather than replace it with a fake queue algorithm. Keep fit computation coverage in Task 1.
- [ ] Migrate existing live behavior assertions to offline tests: tide/current offline relaunch, derived gate, downloads manager, provisional final rendering, queue promotion/resume, on-demand station, and online-gate rendering.
- [ ] Normalize direct and helper launch arguments, maintain intentional offline/failed-state assertions, remove obsolete sleeps/time ceilings where replaced by controlled state.
- [ ] Report coverage mapping and simulator test selections to coordinator.

## Task 3: Runner modes and documentation

**Files:** scripts/test.sh, scripts/test-modes.test.sh (or existing tooling test convention), TestPlans/Slackwater.xctestplan if needed, project.yml comments, CONTRIBUTING.md, docs/testflight.md, .github/workflows/ci.yml comments.

**Interface:** default fast = offline iPhone; `--full` = offline iPhone+iPad plus exhaustive data test; `--unit` = unit target only on one device; `--live` = live smoke UI target only on one device and TEST_RUNNER_SLACKWATER_LIVE=1. Clear inherited live opt-in for all other modes. Reject unknown/conflicting flags. Preserve lock and simulator overrides with one-device validation for live/unit.

- [ ] Write stubbed runner checks for mode selection, unknown flags, inherited live env, and missing fixtures before simulator work.
- [ ] Implement local fixture prepare before xcodegen for unit-containing modes. Never refresh implicitly. Keep live smoke independent of the fixture pack and prevent unrelated tests from running in live mode.
- [ ] Document one-time fixture refresh, reuse across runs/worktrees, explicit refresh semantics, test modes, and that fixture absence is setup failure.
- [ ] Run stubbed runner checks and hand commands to coordinator.

## Integration validation

- [ ] Coordinator records fixtures explicitly, compiles under the global lock, runs unit target and all new/changed offline UI behaviors; then runs required fast suite before PR creation.
- [ ] Independent Sol review of each task and whole branch; fix important findings and verify changed checks.
- [ ] Summarize observed timings separately from expected savings, plus any unresolved validation limitations.
