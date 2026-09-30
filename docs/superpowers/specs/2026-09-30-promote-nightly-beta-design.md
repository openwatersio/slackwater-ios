# Promote a nightly build to Beta

## Goal

An owner supplies a nightly build number to a GitHub Actions workflow. The workflow opens a reviewable release pull request for that existing binary. Merging the pull request approves promotion to every configured external TestFlight group, submits the build once for beta review, and publishes the final GitHub release without rebuilding the app.

App Store release remains outside this workflow.

## Release record

The release pull request checks in everything needed to repeat and audit the promotion:

- `docs/release-notes/<version>.md` contains the public highlights and final `Worth testing:` paragraph.
- `docs/release-promotions/<version>.json` identifies the marketing version, build number, nightly tag, and commit.
- `.github/testflight-beta-groups.txt` names the external TestFlight groups that receive every Beta release, one per line.

The promotion record remains as release history and gives the merge job a path-filtered, machine-readable trigger.

## Preparing the pull request

The manually dispatched job runs only from `main` and accepts one numeric build number. It fetches tags and finds exactly one `nightly-<version>-<build>` tag. The tag's commit must be reachable from `main`, App Store Connect must report the same version and build, and `v<version>` must not exist locally or on GitHub. Any mismatch stops before a branch or pull request is created.

The job reads merged pull request titles between the previous final version tag and the nightly commit. Those titles become concise `·` highlight lines in the current release-note format. The generated `Worth testing:` paragraph points testers at those changes and is deliberately reviewable copy, not an attempt to infer detailed test instructions from titles.

The pull request title names the version and build. Its body lists the binary, nightly tag, commit, target groups, and validation results. A deterministic branch name makes a repeated dispatch update the same release pull request instead of opening duplicates.

## Approval and promotion

A merge to `main` that contains a pending promotion record starts the promotion job in the protected `testflight` environment. The job validates the record again against the merge contents, Git tags, and App Store Connect before changing external state.

The job adds the exact existing build to each checked-in external group, then creates one beta review submission for the build. Group attachment is idempotent. A rerun recognizes a build already attached or already submitted and continues instead of creating a second review request.

After App Store Connect accepts the promotion, the job creates `v<version>` at the nightly commit with `docs/release-notes/<version>.md` as its release body. It then edits the nightly prerelease notes to name the final release and promotion run. The final tag never points at the pull request merge commit.

## TestFlight group safety

The checked-in external group list is the release policy. Both preparation and promotion fetch external groups for the Slackwater app and require an exact name match with that list. A group added or removed in App Store Connect blocks the workflow until the repository list is reviewed and updated.

`scripts/asc.mjs` owns App Store Connect lookup and mutation so authentication, app filtering, build waiting, and submission behavior stay in one place. It receives only the commands needed to resolve a build, verify groups, and idempotently promote a named build to the configured groups.

## Repository changes

The implementation should keep orchestration in one GitHub Actions workflow and put reusable validation in the smallest existing script that fits, preferring `scripts/asc.mjs` and a short shell script over a new framework or dependency.

`scripts/testflight.sh` becomes upload-only and no longer accepts `--external` or creates final releases. `docs/testflight.md` and `.claude/skills/releasing-to-testflight/SKILL.md` describe nightly upload, release pull request review, and merge-driven promotion as separate steps.

## Failure handling

Validation happens before mutation. Promotion stops on an ambiguous tag, mismatched commit or version, existing final tag, missing build, build processing failure, or TestFlight group drift. Error messages name the expected and observed values.

Once mutation begins, reruns are safe. The workflow treats an existing group attachment, beta submission, final release, or nightly annotation as the desired state when it matches the promotion record. A conflicting final tag or release remains a hard failure.

## Verification

One runnable script test stubs GitHub and App Store Connect at the command boundary. It covers successful preparation and promotion plus the dangerous failures: build mismatch, existing final tag, group drift, and duplicate beta submission. Workflow YAML receives a syntax check using tools already present in the repository or GitHub's own parser; no dependency is added only for validation.
