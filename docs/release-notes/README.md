# Release notes

One file per version, named for its `MARKETING_VERSION`. `scripts/testflight.sh` posts `docs/release-notes/$VERSION.md` as the build's TestFlight "What to Test" and as the body of the `v$VERSION` GitHub release, so the file is the single source both read.

## Format

1. The version line, which gains its build number when a build is picked.
2. A blank line.
3. What the version is about — one sentence and highlight bullets opening with `·` for an update, an introduction for a first release.
4. A closing paragraph starting `Worth testing:`.

## The App Store takes the highlights only

App Store Connect's "What's New" wants the highlights without the beta instructions. Everything between the version line and `Worth testing:` is that text, and `scripts/asc.mjs localization` pushes it ([App Store releases](../appstore.md)). An app's first version has no What's New field, so 1.14.0's notes stop at TestFlight and the GitHub release:

```sh
sed -e '1,2d' -e '/^Worth testing:/,$d' docs/release-notes/1.14.0.md
```

So `Worth testing:` starts its own line and stays last, and anything a beta tester needs but an App Store reader does not belongs inside it — build numbers, simulator caveats, what to watch for in a specific lane.

The listing reads What's New from this file rather than holding a second copy, so the listing and the build's notes cannot drift apart.
