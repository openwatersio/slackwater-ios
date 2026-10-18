---
name: post-release
description: Use when App Review approves a Slackwater version, when a version goes live on the App Store, when Nightly uploads fail with errors 90186 or 90062, or when asked what is left to do after a release, which build is live, or whether a version has its v<version> GitHub release.
---

# After a Slackwater release

Two App Store milestones unblock work: App Review approving a version, and the version going live. Each has fixed steps in this repo, plus items in other openwatersio repos tracked in the [Slackwater releases](https://github.com/orgs/openwatersio/projects/4) project.

The TestFlight side, up to submission, is the `releasing-to-testflight` skill.

## The project

Every item has a **Release** (the version it waits on) and a **Waits for**:

| Waits for | Meaning | Example |
|---|---|---|
| Submission | Done before the version goes to App Review | The App Store listing |
| Approval | Done as soon as App Review approves | Opening the next train |
| App Store release | Done once the version is live | Website changes, the `v` tag and release |

At a milestone, filter on both fields and clear the list. Close the issues and merge the waiting draft PRs, then add any new item (such as the next train's issue) with its Release and Waits for set:

```sh
gh project item-add 4 --owner openwatersio --url <issue-or-pr-url>
```

Website changes wait as draft PRs. App changes are opened only after the milestone, so CI builds them against the latest `main`.

## When App Review approves

Approval closes the version's train. App Store Connect then rejects every upload to it with errors 90186 and 90062, and Nightly fails until `MARKETING_VERSION` moves.

1. Set `MARKETING_VERSION` in `project.yml` to the next minor version, run `xcodegen generate` and `zsh scripts/nightly.test.sh`, and merge. #713 is the pattern.
2. Once main CI passes on that commit, dispatch a fresh Nightly. Rerunning a failed Nightly job rebuilds its old commit on the closed train.
3. File the issue for the following train ("Open the 1.N+1.0 train when App Review approves 1.N.0") and add it to the project as Approval for the new version.

## When the version is live

1. **Find the released build.** The submitted build can change during review: 1.14.0 went in as 47 and shipped as 61. Read it from the version's page in App Store Connect or the release issue's latest comment, not from `docs/release-notes/`. Its commit is `git rev-parse nightly-<version>-<build>^{commit}`.
2. **Update `docs/release-notes/<version>.md`** so its version line names the released build and its highlights describe what that build ships. Merge that before publishing.
3. **Publish the GitHub release** at that commit, as the latest full release, titled with a headline that says what changed for people using the app, with no version (see [GitHub release title and notes](../../../CONTRIBUTING.md#github-release-title-and-notes)). The body is the notes file without its version line or its `Worth testing:` paragraph, which is for beta testers, so it opens with the one-line summary:

   ```sh
   sed -e '1,2d' -e '/^Worth testing:/,$d' docs/release-notes/<version>.md > /tmp/notes.md
   gh release create v<version> --target <commit> --title "<headline>" --notes-file /tmp/notes.md --latest
   ```

4. **Confirm:** `gh release list` shows `v<version>` as Latest.
5. **Clear the App Store release column** for the version in the project. Merge a waiting website PR only when the released build contains the app change it announces: `git merge-base --is-ancestor <app-change-commit> <released-commit>`. If it doesn't, move the item to the next Release.

## Common mistakes

| Mistake | Instead |
|---|---|
| Tagging the build named in the notes or the first submission | Tag the build App Review released |
| Opening the version-bump PR before approval | It moves Nightly off the train under review; wait |
| Rerunning the failed Nightly job after the bump | Dispatch a new run on the bumped commit |
| Finding the released build with `asc.mjs builds` | It lists uploads, not which one App Review released |
| Merging a website PR because its Release matches | Check the released build contains the change; a merge after the last upload ships in the next version |
| Stopping at the tag | The `v` release is the record; `gh release list` must show it |
| Publishing `Worth testing:` in the release | It's beta instructions; cut it |
