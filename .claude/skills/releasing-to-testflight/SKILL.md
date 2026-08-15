---
name: releasing-to-testflight
description: Use when cutting a Slackwater iOS release, bumping MARKETING_VERSION or CURRENT_PROJECT_VERSION, running scripts/testflight.sh, or answering what version and build number TestFlight is actually serving.
---

# Releasing Slackwater to TestFlight

`project.yml` is the source of truth for both version numbers. It has not always
been — read The rule that bites before touching either one.

One-time infrastructure (ASC key, keychain, signing identity, profile) lives in
`docs/testflight.md`. This skill is the per-release procedure only.

## The rule that bites

`exportArchive`'s `manageAppVersionAndBuildNumber` **defaults to YES**. With that
default, Xcode rewrites `CFBundleVersion` at upload time to the next number free
on App Store Connect, and the archive's own number is discarded.

Slackwater ran on that default through build 21. The generated `Slackwater/Info.plist`
carried XcodeGen's literal `1.0` / `1` on every one of those uploads, so:

- ASC's build numbers were **a count of uploads**, not `CURRENT_PROJECT_VERSION`
- `CURRENT_PROJECT_VERSION` was a hand-kept guess at that count, correct only
  while bumps and uploads stayed 1:1 — it drifted the first time they didn't
- `MARKETING_VERSION` reached nothing at all. Builds 1–21 all read `1.0` to
  testers; 0.3.0, 0.5.0 and 0.6.0 existed only in git

Fixed 2026-08-11 (PR #48). `info.properties` now maps both plist keys to the
build settings, and the export sets `manageAppVersionAndBuildNumber` to `<false/>`.
**Both halves are load-bearing** — the plist keys alone are still overwritten at
upload, and the flag alone uploads build `1` and is rejected as a duplicate.

The consequence to plan around: **a stale `CURRENT_PROJECT_VERSION` is now a
rejected upload.** Nothing renumbers it for you.

## Cutting a release

1. `node scripts/asc.mjs builds` — read the highest build number already on ASC.
2. Bump in `project.yml`: `CURRENT_PROJECT_VERSION` above that number,
   `MARKETING_VERSION` if the release warrants it.
3. `./scripts/test.sh --full` — both reference simulators. The full plan covers
   the live-IWLS and on-device-fit tests the fast plan skips.
4. Open the release PR. Nothing reaches App Store Connect before it merges, and
   you never merge your own PR (`CONTRIBUTING.md`).
5. After the merge, from `main`: `./scripts/testflight.sh --family` for a release,
   plain `./scripts/testflight.sh` for a build only Nightly needs.
6. `node scripts/asc.mjs builds` again. Confirm the top row reads the version and
   build you intended, `VALID`, in the beta groups you expect.

Step 6 is not optional. It is the only place the intent in `project.yml` can be
checked against what testers will actually install.

## Known answers

Settled, so they don't get re-litigated:

| Question | Answer |
|---|---|
| Does ASC accept a *lower* pre-release train? | Yes. Build 22 went up as 0.6.0 after 21 builds at 1.0, VALID. |
| Why do builds 1–21 sit under a `1.0` train? | They shipped the plist literal. The eventual real 1.0 needs a build number above 21. |
| A build is `VALID` but a tester can't see it | Beta-group attachment, not the upload. The two groups behave differently — see below. |
| Why does Friends & Family need a flag when Nightly doesn't? | **Nightly is internal** with `hasAccessToAllBuilds`, so every upload lands there untouched. **Friends & Family is external, behind a public link**, so a build reaches it only after Apple beta review. `asc.mjs promote` does both steps; `externalState` goes `READY_FOR_BETA_SUBMISSION` → `WAITING_FOR_BETA_REVIEW` → `IN_BETA_TESTING`. |
| `Upload Symbols Failed … no dSYM for MapLibre.framework` | Pre-existing on every upload. MapLibre frames won't symbolicate in crash reports. Not a failed upload. |
| `promote` 422s `INVALID_QC_STATE` seconds after an upload | It promoted the *previous* build. ASC doesn't list a fresh upload for several minutes, and a bare `promote` takes the newest build it lists — build 23's release hit build 22, already reviewed. Since PR #88 `testflight.sh` passes the archive's own build number and `promote` waits for that build to appear. |
| Every UI test reports `Test crashed with signal kill`, zero assertion failures | Two test runs overlapping on this machine, not a code failure. See `docs/testflight.md`. |

## Common mistakes

- **Bumping `CURRENT_PROJECT_VERSION` to "the next one" from memory.** The git
  counter and the ASC counter agreed by hand-maintenance, not by mechanism. Read
  `asc.mjs builds` first, every time.
- **Uploading from an unmerged branch.** The repo's contract is that a release
  reaches ASC only after its PR merges.
- **Treating a green CI run as a released build.** CI never uploads. An upload is
  `scripts/testflight.sh` on `main` and nothing else.
- **Assuming a version bump shipped.** Until it appears in `asc.mjs builds`, the
  bump is a line in a YAML file. Build 22 sat merged and unuploaded for a day.
