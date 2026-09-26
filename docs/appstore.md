# App Store releases

An App Store version ships a build that already went through Nightly and Beta; nothing is rebuilt. `scripts/asc.mjs` pushes everything App Review reads from this repo, submits the version, and releases it once approved. The listing copy is [`appstore-listing.json`](appstore-listing.json), the rules it is written against are in [App Store metadata](appstore-metadata.md), and each version's What's New is its [release notes](release-notes/) above the `Worth testing:` line.

Credentials are the same `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY` TestFlight uses ([TestFlight](testflight.md)). The review contact's phone number stays out of the repo: export `ASC_REVIEW_PHONE` when pushing review details, or the request leaves the phone out.

## Per release

1. **Pick the build.** It is a nightly that was promoted to Beta and checked on a device. `node scripts/asc.mjs builds` shows it as `<version> (<build>)`, `VALID`. Its number goes on the first line of `docs/release-notes/<version>.md`.
2. **Shoot the screenshots** on the current UI. The two runs write the directories `asc.mjs` reads:

   ```sh
   WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/iphone-6.9 ./scripts/screenshots.sh
   WALK=AppStoreScreenshots SHOT_DIR=/tmp/slackwater-appstore/ipad-13 \
     SLACKWATER_SIM='iPad Pro 13-inch (M5)' ./scripts/screenshots.sh
   ```

3. **Push the listing.** Read the dry run, then run it for real:

   ```sh
   node scripts/asc.mjs prepare 1.15.0 60 --dry-run
   ASC_REVIEW_PHONE='…' node scripts/asc.mjs prepare 1.15.0 60
   ```

   `prepare` creates or finds the version with manual release, then pushes app info and categories, the version's copy and What's New, and the review details. It attaches the build and replaces both screenshot sets. Rerunning it converges; each step is also its own command (below).
4. **Check the version page in App Store Connect.** Read it as App Review will, and finish anything under [What stays in the UI](#what-stays-in-the-ui).
5. **Submit.** `node scripts/asc.mjs submit 1.15.0 --dry-run`, then `--yes`. The submission holds the version alone, and `submit` refuses a draft submission that already holds anything else, such as an in-app purchase.
6. **Release.** Approval parks the version in Pending Developer Release. On release day, `node scripts/asc.mjs release 1.15.0 --yes` puts it on sale. Merge the `slackwater.xyz` release pull request at the same time, so the site never links to a version that cannot be downloaded yet.

## Commands

Every command takes `--dry-run`. `submit`, `release`, and `accessibility` reach an audience and refuse to run without `--yes`.

| Command | What it does |
|---|---|
| `prepare <version> <build> [screenshotDir]` | Everything below except submit, release, and accessibility, in order |
| `version <version>` | Finds or creates the iOS version, sets release type `MANUAL` and the copyright |
| `app-info` | Name, subtitle, privacy policy URL, primary and secondary category, content rights |
| `localization <version>` | Description, keywords, promotional text, support and marketing URLs, What's New |
| `review-details <version>` | Review contact and notes |
| `attach-build <version> <build>` | Attaches a `VALID`, unexpired, App Store–eligible build |
| `screenshots <version> [screenshotDir]` | Replaces the 6.9" iPhone (`APP_IPHONE_67`) and 13" iPad (`APP_IPAD_PRO_3GEN_129`) sets from `iphone-6.9/` and `ipad-13/` (default `/tmp/slackwater-appstore`) |
| `submit <version> --yes` | Creates a review submission holding the version and submits it |
| `release <version> --yes` | Releases a version in Pending Developer Release |
| `accessibility --yes` | Publishes the Accessibility Nutrition Labels in the listing file for iPhone and iPad |

**Dry runs** print every write with its body. With a key in the environment the reads are real, so the output is what a real run would send. With no key, nothing is read and every lookup misses: the output plans against an empty record, with placeholders such as `<appInfos>` and `<new appStoreVersions 1>` standing in for IDs.

## How the commands treat the record

- **An app has one editable version at a time.** A new app record starts with a `1.0` placeholder in Prepare for Submission, and `version` renames it rather than POSTing a second one, which App Store Connect refuses. A version past review is read-only, and the commands say so instead of editing it.
- **The app's first version has no What's New.** App Store Connect has no such field until a version has shipped, so `localization` skips it when the app has no other version. `1.14.0`'s release notes reach TestFlight and the GitHub release only.
- **App info edits go to the editable copy.** Once a version ships, the live app info is read-only, and App Store Connect opens an editable one alongside the next version.
- **Screenshots are checked before anything is deleted.** Each directory must hold 1 to 10 PNGs at a size the slot accepts. Upload order is file-name order, set explicitly after upload. The command waits for App Store Connect to process each image and fails on any it rejects.
- **The copyright line carries a year.** Update `version.copyright` in the listing file in January.

## What stays in the UI

Neither the API nor `asc.mjs` covers these. Answer them before the first submission, and again when what they describe changes.

- **App Privacy.** The API has no endpoint for the privacy questionnaire. The answers and the host check that justifies them are in [App Store metadata](appstore-metadata.md#privacy-app-store-connect-app-privacy-answers).
- **Age rating.** The questionnaire has an API, but `asc.mjs` doesn't cover it. Nothing in the app rates above 4+.
- **Pricing and availability.** Free, in the territories the data licences allow.
- **In-app purchases.** Attaching one to a version is a UI decision, and `submit` refuses a submission that holds one.
- **Phased release** for updates after the first.
