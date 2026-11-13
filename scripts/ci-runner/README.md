# Studio CI runners

The Mac Studio runs the CI app lane as three ephemeral self-hosted runners, slots 1 to 3. Each slot has its own runner directory, `~/actions-runner/studio-<slot>/`, its own two simulators, `SlackwaterCI-<slot>-iPhone` and `SlackwaterCI-<slot>-iPad`, and its own launchd job, `io.openwaters.slackwater.ci-runner.<slot>`. A runner takes one job and exits. launchd starts `reregister.sh` again, which cleans the slot's simulators, registers a fresh runner with a new token, and waits for the next job. The design is in `docs/superpowers/specs/2026-11-12-studio-ci-runner-design.md`.

| File | What it does |
| --- | --- |
| `install.sh` | Sets up the three slots and retires the old organisation runner. |
| `reregister.sh` | What each launchd job runs: clean, register, run one job. |
| `launchd.plist.template` | The launchd job, rendered once per slot. |
| `hook-job-started.sh` | Refuses any job that is not a push to main or a same-repository pull request. |
| `cleanup-slot.sh` | Deletes the slot's simulator clones and erases its two devices. |

`install.sh` copies `reregister.sh`, the hook and the cleanup script into each runner directory, and those copies are what run. Between jobs there is no checkout to run them from.

## Install

1. Create a fine-grained personal access token at github.com, Settings, Developer settings, Fine-grained tokens. Resource owner `openwatersio`, repository access only `openwatersio/slackwater-ios`, repository permission Administration: Read and write. Nothing else. It mints the short-lived runner registration tokens and nothing more.

2. Store it in the login Keychain. The command prompts for the token, so it never lands in shell history:

   ```sh
   security add-generic-password -s slackwater-ci-runner -a runner -w
   ```

   To replace it later, add `-U`.

3. From a checkout of this repository, preview the install, then run it:

   ```sh
   RUNNER_DRY_RUN=1 sh scripts/ci-runner/install.sh
   sh scripts/ci-runner/install.sh
   ```

   It needs `gh`, `jq`, `curl` and Xcode's `xcrun` on PATH, and the iOS 27.0 runtime installed. For each slot it downloads the current `actions/runner` release for `osx-arm64` if the directory has none, copies the scripts, creates the two simulators if they are missing, writes the launchd plist into `~/Library/LaunchAgents/`, and loads it.

   Before that it retires the old runner: it unloads and deletes the `actions.runner.openwatersio.studio` agent and deletes the old `SlackwaterCI-iPhone` and `SlackwaterCI-iPad` simulators and their clones. The old runner was registered with the organisation, and its removal token can only be minted with an organisation admin token, so `install.sh` prints two commands, marked `operator:`, for you to run with one: the `config.sh remove` for `~/actions-runner/slackwater-ios`, and the `gh api` call that deletes the `slackwater-nightly` runner group. It keeps printing them while the old runner's `.runner` file is still there.

4. Turn the Studio path on. In the repository's Settings, Secrets and variables, Actions, Variables, set `CI_STUDIO` to `on`, or:

   ```sh
   gh variable set CI_STUDIO --body on --repo openwatersio/slackwater-ios
   ```

### Running it again

Every step checks before it acts, so a second run changes nothing that is in place. It does not download a runner into a directory that has one, recreate a simulator that exists, or reload a job that is loaded with the current plist. It does recopy the scripts when the checkout's copies differ, so run it after changing any of them. A plist that differs from the template is rewritten and its job reloaded, which stops that slot's runner, mid-job if it has one. In dry-run mode nothing is changed, so two dry runs print the same commands.

## Check it

`launchctl list | grep slackwater` shows the three jobs. The first column is the process ID while `reregister.sh` or the runner is up; the second is the last exit status, which should be 0:

```
41211	0	io.openwaters.slackwater.ci-runner.1
41215	0	io.openwaters.slackwater.ci-runner.2
41219	0	io.openwaters.slackwater.ci-runner.3
```

GitHub sees three runners, `studio-1` to `studio-3`, online and ephemeral, with labels `self-hosted`, `macOS`, `studio`:

```sh
gh api repos/openwatersio/slackwater-ios/actions/runners \
  --jq '.runners[] | [.name, .status, .busy, .ephemeral, ([.labels[].name] | join(","))] | @tsv'
```

```
studio-1	online	false	true	self-hosted,macOS,studio
studio-2	online	true	true	self-hosted,macOS,studio
studio-3	online	false	true	self-hosted,macOS,studio
```

A busy runner is running a job. When it finishes, it disappears from the list for a few seconds and comes back under the same name.

Each slot logs to `~/Library/Logs/slackwater-ci-runner-<slot>.log`. A job that stays missing from that list usually means `reregister.sh` is failing and launchd is restarting it every few seconds: the log says why, often a Keychain item that is missing or a token that has expired.

## Take the Studio away

Set `CI_STUDIO` to `off`, from any browser or with `gh variable set CI_STUDIO --body off --repo openwatersio/slackwater-ios`. The next run goes to the hosted runners. Runs that already queued for the Studio keep waiting for it. To move one, cancel it and re-run all its jobs, so the route job reads `CI_STUDIO` again.

The runners themselves can stay loaded. To stop a slot outright, `launchctl bootout gui/$(id -u)/io.openwaters.slackwater.ci-runner.<slot>`; `install.sh` loads it again.

## Tests

`sh scripts/ci-runner/install.test.sh` drives both scripts with `RUNNER_DRY_RUN=1` against a temporary `HOME`, with stand-ins for `launchctl list` and the simulator list. It never registers a runner, loads a job, or touches a simulator.
