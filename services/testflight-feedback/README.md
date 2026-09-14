# TestFlight feedback intake

This directory contains the public intake code. Run it from a **separate private GitHub repository** using [`workflow.example.yml`](workflow.example.yml). Apple feedback text, screenshots, and crash logs go only to that private repository's issues and release assets. The poller does not write to the public project repository.

## Set up the private repository

1. Create a private repository for feedback and limit its readers, notifications, and release access. Keep it private: issues and release assets may contain identifying information. Check organization base permissions too; a private repo can still be readable by every org member.
2. Create a dedicated App Store Connect API key with the Developer role and access to the target app's TestFlight feedback. Apple team keys cover all apps, so use an individual key with narrower app access if available. Add `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, and the complete `.p8` text as `APPLE_PRIVATE_KEY` under the private repository's Actions **secrets**. Add `APPLE_APP_ID` and `FEEDBACK_REPOSITORY` (`owner/private-repo`) under Actions **variables**. Never commit the key or raw feedback.
3. After the public intake implementation is reviewed and its commit is on `main`, copy the example to `.github/workflows/testflight-poll.yml` in the private repository. Replace `REPLACE_WITH_REVIEWED_40_CHARACTER_COMMIT_SHA` with that exact commit SHA. Review and update this pin deliberately for later changes; do not use a branch or PR ref. The workflow's repository-scoped `GITHUB_TOKEN` needs only `contents: write` and `issues: write`.
4. The example has its `schedule` commented out. Run **Actions → TestFlight feedback intake → Run workflow → scan** once. Confirm the run logged only counts, the issue and any assets are private, and the `intake/` marker completed. Then enable the six-hour schedule. A manual scan can catch up after a failed or skipped scheduled run.

The workflow checks its repository identity before checkout; the poller also queries GitHub to verify the destination is private. It scans all pages of Apple's screenshot and crash feedback lists on every run, because Apple does not document a creation-date filter and GitHub scheduled runs can be delayed or dropped. This is intended for a small beta. Feedback removed from Apple before a successful scan cannot be recovered by this intake.

## Incomplete markers and retention

Runs are serialized. If an issue creation response is ambiguous, the poller leaves an `intake/` marker in `creating` rather than risking a duplicate. Manually run **reconcile** from the same workflow; it looks for an existing private issue with the marker's source key and repairs the marker when it finds one. If it cannot find a matching issue, inspect the private marker and GitHub issues before deciding whether to retry ingestion; do not blindly delete the marker. Keep logs free of feedback text, Apple response bodies, screenshot URLs, and crash logs.

One private release per feedback submission holds its screenshot or crash-log bytes; issue bodies reference them. Keep those assets while their issues need the evidence, and review both issues and releases under your private-repository retention policy. Deleting an issue does not remove its release assets automatically. The workflow uploads no Actions artifacts. A future public-issue triage process must redact private material explicitly; this intake never publishes it. Issues created by `GITHUB_TOKEN` generally do not trigger another GitHub workflow, so schedule that later process separately if needed.
