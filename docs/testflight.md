# TestFlight — headless signing & upload

Slackwater ships from the Open Waters Apple team (`Z59BQLF5VQ`). The Nightly workflow (`.github/workflows/nightly.yml`) bumps the build number, runs the full suite, and calls `scripts/testflight.sh` on a GitHub-hosted macOS runner. Everything below is the one-time state that relies on, and how to rebuild it.

## The pieces

| Piece | Where | Notes |
|---|---|---|
| ASC API key | `testflight` environment secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY` (the `.p8` contents) | Signs `asc.mjs` requests and authenticates the upload. App Store Connect → Users and Access → Integrations → Team Keys, role App Manager |
| Bundle ID (app) | `io.openwaters.slackwater` | Capabilities: In-App Purchase, App Groups, iCloud (key-value storage), Associated Domains. The `apple-app-site-association` file slackwater.xyz serves for `applinks:` must list `Z59BQLF5VQ.io.openwaters.slackwater` |
| Bundle ID (appex) | `io.openwaters.slackwater.widgets` | Capabilities: App Groups. An appex needs its own bundle ID **and its own profile** — the app's covers neither |
| App Group | `group.io.openwaters.slackwater` | Shared by app + appex (`Slackwater.entitlements`, `SlackwaterWidgets.entitlements`); how the widget reads the fitted model and the Premium entitlement. **Not in the ASC API** — `/v1/appGroups` is a 404. Create it in Xcode or the developer.apple.com UI |
| In-app purchases | `io.openwaters.slackwater.premium.yearly` (auto-renewable, in a subscription group) and `io.openwaters.slackwater.premium.lifetime` (non-consumable) | `PremiumStore.swift`. Created in the App Store Connect UI. `Slackwater.storekit` only reaches Debug runs, so an archive with no products in ASC shows the pitch with nothing to buy |
| Distribution identity | `testflight` environment secrets `SIGNING_P12` (base64 `.p12`) and `SIGNING_P12_PASSWORD` | "Apple Distribution" certificate, minted through `asc.mjs create-cert`. `testflight.sh` imports it into a throwaway keychain per run |
| Provisioning profiles | "Slackwater App Store" and "Slackwater Widgets App Store" | `testflight.sh` downloads both by name (`asc.mjs install-profiles`), so a re-mint needs no secret change. Both must post-date every capability on their bundle ID |
| Signing config | `project.yml`: Release = manual signing, "Apple Distribution" + the profile; Debug stays automatic | |

## One-time setup

Run from a checkout with the ASC key exported (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY`). `op run` works well for keeping them in 1Password.

1. **App IDs, capabilities, and the App Group.** Open `Slackwater.xcodeproj` signed into the team and build the Debug scheme to a device. Automatic signing registers both bundle IDs, enables the capabilities in the entitlements files, and creates the App Group. Confirm on developer.apple.com → Identifiers that both IDs list the capabilities in the table above.
2. **App record.** App Store Connect → Apps → New App, bundle ID `io.openwaters.slackwater`. Records can't be created through the public API.
3. **In-app purchases.** Create the subscription group, the yearly subscription, and the lifetime purchase with the product IDs above. Reference names match `Slackwater.storekit`: group "Slackwater Premium", "Premium Yearly", "Premium Lifetime". Check `inAppPurchasesV2` and `subscriptionGroups` on the app before release notes mention a purchase.
4. **Distribution certificate.**

   ```sh
   openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -subj "/CN=Slackwater Distribution" -out dist.csr
   node scripts/asc.mjs create-cert dist.csr dist.cer          # prints the certificate id
   openssl x509 -inform der -in dist.cer -out dist.pem
   openssl pkcs12 -export -inkey dist.key -in dist.pem -out dist.p12   # add -legacy with OpenSSL 3
   ```

   The `-legacy` flag matters: `security import` can't read OpenSSL 3's default `.p12` encryption. macOS's own `/usr/bin/openssl` (LibreSSL) writes the old format already.
5. **Profiles**, after step 1 so they carry every capability:

   ```sh
   node scripts/asc.mjs create-profile io.openwaters.slackwater <certId> app.mobileprovision
   node scripts/asc.mjs create-profile io.openwaters.slackwater.widgets <certId> widgets.mobileprovision "Slackwater Widgets App Store"
   ```

6. **Secrets**, in a `testflight` environment that only `main` can deploy to, so a workflow edited on another branch can't read them:

   ```sh
   gh api -X PUT repos/openwatersio/slackwater-ios/environments/testflight \
     -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true'
   gh api -X POST repos/openwatersio/slackwater-ios/environments/testflight/deployment-branch-policies -f name=main
   gh secret set -e testflight ASC_KEY_ID; gh secret set -e testflight ASC_ISSUER_ID
   gh secret set -e testflight ASC_KEY < AuthKey_XXXXXXXXXX.p8
   base64 -i dist.p12 | gh secret set -e testflight SIGNING_P12
   gh secret set -e testflight SIGNING_P12_PASSWORD
   ```

   Keep `dist.key`/`dist.p12` in 1Password and delete the local copies.
7. **Tester groups.** Create an internal "Nightly" group with access to all builds, and the external groups with public links (see Tester groups).

To release by hand from a Mac, export the same five variables and run `scripts/testflight.sh`.

## Why a throwaway keychain

Non-GUI sessions (agents, launchd, ssh, CI) see the **login keychain as locked**: codesign fails with `errSecInternalComponent`, `-allowProvisioningUpdates` cloud signing dies with "User interaction is not allowed", and `set-key-partition-list` on the login keychain doesn't help, because the lock, not the ACL, is the blocker. `testflight.sh` creates a keychain with a random password, imports the identity, adds it to the search list, and removes it on exit. Holding one identity also keeps "Apple Distribution" unambiguous; a login keychain with two same-named identities picks one arbitrarily. Cloud-managed signing is never used. Certificate renewal = steps 4–6 again.

## Tester groups

| Group | Kind | Gets builds | Link |
|---|---|---|---|
| Nightly | internal (`hasAccessToAllBuilds`) | every upload, automatically, no review | — |
| Friends & Family | external, public link | only what `asc.mjs promote` adds, **after Apple beta review** | _not yet created_ |
| OSS and Externals | external, public link | same — and this is the link `slackwater.xyz` publishes as its download button (`src/routes/index.tsx`), so a release that skips it leaves the public page on the previous build. Update that button when the link changes | _not yet created_ |

The public link is written down here because it exists nowhere else in the repo — App Store
Connect mints it and `asc.mjs` never reads it back. Re-read it any time with
`GET /v1/betaGroups` → the group's `attributes.publicLink` (`publicLinkEnabled` is the
on/off switch, `publicLinkLimit` the tester cap, currently unset).

Before handing the link to anyone, check what they'd actually install: `node scripts/asc.mjs
builds` shows group membership, but membership is not availability — an external build sits
in `WAITING_FOR_REVIEW` until Apple clears it, and testers keep getting the last **approved**
build meanwhile. Build 25 was in the group and pending review the day it shipped.

## Adding a capability breaks every existing profile (2026-08-23)

Build 28 was merged, approved, and dead on arrival: `xcodebuild archive` failed with
six errors, all of them App Groups. The suite had been green twice on both simulators.
It could not have helped — simulator builds sign with a wildcard development profile
and ignore entitlements the archive enforces.

The order that works, when a target gains an entitlement:

1. **Register the bundle ID** if it is new (`POST /v1/bundleIds`). An app extension
   is a separate bundle ID; the app's does not cover it.
2. **Create the App Group in the developer.apple.com UI.** There is no API —
   `/v1/appGroups` returns 404 `NOT_FOUND`, "the path provided does not match a
   defined resource type". Enable App Groups on *each* bundle ID and assign the group.
3. **Re-mint every affected profile.** Profiles are snapshots: "Slackwater App Store"
   was minted 2026-07-30, long before the entitlement existed, and adding the
   capability does not retroactively update it.
4. **Give the appex a `Release` block in `project.yml`.** Without one it stays on
   `CODE_SIGN_STYLE: Automatic` and Release falls back to
   `"iOS Team Provisioning Profile: *"` — which needs a GUI session to mint, so a
   headless archive simply fails.
5. **Add the appex to `exportOptions`' `provisioningProfiles` dict** in
   `testflight.sh`. A missing entry fails the export *after* a successful archive.

Verify before archiving, rather than after:

```sh
node scripts/asc.mjs builds     # highest build already on ASC
# Does the profile carry the group, and is it bound to the bundle you think?
for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
  security cms -D -i "$f" | plutil -p - \
    | grep -E '^  "Name"|application-identifier"|group\.'
done
```

**Check `application-identifier`, not just the name.** `filter[identifier]` on
`/v1/bundleIds` is a **prefix** match: it returns `io.openwaters.slackwater` *and*
`io.openwaters.slackwater.widgets`, appex first. `create-profile` took `data[0]`,
so the first mint after the appex was registered produced a profile **named**
"Slackwater App Store" and **bound to the widget's bundle id** — success message,
right name, wrong profile. Fixed by matching the identifier exactly; the check
above is what caught it.

**Favourites went to iCloud (#134) and the app target gained
`com.apple.developer.ubiquity-kvstore-identifier`.** Same drill, with one
difference: iCloud *does* have an API where App Groups does not. `POST
/v1/bundleIdCapabilities` with `capabilityType: ICLOUD` and `ICLOUD_VERSION:
XCODE_6` against the app's bundle id returns 201. Key-value storage needs no
iCloud *container*, so there is nothing to create and nothing to assign, and only
the app target is affected — the appex reads favourites out of the App Group,
never out of KVS. After re-minting, confirm the signed app carries
`com.apple.developer.ubiquity-kvstore-identifier => Z59BQLF5VQ.io.openwaters.slackwater`
(`codesign -d --entitlements`). That is the check the merge gate cannot do for you.

**Delete the old file when you re-mint, or the name stops identifying a profile.**
This matters on a Mac that archives locally; a hosted runner starts empty.
`PROVISIONING_PROFILE_SPECIFIER` matches on *name*, so with two same-named
profiles installed, which one an archive picks is not something this repo
controls, and the failure looks like a missing entitlement rather than a stale
file. The `security cms -D` loop above prints one line per installed profile; a
repeated name in that output is the bug.

## Cadence

Per-release procedure lives in the `releasing-to-testflight` skill
(`.claude/skills/`) — bump, test, PR, upload, verify. What follows is the state
that procedure sits on.

- **A release goes to every external group, not one.** `./scripts/testflight.sh --external`
  (the flag was `--family`, still accepted) promotes to all groups with
  `isInternalGroup: false`, discovered at run time rather than named — adding a fourth
  group needs no code change. Beta review is submitted **once per build**; it is not
  per group and a second submission 409s. Check with `node scripts/asc.mjs builds`,
  whose group column is the only place the asymmetry is visible.
- Bump `CURRENT_PROJECT_VERSION` in `project.yml` per upload (App Store Connect rejects reused
  build numbers per version); `MARKETING_VERSION` per release. **Both reach the bundle only
  because `info.properties` maps them to `CFBundleVersion` / `CFBundleShortVersionString` and
  the export sets `manageAppVersionAndBuildNumber` `<false/>`** — through build 21 neither was
  wired, Xcode renumbered every upload itself, and every build shipped as `1.0`. Check the
  result with `node scripts/asc.mjs builds`.
- App record ("Slackwater — Tides & Currents") + tester management stay in the App Store
  Connect UI — records can't be created via the public API.
- Export-only variant (signed .ipa, no upload): `build/exportOptions.plist` with
  `destination: export` — what the first proof run used.
- **Fill bundle refit is a release-time decision, not a sync** (`fill-salish.bin`,
  2026-08-21). Fitted constants do not expire; ship the committed bundle as-is
  unless SSCOFS revises its mesh/model or new stations change certification.
  Refit = re-run `tools/fill-pipeline/` end-to-end (README there; ~5 h fetch +
  hours of compute + the size gate + re-pin the real golden in
  `FillFieldTests`). The header JSON records corpus window + mesh hash — check
  those before assuming a refit is needed.

## Test runs — offline by default, full before an upload (2026-09-08)

One XCTestPlan (`TestPlans/Slackwater.xctestplan`), checked in and wired into the
scheme by `project.yml`. `scripts/test.sh` selects targets from that plan and
prints a per-simulator wall clock. Default, full, and unit modes use only local
recordings and seeded state. Only `--live` opts into real IWLS access, with
`TEST_RUNNER_SLACKWATER_LIVE=1` reaching the UI-test runner.

The versioned recording is committed at `SlackwaterTests/Fixtures/iwls-recording.json`, so fresh checkouts and CI runners have the same input. Unit-containing modes run `node scripts/iwls-fixtures.mjs prepare` to validate it offline. `node scripts/iwls-fixtures.mjs refresh` explicitly downloads an updated recording for review in Git. `SLACKWATER_FIXTURE_DIR` can supply an alternative recording to stage; routine runs never refresh it.

```sh
./scripts/test.sh                                  # offline unit + UI, iPhone
./scripts/test.sh --full                           # offline both sims + exhaustive data check
./scripts/test.sh --unit                           # unit target only, one simulator
./scripts/test.sh --live                           # real-IWLS smoke only, one simulator
SHOT_DIR=/tmp/shots ./scripts/test.sh              # where the UI tests save screenshots
SLACKWATER_SIMS='SimA,SimB' ./scripts/test.sh      # run on other devices
```

### One test run at a time (2026-08-02)

Two `xcodebuild test` runs on this Mac SIGKILL each other's test runner: every UI
test in the losing run reports `Test crashed with signal kill` with **zero
assertion failures**. It reads as a real failure and is not one. If you see that
signature, check whether something else was testing at the same time before you
debug the code.

Five runs died this way on 2026-08-02 — 3, 6 and 16 UI tests at a time — and the
last of them had the two runs on *different simulator devices*, so device
separation does not avoid it. The exact kill mechanism was never pinned down; the
CoreSimulator logs had already rolled off. The correlation with overlap was 5 for 5.

Those five were CI against a local run, from when the macOS lane was self-hosted on
this Mac. CI is GitHub-hosted now (#327), so the overlap left to guard against is
local against local — another worktree, another agent session — which this machine
has more of than it ever had CI runs. `scripts/test.sh` takes a machine-wide
`lockf(1)` lock and whoever arrives second waits; it prints a line when it's
waiting. The lock lives in the kernel, so a killed or cancelled run releases it and
nothing wedges.

Two smaller pieces of the same story:

- `SLACKWATER_SIMS` names the devices to run on, overriding the fast/full list
  outright. CI passes the runner image's stock `iPhone 17` to keep the hosted lane
  iPhone-only; locally it is how you run on a clean device instead of the base one.
- Every run writes screenshots to `/tmp/slackwater-shots` unless `SHOT_DIR` says
  otherwise, so two local runs overwrite each other's images.

| Mode | Devices | Contents | Wall clock |
|---|---|---|---|
| **Fast** (default) | iPhone 17 | offline unit and UI tests; skips the exhaustive national sweep | Re-measure after migration |
| **Full** (`--full`) | iPhone 17 + iPad Pro 11-inch (M5) | offline unit and UI tests plus the national sweep | Re-measure after migration |
| **Unit** (`--unit`) | one simulator | unit target, including the national sweep | Re-measure after migration |
| **Live** (`--live`) | one simulator | `LiveFetchTests` compatibility smoke only | Network-dependent |

The old timings mixed routine behavior coverage with live downloads and do not
describe these modes. Record observed timings after the migrated suite runs.
Run fast while iterating and offline `--full` before `scripts/testflight.sh`.
Run `--live` separately when real-service compatibility needs checking; green
offline runs intentionally make no claim about current IWLS availability.

Fast and unit modes pass `-collect-test-diagnostics never`. Failed assertions,
screenshots, and the result bundle remain available, while Xcode skips the
multi-minute simulator diagnostics collection that otherwise delays routine
failure feedback. Full and live modes retain `on-failure` diagnostics.

Screenshots: `ScreenshotTestCase` reads `M1_SHOT_DIR` **inside the UI-test runner process**, so
the script exports `TEST_RUNNER_M1_SHOT_DIR` — xcodebuild strips that prefix and sets the
rest on the runner. A bare `M1_SHOT_DIR` in the invoking shell never arrives and the tests
silently fall back to `/tmp`.

## Card contrast — amber against the flat card background (2026-08-02)

**#93 deleted `ProvisionalBadge`** (the fast answer is now `CardStatus.refining`'s strip —
icon, word and the gate's own tolerance, where the badge was a triangle to decode). The
numbers below are why that strip can be plain amber text: at 4.71:1 worst case it clears AA
for text, not just 1.4.11's 3:1 for the icon beside it, so the marking no longer needs its own
opaque disc. `CardStatus.tint` cites this section.


Superseded by M53 (layout A): the per-station `stationGradient`/`gradientTrios` this section
used to warn about are deleted — every card background is now flat `SN.cardFill` (≈5% white)
composited over the list's `SN.canvas`/`SN.canvasGlow` radial ground, so there is no longer a
12-trio worst case to chase. The badge kept its own opaque chrome (amber on an `SN.canvas` disc
with a full-strength amber ring) for the gradients' sake; against the flat fill that measured
below, bare coloured text clears the bar on its own.

Composited card background ranges `#121E35` (deep in the list, near `SN.canvas`) to `#162C4A`
(top of list, near the brighter `SN.canvasGlow`). New amber `#EF6F4A` against that range is
**4.71:1–5.59:1** — clear of WCAG 1.4.11's 3:1 for non-text either way. The glyph-on-disc
contrast (amber icon on the `SN.canvas` disc, 6.25:1) doesn't depend on the card background and
was never the tight number. The prose the badge replaced lives on the detail view's amber card,
which has a controlled background and can afford it.

## CLI vs Xcode GUI — SPM cache isolation (2026-07-31)

CLI builds (testflight.sh and any agent-run `xcodebuild`) must pass
`-clonedSourcePackagesDirPath build/SourcePackages` — a repo-local, gitignored SPM
cache. Without it, a CLI resolve racing the Xcode GUI resolver corrupts the shared
`~/.../org.swift.swiftpm` artifact cache on the MapLibre binary zip ("already exists
in file system" → Resolving Package Graph Failed in Xcode). If the GUI shows that
error: quit Xcode, delete the artifact dir under
`~/Library/Caches/org.swift.swiftpm/artifacts/`, File → Packages → Reset Package
Caches, rebuild.
