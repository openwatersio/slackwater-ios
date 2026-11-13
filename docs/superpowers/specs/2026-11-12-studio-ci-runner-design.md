# App tests run on the Studio again

Design for moving the CI app lane from GitHub-hosted macOS runners back to the Mac Studio, as ephemeral self-hosted runners, while fork pull requests and the Nightly release stay on hosted runners. It replaces the per-device shard matrix in `.github/workflows/ci.yml` with one job per device that runs the suite with parallel simulator workers, and it answers each of the reasons the lane left the Studio in September 2026 (PR #250).

## Intent

A pull request's checks should finish in the time it takes to read the diff, and a push to main should give Nightly a trusted full run within the hour. Neither is true today. The free org has five hosted macOS slots. A pull request books seven of them (one build, six iPhone shards) and a push to main books thirteen. With two or three pull requests open, the runs queue behind each other and behind main, and the pool itself runs dry at peak. On 12 November pull request runs took 89 to 138 minutes of wall clock, pushes to main took 149 to 214 minutes, one push on 10 November took 1,125 minutes, and a pull request sat queued for over two hours before its first job started. The tests themselves account for a small share of that. The rest is waiting for a slot, cold simulator services, and runners slow enough to trip XCUITest's 60-second idle waits.

The Studio runs the same full suite, both devices, in about 65 minutes end to end, and the fast suite in about 17, with no queue (CONTRIBUTING.md, "Local test runs"). It is an M1 Ultra with 20 cores and 128 GB. It already served as the CI runner from August to September, and the lane left for reasons that are now understood and each have a fix below. The test suite is not being trimmed as part of this. Making the tests cheap to run is what makes trimming them measurable, and that is a separate project.

## Goals

- A pull request from a repository branch runs its app lane on the Studio, and its checks finish without waiting for a hosted slot.
- A push to main runs the full two-device suite on the Studio, and Nightly keeps trusting that run exactly as it does now.
- Several CI runs proceed on the Studio at once, alongside local test runs and Android builds, without any of them killing another.
- A runner that finishes, crashes, or is cancelled leaves nothing behind: no runner process, no booted simulator, no simulator clone.
- A pull request from a fork never runs on the Studio.
- When the Studio is off or away, CI still works, on hosted runners, by flipping one switch and without editing the workflow.
- The shard tables in `ci.yml` go away. Lane balance becomes the test runner's parallelism instead of a hand-tuned list of test selectors.

## Non-goals

- No trimming of the test suite. That is the follow-on, measured against the new run times.
- No change to the Nightly or Promote workflow files. Release stays on hosted runners and keeps the Open Waters team's signing material off the Studio, as issue #221 set out. The validator Nightly runs, `scripts/nightly-validation.py`, is in scope: it names the jobs a trusted main run must contain, and it has to learn the Studio path's job names or Nightly will select nothing (see "Nightly's validator" below).
- No paid runner tier, no Xcode Cloud, no third-party macOS CI.
- No change to the Ubuntu lanes (what changed, data generators, TestFlight intake, lockfiles, required checks). They are free and fast.
- No change to `scripts/test.sh`'s modes, lock, or worker sizing beyond what the runner environment needs.
- No virtual machines on the Studio. Apple's Virtualization framework allows two guests per host, which is less parallelism than bare runners give, and the isolation it buys is not needed once fork code never reaches the machine. If bare runners turn out to interfere with each other in a way the rules below do not cover, VMs are the next thing to try, not the first.

## Anti-goals

- A shared lock that serialises CI behind local runs, or local runs behind CI. The lock in `scripts/test.sh` is per worktree and stays that way. CI runs are separate worktrees with separate DerivedData and separate simulators, and overlapped runs on separate devices do not disturb each other (measured 2026-10-01, `scripts/test.sh` header).
- A runner that needs babysitting. If anyone has to ssh in to delete a simulator or restart a process after a bad run, the design has failed.
- Any workflow path where untrusted code executes on the Studio, including through a label a maintainer could apply by mistake.
- Results that are harder to read than today's. Failure messages, the bounded rerun of service timeouts, the step summary, and the uploaded screenshots and `.xcresult` bundles all stay.

## Constraints

- The repository is public and takes fork pull requests under a CLA. GitHub does not send secrets to fork pull request runs, but a self-hosted runner executes the fork's checked-out code, which is enough to compromise the host.
- The Studio is a development machine. It builds and tests slackwater-ios and slackwater-android locally, runs Claude sessions in several worktrees at once, and is sometimes asleep, away, or on a hotel network.
- The old runner is still registered on the machine: a launchd job named `actions.runner.openwatersio.studio` with its work directory under `~/actions-runner/slackwater-ios`, currently not running, and seven simulators from the old `SlackwaterCI-*` scheme still defined. The builder removes both before installing the new runners.
- `scripts/test.sh` sizes parallel workers from RAM, between two and four, unless `SLACKWATER_WORKERS` overrides it. Each booted simulator clone costs roughly 2.2 GB.
- Hosted runners had their performance budgets widened four times through `TEST_RUNNER_SLACKWATER_PERF_SCALE`. The budgets were calibrated on the Studio with nothing else running, and `scripts/test.sh` defaults to scale two there to absorb overlapped runs.
- The hosted path must keep working as it does today, both for forks and as the fallback, so its build-then-shards shape stays in the workflow.

## Design

### Two paths through the same workflow

The app lane has two implementations and a single selector.

The Studio path runs when the Studio is enabled and the run is trusted. One job per device builds for testing and runs the tests in the same job, on the same machine, with no artifact round trip. A pull request runs the fast suite on the iPhone. A push to main runs the full suite on the iPhone and the iPad as two jobs, so each device's results are its own check and the two run on two runners at once.

The hosted path is today's `build` job plus the `app` shard matrix, unchanged in shape. It runs when the Studio is disabled or the run is untrusted.

The selector is a job that sets two outputs: `trusted` and `studio`. Trusted means the event is a push to main or a pull request whose head repository is this repository and whose actor is not `dependabot[bot]`. Only people with push access can create a branch here, which is the set of people whose code may run on the Studio, and the set changes without editing the workflow. Dependabot's branches are in this repository too, but nobody pushed their contents, and a bumped npm package under `tools/` or a bumped action is exactly the kind of code that should meet the hosted path first. Those pull requests are weekly and small. Studio means a repository variable `CI_STUDIO` is `on`. Flipping it to `off` in the repository settings moves every run to the hosted path within the next run. There is no per-pull-request label and no `workflow_dispatch` input that routes a run to the Studio.

The `required` job accepts whichever path ran, the same way it accepts the docs-only skip today.

### Fork code never reaches the runner

The selector is not the guard. A pull request runs the workflow file from its own head, so a fork can delete the selector and put the Studio's labels on any job, and a maintainer who approves that fork's run to see its hosted results has just sent it to the Studio. Two things stand in front of that, and neither lives in the workflow.

The runners are registered to this repository, not the organisation. A repository-level runner only ever receives this repository's jobs, so no other repository's workflow can name its labels. The old registration was organisation-level, in a runner group called `slackwater-nightly` that still exists and admits public repositories. The install removes that registration and that group.

Each runner has a job-started hook, set through `ACTIONS_RUNNER_HOOK_JOB_STARTED` in the runner's `.env`, that reads the event payload from `GITHUB_EVENT_PATH` and fails the job before any step runs unless the event is a push to main or a pull request whose head repository is this repository and whose actor is not Dependabot. The hook is the same rule as the selector, enforced where the pull request cannot edit it. The hook script lives in the repository under `scripts/` with a test alongside the other runner-script tests, and the install copies it into each runner's directory. A job the hook refuses shows up in the run as failed at its first step with the hook's message, so the refusal is visible rather than silent.

### Nightly's validator

`scripts/nightly-validation.py` selects the commit to release by checking that main's latest CI run completed a fixed set of jobs: "Build for testing" and the twelve "App tests" shard jobs. The Studio path produces two jobs with other names, so the validator learns both shapes: the hosted set as today, or the two Studio device jobs. It accepts a run that satisfies either in full and never a mixture. The test that runs from the `data` job covers both. Nightly's workflow file, its schedule, and its owner gate do not change.

### Ephemeral runners

The Studio registers three runners with this repository, each its own directory under `~/actions-runner/` and its own launchd job. Each is configured with `--ephemeral`, so it takes exactly one job, deregisters itself, and exits. Its launchd job has `KeepAlive` and restarts it, and the restart re-registers with a fresh registration token before listening again. A registration token is short-lived and is minted from a fine-grained personal access token with administration access to this one repository, or a GitHub App installed on it, stored in the login Keychain and never in the repository or the runner directory. This is what makes a stale runner impossible: a runner process only ever lives as long as its one job, and the thing that outlives a job is the launchd job, which holds nothing.

Three is the number of runs the Studio holds at once. The full suite's two device jobs and one pull request fit together. Each run's workers are left to `scripts/test.sh`'s own sizing, which caps at four, so the worst case is twelve booted clones, about 26 GB, with the rest of the machine free for local work. A fourth run waits in GitHub's queue, which is fine. The number is a launchd plist count and can change without touching the workflow.

Runners carry the labels `self-hosted`, `macOS`, `studio`, and the workflow targets `[self-hosted, macOS, studio]`.

### Simulators and cleanup

Each runner slot owns a fixed pair of simulators named for the slot, `SlackwaterCI-1-iPhone` and `SlackwaterCI-1-iPad` and so on, created once at install time from the same device types and runtime the hosted path names. The workflow passes the slot's devices through `SLACKWATER_SIMS`, and `scripts/test.sh` clones them for its workers as it does locally. Local runs never name a `SlackwaterCI-*` device, so CI and local never share a simulator.

Every Studio job starts with a cleanup step and ends with the same step under `if: always()`. It shuts down and deletes every simulator whose name starts with that slot's prefix except the two fixed devices, erases the two fixed devices, and kills any `xcodebuild`, `Simulator`, or test runner process whose arguments name that slot's devices. It touches nothing without the slot prefix. The same cleanup runs from the launchd job before each runner re-registers, so a job that was cancelled mid-boot or a runner that was killed by a reboot is cleaned by the next start, not by a person.

The first-time warm-up that the hosted path performs, installing the app, launching it for 45 seconds and uninstalling it, exists because a fresh hosted simulator has no permission state. The Studio's fixed devices are erased before each run, so the same warm-up runs there too. It is cheap and keeps the two paths honest.

### Environment on the Studio path

- `TEST_RUNNER_SLACKWATER_PERF_SCALE` is unset. `scripts/test.sh` then applies its own default of 2, which it chose for overlapped runs on this machine, and three CI runs beside local work is that case. The hosted path's 4 goes with the hosted runners. The budgets were measured at scale 1 with the machine otherwise idle, so the Studio path does not measure them; it measures raw per-test durations from the `*.summary.json` artifacts, which do not depend on the scale.
- `SLACKWATER_WORKERS` is unset, so the script sizes itself.
- `SLACKWATER_NO_CLONE` is unset, so the workers clone the slot's devices.
- The fast mode runs for pull requests and `--full` for pushes to main, as today.
- `xcodegen` and the Node version from `mise.toml` come from the machine. The job does not install tools.
- Build products go to the worktree's own `build/` as locally, and the run takes the worktree's `build/xcodebuild.lock` as locally. Each runner slot checks out into its own directory, so the lock never crosses slots.
- The checks that ride on the hosted `build` job today, the runner-script tests, the fitting validator build, the IWLS fixture staging, and the localization completeness check, run in the iPhone job on the Studio path, before its build. The iPhone job runs on every trusted event, so each of them still gates every pull request and every push. The iPad job skips them rather than running them a second time.

### What stays

The `changes` job and its docs-only skip. The Ubuntu jobs. The failure messages step, the retryable classification, the one bounded rerun of service timeouts, the step summary, and the uploads of test summaries, screenshots and `.xcresult` bundles on failure. `scripts/test-shards.test.rb` either goes with the shard tables or is retargeted at the hosted matrix; the builder decides, and it must not be left checking tables the Studio path does not use.

### When the Studio is away

Runs queue in GitHub until a runner comes back. That is the right behaviour for an evening or a sleep, and the wrong one for a trip. The remedy is the `CI_STUDIO` variable, flipped to `off` from any browser, which routes the next run to the hosted path. Nothing waits on a timeout to fail over, because a timeout that fails over hides a runner that silently died. A queued job is visible in the run list and says what it is waiting for.

## Measured expectations

These are what the design is checked against after the first week, not promises. Pull request fast suite on the Studio: under 20 minutes from push to green, against 89 to 138 minutes on 12 November. Push to main full suite: both device jobs green within about 65 minutes, against 149 to 214. Idle-timeout warnings from `scripts/test.sh` in Studio logs: none. Simulators on the Studio outside the six fixed CI devices after any CI run finishes: none with a `SlackwaterCI-` prefix. A fork pull request edited to target the Studio's labels: refused by the hook at its first step.

## Left to the builder

- The launchd plist, the re-registration script, the job-started hook, and where the minting token lives in the Keychain. The scripts are in the repository under `scripts/` so the install is reproducible on another Mac, with the token supplied from outside.
- How the selector job expresses trust and the variable, and how the two paths and `required` are wired in YAML so that a skipped path satisfies the gate.
- How `scripts/nightly-validation.py` expresses the two accepted job sets.
- Whether the Studio path's build step keeps the SPM cache keyed on `project.yml` or relies on the machine's own package cache.
- The exact cleanup commands and the process-matching rule, tested against a cancelled run and a reboot.
- Whether `scripts/test-shards.test.rb` survives, and in what form.
- The CONTRIBUTING.md sections on CI topology, which describe the current state only once this lands: "Every lane runs on ephemeral GitHub-hosted runners" becomes untrue.
- Removing the old organisation-level runner registration, its `slackwater-nightly` runner group, and the seven old simulators as part of the install, and confirming nothing else on the machine still points at `~/actions-runner/slackwater-ios`.

## Later

Trimming the suite, once a week of Studio runs has given per-test durations from the summary artifacts. The candidates are the fourteen `testSettingsIn<Language>` layout tests and the printable-table tests, which exist as per-locale screenshots more than as behaviour checks. That decision is made with the timings in hand, not before.

A second device in the matrix, or a duo suite, costs one more Studio job per push, not five more hosted slots.
