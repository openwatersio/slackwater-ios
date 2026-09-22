# Release notes

One file per version, named for its `MARKETING_VERSION`. `scripts/testflight.sh` posts `docs/release-notes/$VERSION.md` as the build's TestFlight "What to Test" and as the body of the `v$VERSION` GitHub release, so the file is the single source both read.

## Format

1. The version line, which gains its build number when a build is picked.
2. A blank line.
3. One sentence naming what the version is about.
4. Highlight bullets, each opening with `·`.
5. A closing paragraph starting `Worth testing:`.

## The App Store takes the highlights only

App Store Connect's "What's New" wants the highlights without the beta instructions. Everything between the version line and `Worth testing:` is that text:

```sh
sed -e '1,2d' -e '/^Worth testing:/,$d' docs/release-notes/1.14.0.md
```

So `Worth testing:` starts its own line and stays last, and anything a beta tester needs but an App Store reader does not belongs inside it — build numbers, simulator caveats, what to watch for in a specific lane.

The first App Store version introduces the app rather than listing changes, and its copy lives in [App Store metadata](../appstore-metadata.md) instead.
