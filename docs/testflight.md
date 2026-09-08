# TestFlight — headless signing & upload

Set up 2026-07-30 under Bryan's Apple account (Team `R3H8DPTV9C`). Run `scripts/testflight.sh`
to archive + upload; everything below is the one-time state it relies on, and how to rebuild it.

## The pieces

| Piece | Where | Notes |
|---|---|---|
| ASC API key | `~/.appstoreconnect/private_keys/AuthKey_VM6W5HP585.p8` (Key ID `VM6W5HP585`, Issuer `69a6de81-5896-47e3-e053-5b8c7c11a4d1`, role App Manager) | Signs API requests + authenticates the upload. Re-mint at App Store Connect → Users and Access → Integrations |
| Bundle ID (app) | `org.openwaters.slackwater` (ASC id `D696FS7JD3`) | Registered in ASC (one-time, 2026-07) |
| Bundle ID (appex) | `org.openwaters.slackwater.widgets` (ASC id `BC99FA5V78`) | Registered 2026-08-23 for the widget extension. An appex needs its own bundle ID **and its own profile** — the app's covers neither |
| App Group | `group.org.openwaters.slackwater` | Shared by app + appex (`Slackwater.entitlements`, `SlackwaterWidgets.entitlements`); how the widget reads the fitted model and the Premium entitlement. **Created in the developer.apple.com UI — `/v1/appGroups` is a 404, App Groups are not in the ASC API at all** |
| Distribution identity | `slackwater-ci.keychain-db` — "Apple Distribution: Bryan Clark (R3H8DPTV9C)", expires 2027-07-30 (cert `D5456R8W23`) | Key generated locally (openssl CSR → `asc.mjs create-cert`); keychain password in `~/.appstoreconnect/ci-keychain-pass` |
| Provisioning profiles | "Slackwater App Store" (`JZRK3RW824`) **and** "Slackwater Widgets App Store" (`8395577WG2`), both re-minted 2026-08-23 and installed in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` under their UUID filename | `asc.mjs create-profile <bundleIdentifier> D5456R8W23 <out> [profileName]` — the name defaults to "Slackwater App Store", so the appex **must** pass its own or it deletes the app's profile and mints a duplicate wearing the app's name. **Both are needed**, and both must post-date the App Groups capability: a profile minted before a capability was added carries an empty `application-groups` array and the archive fails with entitlement errors. The predecessor `LF393ZYMCC` (2026-07-30) was replaced because it predated widgets |
| Signing config | `project.yml`: Release = manual signing, "Apple Distribution" + the profile; Debug stays automatic | |

## Why the dedicated keychain (the gotcha that cost the afternoon)

Non-GUI sessions (agents, launchd, ssh) see the **login keychain as locked** — codesign fails
with `errSecInternalComponent`, `-allowProvisioningUpdates` cloud signing dies with "User
interaction is not allowed", and `set-key-partition-list` on the login keychain doesn't help
because the lock, not the ACL, is the blocker. The fix is the CI-standard one: a dedicated
keychain whose password lives on disk, unlocked by the script per run, holding a distribution
identity minted through the ASC API (no Xcode sign-in anywhere). Cloud-managed signing is never
used; certificate renewal (2027-07) = new CSR → `asc.mjs create-cert` → import → new profile.

## Tester groups

| Group | Kind | Gets builds | Link |
|---|---|---|---|
| Nightly | internal (`hasAccessToAllBuilds`) | every upload, automatically, no review | — |
| Friends & Family | external, public link | only what `asc.mjs promote` adds, **after Apple beta review** | https://testflight.apple.com/join/HK7mHF19 |
| OSS and Externals | external, public link | same — and this is the link `slackwater.xyz` publishes as its download button (`src/routes/index.tsx`), so a release that skips it leaves the public page on the previous build | https://testflight.apple.com/join/FCSS4w8s |

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
`/v1/bundleIds` is a **prefix** match: it returns `org.openwaters.slackwater` *and*
`org.openwaters.slackwater.widgets`, appex first. `create-profile` took `data[0]`,
so the first mint after the appex was registered produced a profile **named**
"Slackwater App Store" and **bound to the widget's bundle id** — success message,
right name, wrong profile. Fixed by matching the identifier exactly; the check
above is what caught it.

**Favourites went to iCloud (#134) and the app target gained
`com.apple.developer.ubiquity-kvstore-identifier`.** Same drill, with one
difference: iCloud *does* have an API where App Groups does not. `POST
/v1/bundleIdCapabilities` with `capabilityType: ICLOUD` and `ICLOUD_VERSION:
XCODE_6` against bundle id `D696FS7JD3` returns 201. Key-value storage needs no
iCloud *container*, so there is nothing to create and nothing to assign, and only
the app target is affected — the appex reads favourites out of the App Group,
never out of KVS. Done 2026-08-23: the app bundle id now reads `IN_APP_PURCHASE,
APP_GROUPS, ICLOUD`, and "Slackwater App Store" was re-minted (`CN6WHP3433`,
UUID `5c858630-7d48-4bea-a803-8bf938b4ec43`) so it carries
`com.apple.developer.ubiquity-kvstore-identifier => R3H8DPTV9C.*`. The widgets
profile is untouched; the appex gained no entitlement. Proven rather than
assumed this time: `xcodebuild archive` succeeded on the new profile and the
signed app carries `com.apple.developer.ubiquity-kvstore-identifier =>
R3H8DPTV9C.org.openwaters.slackwater` (`codesign -d --entitlements`). That is
the check the merge gate cannot do for you.

**Delete the old file when you re-mint, or the name stops identifying a profile.**
Two profiles named "Slackwater App Store" were installed side by side until this
one — `ab3c7463…` (carrying the App Group) and `fb99187e…` (the 2026-07-30
predecessor, which did not). `PROVISIONING_PROFILE_SPECIFIER` matches on *name*,
so with a duplicate installed which one an archive picks is not something this
repo controls, and the failure looks like a missing entitlement rather than a
stale file. Both are backed up in `~/.naturali/profile-backups/2026-08-23/`. The
`security cms -D` loop above prints one line per installed profile; a repeated
name in that output is the bug.

## Cadence

Build 35 adds Associated Domains for `applinks:slackwater.xyz`. The app's
distribution profile was refreshed on 2026-09-05: `LNV5YA445J`, UUID
`d167dc60-6125-4498-9022-5ab20b16bbf1`. Its decoded entitlements include
`com.apple.developer.associated-domains => *`, the existing App Group, and
iCloud key-value storage. The old `5c858630…` profile was moved out of the
installed profiles directory to `/private/tmp/slackwater-build35-previous-profile.mobileprovision`
to prevent duplicate-name selection. The widgets profile is unchanged.

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

Capture the versioned recording once per machine with
`node scripts/iwls-fixtures.mjs refresh`. That is the only fixture command that
downloads. Unit-containing modes automatically run the offline
`node scripts/iwls-fixtures.mjs prepare`, which validates and stages the recording
or fails with the setup command. The default recording lives at
`~/Library/Caches/SlackwaterTests/iwls`, shared by the same macOS account's
checkouts and linked worktrees. `SLACKWATER_FIXTURE_DIR` overrides it. Refresh is
always explicit; routine runs never replace the recording.

```sh
./scripts/test.sh                                  # offline unit + UI, iPhone
./scripts/test.sh --full                           # offline both sims + exhaustive data check
./scripts/test.sh --unit                           # unit target only, one simulator
./scripts/test.sh --live                           # real-IWLS smoke only, one simulator
SHOT_DIR=/tmp/shots ./scripts/test.sh              # where the UI tests save screenshots
SLACKWATER_SIMS='SimA,SimB' ./scripts/test.sh      # run on other devices
```

### One test run at a time (2026-08-02)

The self-hosted runner is this same Mac, so CI and a local run can overlap. When
they do, they SIGKILL each other's test runner: every UI test in the losing run
reports `Test crashed with signal kill` with **zero assertion failures**. It reads
as a real failure and is not one. If you see that signature, check whether
something else was testing at the same time before you debug the code.

Five CI runs died this way on 2026-08-02 — 3, 6 and 16 UI tests at a time — and the
last of them had CI and the local run on *different simulator devices*, so device
separation does not avoid it. The exact kill mechanism was never pinned down; the
CoreSimulator logs had already rolled off. The correlation with overlap was 5 for 5.

So `scripts/test.sh` takes a machine-wide `lockf(1)` lock and whoever arrives second
waits. Your local run can therefore sit for up to a full CI run before it starts —
it prints a line when it's waiting. The lock lives in the kernel, so a killed or
cancelled run releases it and nothing wedges.

Two smaller pieces of the same story:

- `SLACKWATER_SIMS` lets CI run on its own devices (`SlackwaterCI-iPhone` /
  `SlackwaterCI-iPad`, created by the workflow, same device types as the reference
  pair). That doesn't prevent the kill, but it does stop results bleeding between
  overlapping sessions — CI once reported a failing test that didn't exist on the
  branch under test.
- UI modes write screenshots to `/tmp/slackwater-shots` unless `SHOT_DIR` says
  otherwise, CI included, so a local run and CI overwrite each other's images.

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
