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

## Testing before you open the PR

See the *Testing* section of `README.md`. Short version: `./scripts/test.sh`
while iterating, `./scripts/test.sh --full` before an upload — the full plan is
the only coverage of the live CHS network path.

## Agents

Claude Code and other agents work here under the same policy, with one addition:
**an agent never merges its own PR.** It may open one, push to its branch, and
respond to review. The merge is a human decision.

Agent-facing context lives in the `(agents: read this)` sections of `README.md`
and in the workspace `CLAUDE.md` / `AGENTS.md` one directory up.
