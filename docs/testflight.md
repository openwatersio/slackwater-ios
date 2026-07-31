# TestFlight — headless signing & upload

Set up 2026-07-30 under Bryan's Apple account (Team `R3H8DPTV9C`). Run `scripts/testflight.sh`
to archive + upload; everything below is the one-time state it relies on, and how to rebuild it.

## The pieces

| Piece | Where | Notes |
|---|---|---|
| ASC API key | `~/.appstoreconnect/private_keys/AuthKey_VM6W5HP585.p8` (Key ID `VM6W5HP585`, Issuer `69a6de81-5896-47e3-e053-5b8c7c11a4d1`, role App Manager) | Signs API requests + authenticates the upload. Re-mint at App Store Connect → Users and Access → Integrations |
| Bundle ID | `org.openwaters.slackwater` (ASC id `D696FS7JD3`) | Registered via `scripts/asc.mjs register-bundle` |
| Distribution identity | `slackwater-ci.keychain-db` — "Apple Distribution: Bryan Clark (R3H8DPTV9C)", expires 2027-07-30 (cert `D5456R8W23`) | Key generated locally (openssl CSR → `asc.mjs create-cert`); keychain password in `~/.appstoreconnect/ci-keychain-pass` |
| Provisioning profile | "Slackwater App Store" (`LF393ZYMCC`), installed in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` | Recreate with `asc.mjs create-profile org.openwaters.slackwater D5456R8W23 out.mobileprovision` (idempotent — deletes stale same-name profile first) |
| Signing config | `project.yml`: Release = manual signing, "Apple Distribution" + the profile; Debug stays automatic | |

## Why the dedicated keychain (the gotcha that cost the afternoon)

Non-GUI sessions (agents, launchd, ssh) see the **login keychain as locked** — codesign fails
with `errSecInternalComponent`, `-allowProvisioningUpdates` cloud signing dies with "User
interaction is not allowed", and `set-key-partition-list` on the login keychain doesn't help
because the lock, not the ACL, is the blocker. The fix is the CI-standard one: a dedicated
keychain whose password lives on disk, unlocked by the script per run, holding a distribution
identity minted through the ASC API (no Xcode sign-in anywhere). Cloud-managed signing is never
used; certificate renewal (2027-07) = new CSR → `asc.mjs create-cert` → import → new profile.

## Cadence

- Bump `CURRENT_PROJECT_VERSION` in `project.yml` per upload (App Store Connect rejects reused
  build numbers per version); `MARKETING_VERSION` per release.
- App record ("Slackwater — Tides & Currents") + tester management stay in the App Store
  Connect UI — records can't be created via the public API.
- Export-only variant (signed .ipa, no upload): `build/exportOptions.plist` with
  `destination: export` — what the first proof run used.

## CLI vs Xcode GUI — SPM cache isolation (2026-07-31)

CLI builds (testflight.sh and any agent-run `xcodebuild`) must pass
`-clonedSourcePackagesDirPath build/SourcePackages` — a repo-local, gitignored SPM
cache. Without it, a CLI resolve racing the Xcode GUI resolver corrupts the shared
`~/.../org.swift.swiftpm` artifact cache on the MapLibre binary zip ("already exists
in file system" → Resolving Package Graph Failed in Xcode). If the GUI shows that
error: quit Xcode, delete the artifact dir under
`~/Library/Caches/org.swift.swiftpm/artifacts/`, File → Packages → Reset Package
Caches, rebuild.
