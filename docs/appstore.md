# App Store releases

An App Store version ships a build that already went through Nightly and Beta; nothing is rebuilt. `scripts/asc.mjs` pushes every listing locale and the review details from this repo, submits the version, and releases it once approved. The listing copy is [`appstore-listing.json`](appstore-listing.json), the rules it is written against are in [App Store metadata](appstore-metadata.md), and each version's What's New is its [release notes](release-notes/) above the `Worth testing:` line.

Credentials are the same `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY` TestFlight uses ([TestFlight](testflight.md)). The review contact's phone number stays out of the repo: export `ASC_REVIEW_PHONE` when pushing review details, or the request leaves the phone out.

## Per release

1. **Pick the build.** It is a nightly that was promoted to Beta and checked on a device. `node scripts/asc.mjs builds` shows it as `<version> (<build>)`, `VALID`. The first line of `docs/release-notes/<version>.md` can contain just the version. If you add the build in parentheses, keep it aligned with any replacement selected during review; the GitHub sync checks it against Apple's attached build.
2. **Shoot and caption the screenshots** on the current UI. The medium iPhone, iPad and Watch sets are required; the large iPhone set is optional. Keep raw captures separate from the upload directories:

   ```sh
   WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore-raw/iphone-6.3 \
     SLACKWATER_SIM='iPhone 18 Pro' ./scripts/screenshots.sh
   WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore-raw/iphone-6.9 ./scripts/screenshots.sh
   WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore-raw/ipad-13 \
     SLACKWATER_SIM='iPad Pro 13-inch (M5)' ./scripts/screenshots.sh
   WALK=WatchAppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/watch ./scripts/screenshots.sh
   swift scripts/appstore-artwork.swift /tmp/slackwater-appstore-raw/iphone-6.3 \
     /tmp/slackwater-appstore/watch /tmp/slackwater-appstore/iphone-6.3
   swift scripts/appstore-artwork.swift /tmp/slackwater-appstore-raw/iphone-6.9 \
     /tmp/slackwater-appstore/watch /tmp/slackwater-appstore/iphone-6.9
   swift scripts/appstore-artwork.swift /tmp/slackwater-appstore-raw/ipad-13 \
     /tmp/slackwater-appstore/watch /tmp/slackwater-appstore/ipad-13
   ```

   The artwork exporter needs all five numbered raw frames, `widgets.png` (the free widget previews cropped from the Premium sheet), and the Watch set's `02-tide.png`. It writes six opaque PNGs at the raw device's accepted portrait dimensions: currents, tides, widgets and Watch, night, nearby, map. It reduces captures to fit without enlarging UI pixels and refuses an existing output directory. Use a fresh output directory for each export. Raw directories include a cropped widget image and must never be passed to the uploader.

   Captions are English. Check the Canadian storefront's inherited English set and every other locale's fallback before submission; these assets do not localize Spanish or French screenshots. The third frame shows only free features, with no Premium lock-screen widgets or complications. Canadian places can require an initial download before offline use. Inspect every export at full size and at search-result size before uploading. The widget previews use the preview screen's current clock; recapture the phone and Watch in the same session rather than mixing old and new UI.

   Export checks run without the simulator: `python3 scripts/appstore-artwork.test.py`.

3. **Push the listing.** Set `VERSION` and `BUILD` to the selected nightly train and build number. Read the dry run, then run it for real:

   ```sh
   node scripts/asc.mjs prepare "$VERSION" "$BUILD" --dry-run
   ASC_REVIEW_PHONE='…' node scripts/asc.mjs prepare "$VERSION" "$BUILD"
   ```

   `prepare` creates or finds the version with manual release, then pushes app info and categories, the version's copy and What's New, and the review details. It attaches the build and replaces the screenshot sets whose directories exist. Missing directories leave existing sets untouched; confirm every required set on the version page. Rerunning it converges; each step is also its own command (below).
4. **Check the version page in App Store Connect.** Read it as App Review will, and finish anything under [What stays in the UI](#what-stays-in-the-ui).
5. **Submit.** `node scripts/asc.mjs submit 1.15.0 --dry-run`, then `--yes`. The submission holds the version alone, and `submit` refuses a draft submission that already holds anything else, such as an in-app purchase.
6. **Release.** Approval parks the version in Pending Developer Release. On release day, `node scripts/asc.mjs release 1.15.0 --yes` requests distribution. Confirm the public listing resolves in the intended storefronts. The website already links to the App Store. A successful request starts distribution; it does not establish that the version is available yet. Rerunning `release` after distribution starts sends no second request.

7. **Publish accessibility labels** only after the device checks in #610 support every claimed label. Review `node scripts/asc.mjs accessibility --dry-run`, then publish with `--yes`. Apple Watch labels stay in the UI.
8. **Check the GitHub record.** The [Sync App Store releases](../.github/workflows/sync-appstore-releases.yml) workflow publishes missing stable GitHub releases hourly once a version is submitted to Apple. Confirm its summary names the App Store version, attached build, and exact Nightly commit. It can also be dispatched on `main`; manual runs default to a dry run. See [Automatic GitHub releases](#automatic-github-releases).

## Automatic GitHub releases

`node scripts/asc.mjs appstore-releases 1.15.0` reads submitted and shipped iOS versions at or above 1.15.0 and each version's attached build as JSON, including versions replaced by a newer release. The optional minimum is applied before fetching build relationships, so older records cannot block the sync. Waiting for Review is the first eligible state. Draft submissions and rejected versions are excluded. A GitHub release can therefore precede App Store availability. If Apple rejects a build after GitHub publication, ship a new version and leave the original tag intact. This reads the App Store record, not the latest TestFlight upload.

`node scripts/release-sync.mjs --dry-run` checks those records against Nightly tags, remote stable tags, and GitHub releases. The workflow publishes missing stable `v<version>` releases at `nightly-<version>-<build>`, using the current main branch's reviewed `docs/release-notes/<version>.md`. It creates new tags with a non-forced push before publishing with `--verify-tag`, refusing a conflicting tag created since validation. The notes' first summary line, without closing punctuation, becomes the headline; the body omits the version line and `Worth testing:`. Review and merge those notes before submitting for App Review. If their version line names a build, it must match Apple's attached build; leaving the build off lets Apple supply it. Existing release titles and bodies stay as published.

The hourly Ubuntu workflow uses the existing `testflight` environment secrets and runs only on this repository's `main`; manual dispatch and reruns require an owner. It checks out current main's release scripts and notes without the app's resource blobs, including on reruns. It does not build, upload, submit, or release an app. It validates every applicable version before writing, serializes its runs, and retries on the next schedule after an API or publication failure. The job summary records each version, build, and commit. Failed runs appear in Actions; scheduled-run email notifications go to the schedule's actor according to that user's notification settings.

Sync starts at **1.15.0**. The initial App Store version is `1.0`, recorded manually in GitHub as `v1.14.0`; that historical mapping remains outside automatic reconciliation. Nightly prereleases stay prereleases. The newest eligible version becomes Latest; backfilling older versions never downgrades a newer Latest.

A missing notes file, missing Nightly tag, or build mismatch fails the run. A stable tag pointing elsewhere also fails unless the sync previously published that tag during App Review and recorded its commit in the release. In that case the sync emits a workflow warning and keeps the original tag, even if the replacement ships. Preserve the hidden submission marker when editing release notes. Fix the notes or restore the verified Nightly record through review, then rerun. The sync never moves an existing tag or converts a draft or prerelease into a stable release. A tag with no release can be completed when its commit matches. Publishing is restricted to the serialized workflow, and Latest is re-read after publication. Local runs must use `--dry-run`; they need full, current Nightly tags and `origin/main` (`git fetch origin main --tags`) as well as App Store credentials and a GitHub token.

## Commands

Every command takes `--dry-run`. `submit`, `release`, and `accessibility` reach an audience and refuse to run without `--yes`.

| Command | What it does |
|---|---|
| `prepare <version> <build> [screenshotDir]` | Everything below except submit, release, and accessibility, in order |
| `version <version>` | Finds or creates the iOS version, sets release type `MANUAL` and the copyright |
| `app-info` | Name, subtitle and privacy policy URL in every locale, primary and secondary category, content rights |
| `localization <version>` | Description, keywords, promotional text, support and marketing URLs, and What's New, in every locale |
| `review-details <version>` | Review contact and notes |
| `attach-build <version> <build>` | Attaches a `VALID`, unexpired, App Store–eligible build |
| `screenshots <version> [screenshotDir]` | Replaces available `iphone-6.3/` (`APP_IPHONE_61`), `iphone-6.9/` (`APP_IPHONE_67`), `ipad-13/` (`APP_IPAD_PRO_3GEN_129`) and `watch/` (`APP_WATCH_ULTRA`) sets (default `/tmp/slackwater-appstore`) |
| `submit <version> --yes` | Creates a review submission holding the version and submits it |
| `release <version> --yes` | Releases a version in Pending Developer Release |
| `accessibility --yes` | Publishes the Accessibility Nutrition Labels in the listing file for iPhone and iPad |

**Dry runs** print every write with its body. With a key in the environment the reads are real, so the output is what a real run would send. With no key, nothing is read and every lookup misses: the output plans against an empty record, with placeholders such as `<appInfos>` and `<new appStoreVersions 1>` standing in for IDs.

## How the commands treat the record

- **An app has one editable version at a time.** A new app record starts with a `1.0` placeholder in Prepare for Submission, and `version` renames it rather than POSTing a second one, which App Store Connect refuses. A version past review is read-only, and the commands say so instead of editing it.
- **The app's first version has no What's New.** App Store Connect has no such field until a version has shipped, so `localization` skips it when the app has no other version. Subsequent versions require release notes even when the public version number differs from an earlier nightly train.
- **App info edits go to the editable copy.** Once a version ships, the live app info is read-only, and App Store Connect opens an editable one alongside the next version.
- **Screenshots are checked before anything is deleted.** Each directory must hold 1 to 10 PNGs at a size the slot accepts. Upload order is file-name order, set explicitly after upload. The command waits for App Store Connect to process each image and fails on any it rejects.
- **The copyright line carries a year.** Update `version.copyright` in the listing file in January.

## What stays in the UI

Neither the API nor `asc.mjs` covers these. Answer them before the first submission, and again when what they describe changes.

- **App Privacy.** The API has no endpoint for the privacy questionnaire. The answers and the host check that justifies them are in [App Store metadata](appstore-metadata.md#privacy-app-store-connect-app-privacy-answers).
- **Age rating.** The questionnaire has an API, but `asc.mjs` doesn't cover it. Nothing in the app rates above 4+.
- **Pricing and availability.** Free, in the territories the data licences allow.
- **Translated release notes.** A matching `<version>.<locale>.md` supplies What's New; otherwise the English notes are used. Check each listing locale against the selected build.
- **Mac and iPhone Duo screenshots.** Capture and upload them through the UI using [the metadata guide](appstore-metadata.md#before-submission). The uploader handles iPhone, iPad and Watch only.
- **In-app purchases.** Attaching one to a version is a UI decision, and `submit` refuses a submission that holds one.
- **Phased release** for updates after the first.
