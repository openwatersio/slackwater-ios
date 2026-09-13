# TestFlight feedback intake design

Research checked 2026-09-13. The public `slackwater-ios` repository holds the open-source TypeScript intake code. A **separate private GitHub repository** runs a scheduled workflow and holds raw feedback. Public issue drafting is a later stage and is not authorized by this intake.

## Verified API capabilities and limits

- Apple lists screenshot feedback at [`GET /v1/apps/{id}/betaFeedbackScreenshotSubmissions`](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-betafeedbackscreenshotsubmissions) and crash feedback at [`GET /v1/apps/{id}/betaFeedbackCrashSubmissions`](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-betafeedbackcrashsubmissions). Both collections are paginated and sortable by creation date. Neither documents a creation-date filter, so the initial implementation scans **all pages of both collections** on each run. Read specific records with `GET /v1/betaFeedbackScreenshotSubmissions/{id}` or `GET /v1/betaFeedbackCrashSubmissions/{id}` when needed.
- App Store Connect API reads use an [ES256 JWT](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests) with issuer ID, key ID, `aud=appstoreconnect-v1`, and a short expiry. The list/detail records expose comment, creation time, device model, OS version, feedback ID, and a build relationship; request only required fields and `build`, never tester or email. The build and its [prerelease version](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-builds-_id_-prereleaseversion) supply build number and app version.
- Screenshot feedback includes image URLs with an [expiration date](https://developer.apple.com/documentation/appstoreconnectapi/betafeedbackscreenshotimage); fetch bytes during ingestion because the URL is temporary. Crash feedback has a crash-log relationship whose [`logText`](https://developer.apple.com/documentation/appstoreconnectapi/betacrashlog/attributes-data.dictionary) can be fetched when available. Older TestFlight clients may [send feedback by email](https://developer.apple.com/help/app-store-connect/test-a-beta-version/view-tester-feedback); this API-only intake will not ingest those messages.
- A private GitHub Actions workflow can run on a [schedule](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onschedule) or `workflow_dispatch`. Scheduled runs can [start late or be dropped](https://docs.github.com/en/actions/reference/events-that-trigger-workflows#schedule); a later full scan catches up while Apple retains the feedback. Set [`concurrency`](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency) so runs cannot process the same feedback at once. Grant the private repo's `GITHUB_TOKEN` only `issues: write` and `contents: write` plus permissions needed for release assets; no public-repo write token is needed.
- GitHub can [create private issues](https://docs.github.com/en/rest/issues/issues#create-an-issue) and small [Contents API records](https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents). There is no documented REST upload endpoint for issue attachments. Store screenshot bytes and crash logs as [release assets](https://docs.github.com/en/rest/releases/assets#upload-a-release-asset) in the same private repo; [private releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) are available only to repository readers. Rotate releases before their 1,000-asset limit. An issue created with `GITHUB_TOKEN` generally [does not trigger another workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow), so any future triage job should schedule its own scan unless a different credential is deliberately introduced.

Apple also offers [webhook events](https://developer.apple.com/documentation/appstoreconnectapi/webhook-events) for new screenshot/crash submissions, but polling needs no public endpoint, webhook secret, request-signature verifier, or Cloudflare Worker. The cost is delivery latency and a risk that feedback disappears from Apple before the next successful run.

## Data flow and privacy boundary

`Apple App Store Connect API → private GitHub Actions runner → private GitHub issue and release assets`

1. The private repo runs the poller every six hours, away from the top of the hour, and allows manual `workflow_dispatch`. The workflow checks out a **reviewed, pinned commit SHA** of the public intake code. Secrets live only in the private repo's GitHub Actions secrets: Apple issuer ID, key ID, and API private key. The configured Apple app ID is a private workflow variable. No secret or private repo identifier is committed to the public project.
2. The poller mints a short-lived Apple JWT, paginates both feedback collections to completion, and processes each submission ID. It uses the app-scoped list endpoints and fetches only required detail/build data. It downloads an available screenshot promptly and reads an available crash log, with an 8 MiB per-asset cap. Missing, expired, or oversized assets are recorded as private issue omissions, not as public or expiring links.
3. Before any write, the poller verifies that `GITHUB_REPOSITORY` is the configured **private** destination and that the repository API reports `private: true`. The workflow's `GITHUB_TOKEN` is scoped to this repository. It writes asset bytes to private release assets, then creates one private issue per Apple feedback ID. The public repository has no write path.
4. The runner keeps feedback only in memory or ephemeral temporary files. Disable shell tracing and workflow artifacts; log only feedback kind, opaque IDs, counts, outcome, and error class. Do not print Apple/GitHub response bodies, comments, crash logs, image URLs, or asset bytes. GitHub's [secret masking is not a general PII filter](https://docs.github.com/en/actions/reference/security/secure-use). GitHub is the only durable copy made by this service.

**Copied to private GitHub:** verbatim comment; screenshot bytes or crash-log text when available; Apple app/feedback/build IDs, feedback type, app version, build number, submission time, device model, and OS version. **Omitted:** tester name/email and tester relationship, locale, time zone, network, battery, storage, uptime, and other diagnostics. Comments, images, and logs can themselves contain PII; restrict private-repo membership, notifications, and release access accordingly. Never make the feedback repository public.

## Deduplication and recovery

Define `source_key = <Apple app ID>:<screenshot|crash>:<Apple submission ID>`. The private repository owns a small `intake/<SHA-256(source_key)>.json` record containing the key, phase, asset IDs, and eventual issue number—no raw feedback. A completed record skips the submission on later full scans.

The workflow's concurrency group serializes scheduled and manual runs. Before creating an issue, write the marker in phase `creating` and include the source key in a machine-readable comment in the issue body. If GitHub times out or the create response is ambiguous, **do not retry Create an issue automatically**: leave the marker for a manual reconciliation command that searches the private issues for the source key, then binds the existing issue number or resumes only after confirming none exists. This avoids duplicate issues at the cost of a stuck item needing operator attention. Deterministic private asset names let pre-issue asset work resume without duplicate uploads. Mark `complete` only after the issue and required labels exist. Record API errors without raw response bodies. Validate create-if-absent marker behavior and recovery under concurrent/manual runs during implementation.

A full scan needs no timestamp cursor or scheduler state. A failed or skipped run can catch up on the next run or manual dispatch. Feedback deleted from Apple before ingestion is unrecoverable by this design; document that operational limit.

## Private issue contract (v1)

Title: `[TestFlight screenshot] 1.2.3 (456) · <short source-key hash>` (or `crash`), with no tester words. Labels: `testflight-feedback`, `source:screenshot` or `source:crash`, `needs-triage`, and `version:1.2.3`; keep build number in the body.

The body begins with a delimited `<!-- testflight-feedback:v1 ... -->` JSON block containing `source_key`, Apple app/submission/build IDs, feedback type, app version/build number, submission time, device model, OS version, private asset IDs, asset omissions, `triage_status: "needs-triage"`, `related_private_issue_numbers: []`, and `public_issue_url: null`. Below it, put the **verbatim** comment in a safe fenced code block and link only to private screenshot/log assets. Treat all text as untrusted when rendering. The future triage process can compare these records, redact PII, draft a reproduction-oriented public issue, and update the private links. This poller never writes to the public repo.

## Proposed files and implementation plan

Public `slackwater-ios` repository:

    services/testflight-feedback/
      src/poll.ts          # CLI entry point, pagination, ingestion loop
      src/apple.ts         # Apple JWT and feedback/build/asset reads
      src/github.ts        # private destination guard, marker, assets, issues
      test/poll.test.ts    # small mocked API tests
      package.json        # TypeScript build/check/run
      README.md           # private-repo setup and recovery instructions
      workflow.example.yml # copy into private repo and pin public commit SHA

Private feedback repository: `.github/workflows/testflight-poll.yml`, Actions secrets/variables, `intake/` marker files, private issues, and private release assets. No database, webhook endpoint, Cloudflare deployment, dashboard, or public-issue agent.

1. Create the private feedback repository, labels, and an Apple API key with read access. Add Apple credentials as private Actions secrets and copy the workflow template, pinning the reviewed public code commit. Set `schedule`, `workflow_dispatch`, minimal permissions, concurrency, and no artifact upload.
2. Implement Apple pagination, typed field selection, JWT auth, build/version reads, screenshot/log download, and per-asset limits. Exercise against representative Apple API responses.
3. Implement the private-repository guard, dedup marker phases, deterministic release assets, and versioned private issue format. Add focused checks for duplicate runs, missing assets, private-repo guard, and ambiguous issue creation.
4. Run a manual private-repo workflow against real feedback, inspect sanitized logs and issue/assets, then enable the schedule. Document stuck-marker reconciliation and release-asset retention. Stop here; public triage remains a separate design and implementation.
