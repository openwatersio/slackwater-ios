# Studio CI Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the CI app lane on the Mac Studio as ephemeral self-hosted runners for trusted runs, with the hosted path kept for forks, Dependabot, and the `CI_STUDIO=off` fallback.

**Architecture:** A selector job in `ci.yml` routes each run to one of two app-lane implementations: two Studio jobs (one per device, build and test in one job) or today's hosted build-plus-shards. A runner-side job-started hook enforces the same trust rule where a pull request cannot edit it. Three ephemeral runners on the Studio are kept alive by launchd and re-registered by a script; each slot owns a fixed simulator pair and cleans only its own prefix. Nightly's validator learns the Studio job names.

**Tech Stack:** GitHub Actions, actions/runner (ephemeral, repository-level), launchd, zsh and sh scripts tested the way `scripts/test-retryable.test.sh` tests them, `xcrun simctl`, Python for `scripts/nightly-validation.py`, Ruby for `scripts/test-shards.test.rb`.

**Spec:** `docs/superpowers/specs/2026-11-12-studio-ci-runner-design.md`

## Global Constraints

- Runner labels: `self-hosted`, `macOS`, `studio`. Workflow targets `[self-hosted, macOS, studio]`.
- Runner names: `studio-1`, `studio-2`, `studio-3`. Each runner's `.env` exports `SLACKWATER_CI_SLOT=<n>`.
- Slot simulators: `SlackwaterCI-<n>-iPhone` from device type `iPhone 17` and `SlackwaterCI-<n>-iPad` from `iPad Pro 11-inch (M5)`, same runtime as the hosted path.
- Studio job names: `App tests · iPhone (Studio)` and `App tests · iPad (Studio)`.
- Trusted: `push` to `refs/heads/main`, or `pull_request` whose `head.repo.full_name` equals the repository and whose actor is not `dependabot[bot]`.
- Repository variable `CI_STUDIO`: `on` routes trusted runs to the Studio; anything else routes every run to the hosted path.
- Studio path leaves `TEST_RUNNER_SLACKWATER_PERF_SCALE`, `SLACKWATER_WORKERS` and `SLACKWATER_NO_CLONE` unset.
- Cleanup touches only simulators whose name starts with `SlackwaterCI-<slot>-` and processes whose arguments name those devices.
- Runners register to `openwatersio/slackwater-ios`, never the organisation.
- No secrets in the repository. The registration-minting token lives in the login Keychain under service `slackwater-ci-runner`.
- Durable docs describe the current state only; no history in CONTRIBUTING.

## Review Focus

- A fork PR that edits `ci.yml` to target the Studio labels directly: the hook refuses it at the first step (Task 1 tests `pull_request` with a foreign `head.repo.full_name`).
- A push to a branch other than main that targets the Studio (a tag push, a mistaken `on:` edit): the hook refuses it (Task 1 tests `push` with `GITHUB_REF=refs/heads/feature`).
- A run cancelled while a clone is booting leaves a half-created clone: the cleanup deletes any `SlackwaterCI-<slot>-` device that is not one of the two fixed ones, in any state (Task 2 fixture includes a `Creating` and a `Booted` clone).
- Another slot's clone or a local developer simulator must survive a slot's cleanup (Task 2 fixture includes `SlackwaterCI-2-iPhone` and `iPhone 17` while cleaning slot 1).
- A main run with one Studio job and the hosted shards (a rerun after flipping `CI_STUDIO`) must not be released by Nightly: the validator rejects a mixed set (Task 3 test).

---

### Task 1: Runner job-started hook

**Files:**
- Create: `scripts/ci-runner/hook-job-started.sh`
- Test: `scripts/ci-runner/hook-job-started.test.sh`
- Modify: `.github/workflows/ci.yml` (the "Test runner modes" step, currently in `build`, gains `sh scripts/ci-runner/hook-job-started.test.sh`)

**Interfaces:**
- Produces: `hook-job-started.sh`, exit 0 for a trusted job and exit 1 with one line on stderr otherwise. Reads `GITHUB_EVENT_NAME`, `GITHUB_REF`, `GITHUB_REPOSITORY`, `GITHUB_ACTOR`, `GITHUB_EVENT_PATH`. Task 5 installs it as `ACTIONS_RUNNER_HOOK_JOB_STARTED`.

- [ ] **Step 1: Write the failing test**

Follow the shape of `scripts/test-retryable.test.sh`: a `check` function that writes a temporary event JSON, exports the five variables, runs the hook, and compares the exit code. Cases:

```sh
check 0 push    refs/heads/main    openwatersio/slackwater-ios clarkbw        '{}'
check 1 push    refs/heads/feature openwatersio/slackwater-ios clarkbw        '{}'
check 0 pull_request refs/pull/1/merge openwatersio/slackwater-ios clarkbw '{"pull_request":{"head":{"repo":{"full_name":"openwatersio/slackwater-ios"}}}}'
check 1 pull_request refs/pull/1/merge openwatersio/slackwater-ios someone '{"pull_request":{"head":{"repo":{"full_name":"someone/slackwater-ios"}}}}'
check 1 pull_request refs/pull/1/merge openwatersio/slackwater-ios 'dependabot[bot]' '{"pull_request":{"head":{"repo":{"full_name":"openwatersio/slackwater-ios"}}}}'
check 1 workflow_dispatch refs/heads/main openwatersio/slackwater-ios clarkbw '{}'
check 1 pull_request refs/pull/1/merge openwatersio/slackwater-ios clarkbw '{}'
```

The last case is a payload with no `pull_request` key, which must refuse rather than pass on an empty string.

- [ ] **Step 2: Run it to verify it fails**

Run: `sh scripts/ci-runner/hook-job-started.test.sh`
Expected: fails because the hook does not exist.

- [ ] **Step 3: Implement the hook**

`#!/bin/sh`, `set -eu`. Read the head repository with `jq -r '.pull_request.head.repo.full_name // empty'`. Print `refusing <event> from <actor>: not a trusted run for this runner` to stderr on refusal.

- [ ] **Step 4: Run the test**

Run: `sh scripts/ci-runner/hook-job-started.test.sh`
Expected: exits 0 silently.

- [ ] **Step 5: Add the test to the CI step and commit**

```bash
git add scripts/ci-runner/hook-job-started.sh scripts/ci-runner/hook-job-started.test.sh .github/workflows/ci.yml
git commit -m "Add the runner hook that refuses untrusted jobs"
```

### Task 2: Slot cleanup script

**Files:**
- Create: `scripts/ci-runner/cleanup-slot.sh`
- Test: `scripts/ci-runner/cleanup-slot.test.sh`
- Create: `scripts/ci-runner/fixtures/simctl-devices.json`
- Modify: `.github/workflows/ci.yml` (same "Test runner modes" step gains `zsh scripts/ci-runner/cleanup-slot.test.sh`)

**Interfaces:**
- Produces: `cleanup-slot.sh <slot>`. Shuts down and deletes every device named `SlackwaterCI-<slot>-*` except `SlackwaterCI-<slot>-iPhone` and `SlackwaterCI-<slot>-iPad`, erases those two, and kills `xcodebuild`, `Simulator`, and `xctest` processes whose arguments contain either fixed device's UDID. `SIMCTL_DEVICES_JSON=<path>` and `CLEANUP_DRY_RUN=1` make it print the commands it would run, one per line, instead of running them. Task 4 calls it from the workflow; Task 5 calls it from the re-registration script.

- [ ] **Step 1: Write the fixture**

A `simctl list devices -j` document with, under one runtime: `SlackwaterCI-1-iPhone` (Shutdown), `SlackwaterCI-1-iPad` (Shutdown), `SlackwaterCI-1-iPhone-Clone-1` (Booted), `SlackwaterCI-1-iPad-Clone-2` (Creating), `SlackwaterCI-2-iPhone` (Booted), `iPhone 17` (Booted). Give each a distinct UDID.

- [ ] **Step 2: Write the failing test**

Run the script with `CLEANUP_DRY_RUN=1 SIMCTL_DEVICES_JSON=fixture` for slot 1 and assert the output, sorted, is exactly: shutdown and delete for the two clones' UDIDs, erase for the two fixed UDIDs, and nothing naming the slot-2 or `iPhone 17` UDIDs. Then run it for slot 3 and assert empty output.

- [ ] **Step 3: Run it to verify it fails**

Run: `zsh scripts/ci-runner/cleanup-slot.test.sh`
Expected: fails because the script does not exist.

- [ ] **Step 4: Implement the script**

zsh, `set -eu`. Build the device list with `jq` from `$SIMCTL_DEVICES_JSON` or `xcrun simctl list devices -j`. Process matching uses `pgrep -f "<udid>"` on the fixed devices' UDIDs. In dry-run mode print `simctl shutdown <udid>`, `simctl delete <udid>`, `simctl erase <udid>`, `kill <pid>`.

- [ ] **Step 5: Run the test**

Run: `zsh scripts/ci-runner/cleanup-slot.test.sh`
Expected: exits 0.

- [ ] **Step 6: Add to the CI step and commit**

```bash
git add scripts/ci-runner/cleanup-slot.sh scripts/ci-runner/cleanup-slot.test.sh scripts/ci-runner/fixtures/simctl-devices.json .github/workflows/ci.yml
git commit -m "Add the slot cleanup the Studio runners use"
```

### Task 3: Nightly validator accepts the Studio job set

**Files:**
- Modify: `scripts/nightly-validation.py:50-62` (`validate_jobs`)
- Test: `scripts/nightly-validation.test.py`

**Interfaces:**
- Produces: `HOSTED_JOBS` and `STUDIO_JOBS`, module-level frozensets of job names. `validate_jobs` accepts a run whose latest-attempt successful jobs include all of one set; a run that includes any Studio job and any hosted app job is rejected. Task 4's `test-shards.test.rb` reads both sets.

- [ ] **Step 1: Write the failing tests**

Add after the existing `check` calls, using the same helper:

```python
studio = [dict(id=i, run_attempt=1, name=n, status="completed", conclusion="success")
          for i, n in enumerate(("App tests · iPhone (Studio)", "App tests · iPad (Studio)"), start=50)]
check([run], studio, True)
check([run], studio[:1], False)
check([run], studio[:1] + jobs, False)
check([run], [{**studio[1], "conclusion": "failure"}, studio[0]], False)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `python3 scripts/nightly-validation.test.py`
Expected: AssertionError on the first new `check`.

- [ ] **Step 3: Implement**

Lift the two sets to module level. In `validate_jobs`, after building `latest`, compute `passed = {name for name, job in latest.items() if job["conclusion"] == "success"}`; accept when `HOSTED_JOBS <= passed` or `STUDIO_JOBS <= passed`, and reject first if `passed & STUDIO_JOBS and passed & (HOSTED_JOBS - {"Build for testing"})`.

- [ ] **Step 4: Run the tests**

Run: `python3 scripts/nightly-validation.test.py`
Expected: exits 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/nightly-validation.py scripts/nightly-validation.test.py
git commit -m "Let Nightly release a main run validated on the Studio"
```

### Task 4: Workflow: selector, Studio jobs, hosted fallback

**Files:**
- Modify: `.github/workflows/ci.yml` (`changes` outputs, new `route` job, new `studio` job, `build` and `app` conditions, `required`)
- Modify: `scripts/test-shards.test.rb`
- Test: `ruby scripts/test-shards.test.rb` and a push of the branch

**Interfaces:**
- Consumes: Task 1's hook (installed by Task 5, not referenced in YAML), Task 2's `cleanup-slot.sh <slot>`, Task 3's job names.
- Produces: job outputs `route.outputs.studio` (`true`/`false`) and the job names in Global Constraints.

- [ ] **Step 1: Extend `test-shards.test.rb`**

Add assertions: the workflow has a job named `studio` whose `runs-on` is `[self-hosted, macOS, studio]`, whose matrix `device` values are exactly `iPhone` and `iPad`, and whose `name` expression yields the two `STUDIO_JOBS` names read from `nightly-validation.py` the way the file already reads the hosted shard list. Assert `required.needs` includes `studio`. Keep every existing assertion; the hosted matrix is unchanged.

- [ ] **Step 2: Run it to verify it fails**

Run: `ruby scripts/test-shards.test.rb`
Expected: raises on the missing `studio` job.

- [ ] **Step 3: Add the `route` job**

Ubuntu, `needs: changes`, one step that sets `studio=true` only when `needs.changes.outputs.app == 'true'`, `vars.CI_STUDIO == 'on'`, and the trust rule holds, expressed as `github.event_name == 'push' && github.ref == 'refs/heads/main'` or `github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository && github.actor != 'dependabot[bot]'`.

- [ ] **Step 4: Add the `studio` job**

`needs: [changes, route]`, `if: needs.route.outputs.studio == 'true'`, `runs-on: [self-hosted, macOS, studio]`, `timeout-minutes: 90`, `fail-fast: false`, matrix `device: ${{ fromJSON(github.event_name == 'push' && '["iPhone", "iPad"]' || '["iPhone"]') }}`, the way the hosted `app` job picks its devices. Name: `App tests · ${{ matrix.device }} (Studio)`. Concurrency group `ci-studio-${{ push ? run_id : ref }}-${{ matrix.device }}`, cancel-in-progress on pull requests, as the hosted jobs do.

Steps, in order: checkout; `zsh scripts/ci-runner/cleanup-slot.sh "$SLACKWATER_CI_SLOT"`; on iPhone only, the four runner-script tests, the fitting validator build, `node scripts/iwls-fixtures.mjs prepare`, `xcodegen generate`, `python3 scripts/localization.py`; on iPad only, `node scripts/iwls-fixtures.mjs prepare` and `xcodegen generate`; the warm-up launch from the hosted `app` job against `SlackwaterCI-${SLACKWATER_CI_SLOT}-${{ matrix.device }}`; the `tests`, `failures`, `rerun`, `Test result`, and both upload steps copied from `app` with `SLACKWATER_SIMS: SlackwaterCI-${{ env.SLACKWATER_CI_SLOT }}-${{ matrix.device }}`, no `SLACKWATER_XCTESTRUN`, no `SLACKWATER_WORKERS`, no `SLACKWATER_NO_CLONE`, no `TEST_RUNNER_SLACKWATER_PERF_SCALE`, and artifact names suffixed `-studio-${{ matrix.device }}`; finally the cleanup again under `if: always()`.

`scripts/test.sh` builds when `SLACKWATER_XCTESTRUN` is unset, so the job has no separate build step.

- [ ] **Step 5: Gate the hosted path**

`build.if` becomes `needs.changes.outputs.app == 'true' && needs.route.outputs.studio != 'true'` with `needs: [changes, route]`. `app` is unchanged; it already needs `build`.

- [ ] **Step 6: Update `required`**

Add `studio` and `route` to `needs`. In the script: when `APP_NEEDED` is true and `STUDIO` is `true`, require `needs.studio.result == success`; otherwise require `BUILD` and `APP` as today.

- [ ] **Step 7: Run the Ruby test and a lint**

Run: `ruby scripts/test-shards.test.rb && ruby scripts/nightly-workflow.test.rb`
Expected: both exit 0.

- [ ] **Step 8: Commit**

```bash
git add .github/workflows/ci.yml scripts/test-shards.test.rb
git commit -m "Route trusted CI runs to the Studio"
```

### Task 5: Runner install and re-registration

**Files:**
- Create: `scripts/ci-runner/install.sh`
- Create: `scripts/ci-runner/reregister.sh`
- Create: `scripts/ci-runner/launchd.plist.template`
- Create: `scripts/ci-runner/README.md`
- Test: `scripts/ci-runner/install.test.sh`

**Interfaces:**
- Consumes: Task 1's hook, Task 2's cleanup.
- Produces: three registered ephemeral runners on the Studio and the `CI_STUDIO` variable.

- [ ] **Step 1: Write the failing test for `reregister.sh`**

With `RUNNER_DRY_RUN=1`, `SLOT=2`, and `RUNNER_TOKEN_CMD='echo tok'`, assert the printed command sequence is: `cleanup-slot.sh 2`, `./config.sh --unattended --ephemeral --replace --url https://github.com/openwatersio/slackwater-ios --token tok --name studio-2 --labels studio --work _work`, then `./run.sh`. Assert the script refuses to run when `SLOT` is unset.

- [ ] **Step 2: Run it to verify it fails**

Run: `sh scripts/ci-runner/install.test.sh`
Expected: fails on the missing script.

- [ ] **Step 3: Implement `reregister.sh`**

sh, `set -eu`. Runs from `~/actions-runner/studio-<slot>/`. Mints the registration token with `gh api -X POST repos/openwatersio/slackwater-ios/actions/runners/registration-token --jq .token` using `GH_TOKEN` read from the Keychain with `security find-generic-password -s slackwater-ci-runner -w`, unless `RUNNER_TOKEN_CMD` overrides it. Writes `.env` with `SLACKWATER_CI_SLOT=<slot>` and `ACTIONS_RUNNER_HOOK_JOB_STARTED=<runner dir>/hook-job-started.sh`. Copies the hook and cleanup scripts from the checkout named by `SLACKWATER_CI_SCRIPTS` into the runner directory. Exec's `./run.sh`.

- [ ] **Step 4: Write the plist template**

Label `io.openwaters.slackwater.ci-runner.SLOT`, `ProgramArguments` running `reregister.sh` with `SLOT`, `KeepAlive` true, `RunAtLoad` true, `WorkingDirectory` the runner dir, stdout and stderr to `~/Library/Logs/slackwater-ci-runner-SLOT.log`, `EnvironmentVariables` carrying `PATH` with Xcode's `/usr/bin`, Homebrew, and `~/.local/share/mise/shims`.

- [ ] **Step 5: Implement `install.sh`**

Arguments: none. For slots 1 to 3: download the current actions/runner release into `~/actions-runner/studio-<n>/` if absent, create `SlackwaterCI-<n>-iPhone` and `SlackwaterCI-<n>-iPad` with `xcrun simctl create` if absent, render the plist into `~/Library/LaunchAgents/`, and `launchctl bootstrap gui/$(id -u)` it. Before the loop: `launchctl bootout` and delete `actions.runner.openwatersio.studio`, run `./config.sh remove` in `~/actions-runner/slackwater-ios` with a token from the same minting path, delete every simulator named `SlackwaterCI-iPhone`, `SlackwaterCI-iPad`, or their clones, and print the `gh api` call that deletes the `slackwater-nightly` runner group for the operator to run with an org-admin token. Idempotent: a second run changes nothing.

- [ ] **Step 6: Write the README**

How to create the fine-grained token (repository: `openwatersio/slackwater-ios`, permission: Administration read and write), store it (`security add-generic-password -s slackwater-ci-runner -a runner -w`), run `install.sh`, set `CI_STUDIO` to `on` in repository variables, and what `launchctl list | grep slackwater` and `gh api repos/openwatersio/slackwater-ios/actions/runners` should show. How to take the Studio away: flip `CI_STUDIO` to `off`.

- [ ] **Step 7: Run the test and commit**

Run: `sh scripts/ci-runner/install.test.sh`
Expected: exits 0.

```bash
git add scripts/ci-runner/
git commit -m "Install three ephemeral CI runners on the Studio"
```

### Task 6: Install on the Studio and prove the path

**Files:**
- None in the repository until Step 5.

- [ ] **Step 1: Store the token and install**

Run `security add-generic-password -s slackwater-ci-runner -a runner -w` with a fine-grained token scoped to this repository, then `SLACKWATER_CI_SCRIPTS=$PWD sh scripts/ci-runner/install.sh`.

- [ ] **Step 2: Verify the runners**

Run: `gh api repos/openwatersio/slackwater-ios/actions/runners --jq '.runners[] | [.name, .status, (.labels[].name)] | @tsv'`
Expected: `studio-1`, `studio-2`, `studio-3`, each `online`, each with `self-hosted`, `macOS`, `studio`. `gh api orgs/openwatersio/actions/runners` no longer lists `studio`.

- [ ] **Step 3: Set the variable and push the branch**

`gh variable set CI_STUDIO --body on`, push the branch, open a pull request. Expected: the run shows `App tests · iPhone (Studio)` and no `Build for testing`; the job's first step is the cleanup; it finishes green in under 20 minutes.

- [ ] **Step 4: Prove the refusals and the fallback**

From a fork or a throwaway account, open a pull request whose `ci.yml` puts the Studio labels on a job. Expected: the job fails at its first step with the hook's `refusing` line. Set `CI_STUDIO` to `off`, re-run the branch's pull request. Expected: `Build for testing` and the six shards run on hosted runners and the required check passes. Set it back to `on`.

- [ ] **Step 5: Prove cleanup after a cancel**

Cancel a Studio run during its tests. Expected: within a minute `xcrun simctl list devices | grep SlackwaterCI-` shows exactly six devices, all `Shutdown`, and `launchctl list | grep slackwater` shows the slot's job alive with a new PID.

- [ ] **Step 6: Merge and watch main**

After merge, the push run shows both Studio jobs green and Nightly's next run selects that commit (`Selected <sha> from full main CI run` in its log).

### Task 7: Documentation

**Files:**
- Modify: `CONTRIBUTING.md:215-258` (the "CI" section and "Reading a CI failure")
- Modify: `scripts/test.sh:80-85` (the comment that says CI sets 4)
- Modify: `docs/testflight.md:3` (the sentence on where `--full` runs)

- [ ] **Step 1: Rewrite the CI section**

Describe the current state: the two paths, the trust rule, `CI_STUDIO`, the three slots and their simulators, the job names, where failures and artifacts land, and the line "Every lane runs on ephemeral GitHub-hosted runners" replaced by the Studio topology with the hosted path as fallback. Replace the shard-table guidance under "Reading a CI failure" with the Studio job and the hosted shards as the fallback case. Point at `scripts/ci-runner/README.md` for the install.

- [ ] **Step 2: Fix the two comments**

`scripts/test.sh`: "CI sets 4 for its hosted runners and leaves the default on the Studio". `docs/testflight.md`: "CI runs `--full` on both simulators for every push to `main`, on the Studio or on hosted runners".

- [ ] **Step 3: Commit**

```bash
git add CONTRIBUTING.md scripts/test.sh docs/testflight.md
git commit -m "Describe the Studio CI topology"
```
