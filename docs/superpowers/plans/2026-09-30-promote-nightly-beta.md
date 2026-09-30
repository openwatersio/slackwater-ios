# Promote a nightly build to Beta implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reviewable, merge-approved GitHub workflow that promotes an existing nightly build to external TestFlight groups without rebuilding it.

**Architecture:** A small zsh script owns the prepare and release flows so they can run identically in tests and GitHub Actions. `scripts/asc.mjs` remains the only App Store Connect client, while one workflow supplies credentials and triggers the script on manual dispatch or a newly merged promotion record.

**Tech Stack:** GitHub Actions, zsh, GitHub CLI, Node.js 24 standard library, App Store Connect REST API

**Spec:** `docs/superpowers/specs/2026-09-30-promote-nightly-beta-design.md`

## Global constraints

- Promote the binary identified by `nightly-<version>-<build>`; never archive or upload during promotion.
- Reject a nightly commit outside `main`, a version or build mismatch, and any existing `v<version>` tag or release.
- Use merged pull request titles for release-note highlights.
- Require an exact match between `.github/testflight-beta-groups.txt` and the app's external App Store Connect groups.
- Submit beta review once per build and make reruns safe.
- Create `v<version>` at the nightly commit, not the promotion pull request merge commit.
- Add no dependencies.

## Review focus

- A build number containing whitespace, signs, or leading text must fail before any GitHub or App Store Connect mutation.
- Zero or multiple nightly tags ending in the requested build number must fail as ambiguous.
- A nightly tag whose commit is not reachable from `origin/main` must fail before creating a pull request.
- An App Store Connect group with the same spelling but different case must count as drift and block promotion.
- A rerun after group attachment or beta review submission must skip completed mutations while still repairing a missing GitHub release or nightly annotation.

---

### Task 1: Test and implement the release transaction script

**Files:**
- Create: `scripts/promote-nightly.sh`
- Create: `scripts/promote-nightly.test.sh`

**Interfaces:**
- Consumes: `scripts/asc.mjs verify <version> <build> <group-file>` and `scripts/asc.mjs promote <version> <build> <group-file>` from Task 2; `gh`, `git`, `node`, `GITHUB_REPOSITORY`, and `GITHUB_OUTPUT`.
- Produces: `zsh scripts/promote-nightly.sh prepare <build>` and `zsh scripts/promote-nightly.sh release <manifest-path>`.

- [ ] **Step 1: Write a failing shell test around command boundaries**

Create `scripts/promote-nightly.test.sh` using the temporary bare-repository and fake-command pattern from `scripts/nightly.test.sh`. Initialize `main` with `v1.14.0`, add two commits with nightly tag `nightly-1.15.0-48`, and place fake `gh` and `node` commands first on `PATH`.

The fake `node` accepts only these calls and records them in `$PROMOTE_STATE/events`:

```zsh
case "$*" in
  'scripts/asc.mjs verify 1.15.0 48 .github/testflight-beta-groups.txt') print 'asc:verify' >> "$PROMOTE_STATE/events" ;;
  'scripts/asc.mjs promote 1.15.0 48 .github/testflight-beta-groups.txt') print 'asc:promote' >> "$PROMOTE_STATE/events" ;;
  *) print -u2 "unexpected node call: $*"; exit 1 ;;
esac
```

The fake `gh` must return the titles `Improve current arrows` and `Fix favorite station ordering` for commit-to-pull-request lookups, record `pr create`, `release create`, and `release edit`, and answer that no final release exists. Assert all of these behaviors:

```zsh
prepare 48
grep -qx '1.15.0 (48)' "$REPO/docs/release-notes/1.15.0.md"
grep -qx '· Improve current arrows' "$REPO/docs/release-notes/1.15.0.md"
grep -q '^Worth testing:' "$REPO/docs/release-notes/1.15.0.md"
node -e 'const m=require(process.argv[1]); if (m.version!=="1.15.0" || m.build!==48 || m.tag!=="nightly-1.15.0-48" || !/^[0-9a-f]{40}$/.test(m.commit)) process.exit(1)' "$REPO/docs/release-promotions/1.15.0.json"
grep -q '^pr:create:' "$STATE/events"

release docs/release-promotions/1.15.0.json
[[ $(grep -c '^asc:promote$' "$STATE/events") == 1 ]]
grep -q '^release:create:v1.15.0:' "$STATE/events"
grep -q '^release:edit:nightly-1.15.0-48:' "$STATE/events"
```

Add negative cases for `48x`, two matching nightly tags, a tag on an unmerged branch, `node ... verify` failure, an existing `v1.15.0`, and a manifest commit changed by hand. Each must exit nonzero before `pr:create` or `asc:promote`. Run `release` twice with the fake GitHub client reporting matching releases on the second run and assert the second pass succeeds without another create.

- [ ] **Step 2: Run the test to verify it fails**

Run: `rtk test zsh scripts/promote-nightly.test.sh`

Expected: FAIL because `scripts/promote-nightly.sh` does not exist.

- [ ] **Step 3: Implement `prepare` with native shell and GitHub CLI**

Create an executable zsh script with `set -euo pipefail` and two explicit subcommands. `prepare` must:

```zsh
[[ $build == <-> ]] || fail 'build must contain digits only'
tags=("${(@f)$(git tag --list "nightly-*-$build")}")
(( ${#tags} == 1 )) || fail "expected one nightly tag for build $build, found ${#tags}"
tag=$tags[1]
version=${tag#nightly-}
version=${version%-$build}
commit=$(git rev-parse "$tag^{commit}")
git merge-base --is-ancestor "$commit" origin/main || fail "$tag is not reachable from origin/main"
git rev-parse -q --verify "refs/tags/v$version" >/dev/null && fail "v$version already exists"
gh release view "v$version" >/dev/null 2>&1 && fail "GitHub release v$version already exists"
node scripts/asc.mjs verify "$version" "$build" .github/testflight-beta-groups.txt
```

Find the previous final tag with `git describe --tags --abbrev=0 --match 'v*' "$commit^"`. Walk `git rev-list --reverse --first-parent "$previous..$commit"`, query `gh api "repos/$GITHUB_REPOSITORY/commits/$sha/pulls" --jq '.[0].title // empty'`, and fail if any commit has no associated merged pull request title. Write the notes and manifest through temporary files, then move them into place so a failed lookup leaves neither partial file.

Create or reset branch `release/$version-$build` at `origin/main`, add the two files, commit with `Prepare $version ($build) for Beta`, force-push that deterministic branch with `--force-with-lease`, and run:

```zsh
gh pr create --base main --head "release/$version-$build" \
  --title "Release $version ($build) to Beta" \
  --body-file "$body"
```

If a pull request already exists for that head, update its title and body with `gh pr edit` instead of creating another.

- [ ] **Step 4: Implement `release` with repeated validation**

Parse the checked-in JSON with one Node standard-library expression per field. Require exactly `version`, numeric `build`, `tag`, and a 40-character lowercase hexadecimal `commit`. Recompute `nightly-$version-$build`, resolve the tag, require the recorded commit, reject a conflicting final tag or GitHub release, and call:

```zsh
node scripts/asc.mjs verify "$version" "$build" .github/testflight-beta-groups.txt
node scripts/asc.mjs promote "$version" "$build" .github/testflight-beta-groups.txt
gh release create "v$version" --title "$version ($build)" \
  --notes-file "docs/release-notes/$version.md" --target "$commit"
gh release edit "$tag" --notes-file "$annotated_notes"
```

For reruns, accept `v<version>` only when `gh release view --json targetCommitish` resolves to the recorded commit; otherwise fail. Build the nightly annotation from its current body and append one stable line linking `v<version>` only when absent.

- [ ] **Step 5: Run the transaction test**

Run: `rtk test zsh scripts/promote-nightly.test.sh`

Expected: PASS with `nightly promotion checks passed`.

- [ ] **Step 6: Commit the tested transaction**

```bash
rtk git add scripts/promote-nightly.sh scripts/promote-nightly.test.sh
rtk git commit -m "Prepare nightly builds for Beta promotion"
```

### Task 2: Make App Store Connect promotion exact and idempotent

**Files:**
- Modify: `scripts/asc.mjs`
- Create: `.github/testflight-beta-groups.txt`
- Modify: `scripts/promote-nightly.test.sh`

**Interfaces:**
- Consumes: newline-separated exact external group names from `.github/testflight-beta-groups.txt`.
- Produces: `verify <version> <build> <group-file>` for read-only validation and `promote <version> <build> <group-file>` for idempotent group attachment and one review submission.

- [ ] **Step 1: Extend the failing test for group drift and reruns**

Add fake-client cases to `scripts/promote-nightly.test.sh` so `prepare` and `release` both stop when `node scripts/asc.mjs verify ...` reports `expected external groups [Beta], found [beta]`. Assert no `pr:create`, `asc:promote`, or `release:create` follows. Keep the successful rerun assertion from Task 1 to pin idempotence at the orchestration boundary.

- [ ] **Step 2: Run the focused test to verify the new case fails**

Run: `rtk test zsh scripts/promote-nightly.test.sh`

Expected: FAIL until the fake-state switch and both verification calls are wired consistently.

- [ ] **Step 3: Add shared App Store Connect resolution helpers**

In `scripts/asc.mjs`, replace the build-number-only `waitForBuild` argument with `(version, buildNumber)`. Match both the prerelease version relationship and `attributes.version`, require `processingState === 'VALID'`, and fail if the resolved build does not match both requested values.

Add these internal helpers without exporting a new module:

```js
async function externalGroups() { /* filtered by appId, isInternalGroup === false */ }
function expectedGroups(path) { /* UTF-8 lines, trim, reject blank/duplicate names, sort */ }
async function verifiedPromotion(version, buildNumber, path) { /* exact sorted-name equality, resolved build and groups */ }
```

The comparison is case-sensitive. Error text must include both sorted lists.

- [ ] **Step 4: Add `verify` and make `promote` idempotent**

`verify` calls `verifiedPromotion` and prints one line naming the version, build, commit-independent ASC build id, and groups. `promote` calls the same helper, reads the build's current `betaGroups`, and posts only missing relationships.

Fetch `/v1/builds/<id>/buildBetaDetail`. Submit `/v1/betaAppReviewSubmissions` only when `externalBuildState` is `READY_FOR_BETA_SUBMISSION`. Treat `WAITING_FOR_BETA_REVIEW` and `IN_BETA_TESTING` as already submitted. Fail on every other state so a rejected or expired build is never silently presented as promoted.

Update usage to:

```text
asc.mjs builds | verify <version> <buildNumber> <groupFile> | promote <version> <buildNumber> <groupFile> | notes ...
```

- [ ] **Step 5: Check in the reviewed group policy**

Create `.github/testflight-beta-groups.txt` with the current external group documented in `docs/testflight.md`:

```text
Beta
```

- [ ] **Step 6: Run the script checks**

Run: `rtk test zsh scripts/promote-nightly.test.sh`

Expected: PASS.

Run: `rtk test zsh scripts/nightly.test.sh`

Expected: PASS; nightly upload behavior remains unchanged.

- [ ] **Step 7: Commit the App Store Connect policy**

```bash
rtk git add scripts/asc.mjs scripts/promote-nightly.test.sh .github/testflight-beta-groups.txt
rtk git commit -m "Verify Beta groups before promotion"
```

### Task 3: Wire preparation and merge approval into GitHub Actions

**Files:**
- Create: `.github/workflows/promote-nightly.yml`
- Modify: `scripts/promote-nightly.test.sh`

**Interfaces:**
- Consumes: manual `build` input or a single added `docs/release-promotions/*.json` file on `main`.
- Produces: release pull requests from the `prepare` job and external promotion from the `release` job.

- [ ] **Step 1: Add static workflow assertions to the shell test**

At the end of `scripts/promote-nightly.test.sh`, assert that `.github/workflows/promote-nightly.yml` contains `workflow_dispatch`, a required `build` input, a `push` trigger limited to `main` and `docs/release-promotions/*.json`, `environment: testflight`, `contents: write`, and `pull-requests: write`. Assert the file does not contain `xcodebuild`, `testflight.sh`, or `archive`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `rtk test zsh scripts/promote-nightly.test.sh`

Expected: FAIL because `.github/workflows/promote-nightly.yml` does not exist.

- [ ] **Step 3: Create the two-trigger workflow**

Create `Promote Nightly to Beta` with:

```yaml
on:
  workflow_dispatch:
    inputs:
      build:
        description: Nightly build number
        required: true
        type: string
  push:
    branches: [main]
    paths: ['docs/release-promotions/*.json']
```

Use `concurrency: { group: beta-promotion, cancel-in-progress: false }`. Both jobs run on `ubuntu-latest`, use pinned `actions/checkout` and `actions/setup-node` SHAs already present in `.github/workflows/nightly.yml`, fetch full history, and use `environment: testflight` for App Store Connect secrets.

The `prepare` job runs only for `workflow_dispatch`, requires `github.ref == 'refs/heads/main'`, checks the triggering actor's admin permission using the owner gate copied from `nightly.yml`, grants `contents: write` and `pull-requests: write`, and runs:

```yaml
run: zsh scripts/promote-nightly.sh prepare '${{ inputs.build }}'
```

The `release` job runs only for pushes. Resolve exactly one added manifest with:

```zsh
files=("${(@f)$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD -- 'docs/release-promotions/*.json')}")
(( ${#files} == 1 )) || { print -u2 "expected one added promotion record, found ${#files}"; exit 1; }
zsh scripts/promote-nightly.sh release "$files[1]"
```

Pass `GH_TOKEN`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY`. Do not pass signing secrets because promotion never archives an app.

- [ ] **Step 4: Run local checks**

Run: `rtk test zsh scripts/promote-nightly.test.sh`

Expected: PASS.

Run: `rtk git diff --check`

Expected: no output.

- [ ] **Step 5: Commit the workflow**

```bash
rtk git add .github/workflows/promote-nightly.yml scripts/promote-nightly.test.sh
rtk git commit -m "Promote nightly builds after release review"
```

### Task 4: Remove the manual release path and document the workflow

**Files:**
- Modify: `scripts/testflight.sh`
- Modify: `docs/testflight.md`
- Modify: `.claude/skills/releasing-to-testflight/SKILL.md`
- Modify: `docs/release-notes/README.md`

**Interfaces:**
- Consumes: the workflow and commands completed in Tasks 1 through 3.
- Produces: one documented release path with `testflight.sh` restricted to upload and Nightly notes.

- [ ] **Step 1: Add the upload-only regression assertion**

Extend `scripts/promote-nightly.test.sh` with:

```zsh
! grep -q -- '--external\|--family\|asc.mjs promote\|gh release create' "$ROOT/scripts/testflight.sh" || fail 'testflight.sh still contains manual promotion'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `rtk test zsh scripts/promote-nightly.test.sh`

Expected: FAIL with `testflight.sh still contains manual promotion`.

- [ ] **Step 3: Reduce `testflight.sh` to upload-only behavior**

Delete argument parsing, external promotion, final GitHub release creation, and the manual promotion instruction. Keep archive, upload, optional nightly notes, and the final `asc.mjs builds` verification. End the upload path with a message that the build remains Nightly-only until the promotion workflow's release pull request merges.

- [ ] **Step 4: Update durable release instructions**

In `docs/testflight.md`, replace every `testflight.sh --external` instruction with the manual workflow dispatch, release pull request review, and merge approval. Document `.github/testflight-beta-groups.txt` as the exact group policy and `docs/release-promotions/<version>.json` as retained release history.

In `.claude/skills/releasing-to-testflight/SKILL.md`, replace the build-and-promote procedure with:

```text
1. Merge version changes before Nightly builds the binary.
2. Run Promote Nightly to Beta with the nightly build number.
3. Review the generated notes, manifest, commit, tag, and group list in the release pull request.
4. Merge to approve promotion.
5. Verify the workflow and `node scripts/asc.mjs builds` output.
```

In `docs/release-notes/README.md`, state that the promotion workflow drafts the file from merged pull request titles and reviewers must replace the generic `Worth testing:` paragraph when the release needs specific instructions.

- [ ] **Step 5: Run all release checks**

Run: `rtk test zsh scripts/promote-nightly.test.sh`

Expected: PASS.

Run: `rtk test zsh scripts/nightly.test.sh`

Expected: PASS.

Run: `rtk git diff --check`

Expected: no output.

- [ ] **Step 6: Commit the finished workflow documentation**

```bash
rtk git add scripts/testflight.sh docs/testflight.md docs/release-notes/README.md .claude/skills/releasing-to-testflight/SKILL.md scripts/promote-nightly.test.sh
rtk git commit -m "Document merge-approved Beta releases"
```

### Task 5: Verify the branch against the issue

**Files:**
- Review only: all files changed since `origin/main`

**Interfaces:**
- Consumes: Tasks 1 through 4.
- Produces: a clean, tested branch ready for pull request review.

- [ ] **Step 1: Run the complete focused suite**

Run: `rtk test zsh scripts/promote-nightly.test.sh`

Expected: PASS with `nightly promotion checks passed`.

Run: `rtk test zsh scripts/nightly.test.sh`

Expected: PASS with `nightly release checks passed`.

- [ ] **Step 2: Inspect the exact branch diff**

Run: `rtk git diff --check origin/main...HEAD`

Expected: no output.

Run: `rtk git diff --stat origin/main...HEAD`

Expected: only the workflow, release scripts and tests, group policy, release documentation, spec, and plan.

- [ ] **Step 3: Confirm every issue requirement has an implementation site**

Use `rtk grep` to verify the branch contains the nightly tag check, final tag rejection, release-note generation from GitHub pull request titles, checked-in group comparison, one beta review submission, final release target commit, nightly annotation, and no `testflight.sh --external` path. Fix any missing item before declaring the branch complete.
