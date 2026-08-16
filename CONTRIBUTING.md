# Contributing to Slackwater iOS

This is a shared repo now. The rules below are short because they are meant to
be followed, not consulted.

## Branch and merge

**No direct pushes to `main`.** Work happens on a branch and lands through a
pull request.

```sh
git switch -c <area>/<short-description>    # e.g. tides/ticon-licence-gate
# ... work, commit ...
git push -u origin HEAD
gh pr create --fill
```

Nothing on GitHub's side enforces this. `openwatersio` is a free organisation
and this repo is private, which is the one combination where GitHub offers
neither branch protection rules nor rulesets — the API returns *"Upgrade to
GitHub Pro or make this repository public"* for both. So the policy holds by
agreement, and a slip is a mistake rather than a rejected push. If the org moves
to Team ($4/user/month), turn the two CI jobs into required checks and this
section stops being voluntary.

Two consequences of that, worth naming:

- **Force-pushing `main` is now off the table.** It was survivable when one
  person worked here. It is not survivable with two, and nothing will stop you.
  Force-push your own feature branches freely.
- **Rebase or squash, don't merge-commit.** Keeps `main` readable, which is the
  only reason the terse-commit habit works.

## Review

A PR needs one approval before merge. The exception is a PR that only touches
your own in-progress branch work or a revert of your own breakage — take those
yourself and say so in the description.

Prefer small PRs. A PR that changes generated data (`Slackwater/Resources/*`)
should say what the numbers went from and to, because the diff itself is one
enormous line of JSON and reviewing it any other way is not possible.

## CI

Two jobs, both defined in `.github/workflows/ci.yml`:

| Job | Where | What it does |
|-----|-------|--------------|
| Data generators | GitHub-hosted Ubuntu | `npm ci`, regenerates the two offline bundles, checks the committed artefacts still match, runs the bundle invariants |
| App tests | Self-hosted, Mac Studio | `scripts/test.sh` — xcodegen plus the fast test plan on both reference simulators |

The macOS lane is self-hosted because GitHub-hosted macOS bills at **10× on a
private repo**. The fast plan across both simulators is ~25 minutes of wall
clock, so ~250 billable minutes per run — roughly eight runs against the free
2,000-minute monthly allowance. The Studio is already the always-on
scheduled-job host, so it runs the lane for free and faster, off a warm SPM
cache.

`gen-chs-stations.mjs` is deliberately not in CI: it is the only generator that
needs the network (the DFO IWLS API), so its artefact is trusted as committed.
The other two are regenerated on every run, which is what makes the drift check
meaningful.

### A PR books the Studio. Docs-only work should not open one.

CI runs on `pull_request` for **any** branch, but on `push` only for `main`. So
pushing a branch costs nothing and opening a PR books ~25 minutes of the Mac
Studio — the same machine the scheduled jobs and everyone's local
`./scripts/test.sh` share. There is one macOS lane, so a PR that does not need
it puts every other session in a queue behind it.

**A change that touches no Swift, no `project.yml`, and no generated bundle —
a spec, a plan, a note, a README edit — goes on a branch and stops there.**
Push it so it is shareable and reviewable by URL, and say so rather than
opening a PR:

```sh
git push -u origin docs/<topic>          # shareable, no CI, no queue
# then link the branch or its compare URL; do NOT `gh pr create`
```

It merges by whatever route suits — fast-forward, or a PR opened later when the
runner is idle. This rule exists because `docs/cross-flow-check-spec` — two
markdown files, zero code — consumed a full 25-minute App-tests run, and a
later PR from the same session queued behind two others while a third session
waited.

**CI now enforces this too**, so the habit is belt and braces rather than the
only defence. The `What changed` job diffs the PR and skips the App-tests lane
when *every* changed path is under `docs/` or is a top-level `.md`. It is
fail-safe by construction: a path nobody anticipated runs the suite. It gates
the job rather than the workflow (`on: paths-ignore`) so the free Ubuntu lane
still runs, and so a required check — if this repo ever gets them — is
satisfied by a skip instead of hanging forever on a workflow that never
started.

Opening a docs PR is therefore no longer expensive. Prefer a branch anyway when
there is nothing to review; use a PR when someone actually needs to comment.

## Testing before you open the PR

See the *Testing* section of `README.md`. Short version: `./scripts/test.sh`
while iterating, `./scripts/test.sh --full` before an upload — the full plan is
the only coverage of the live CHS network path.

## Agents

Claude Code and other agents work here under the same policy, with two additions:
**an agent never merges its own PR** — it may open one, push to its branch, and
respond to review; the merge is a human decision — and **an agent does not open
a PR for docs-only work** (see *A PR books the Studio* above). Agents write a
lot of specs and plans into `docs/superpowers/`, so this rule bites them far
more often than it bites a human.

Agent-facing context lives in the `(agents: read this)` sections of `README.md`
and in the workspace `CLAUDE.md` / `AGENTS.md` one directory up.
