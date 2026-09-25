# CHS fitting references

The app uses native Swift fitting with per-sample astronomy. The frozen CHS bundle and glue in this directory remain offline references for field-generation tools and historical validation; they are not app resources.

`capture.mjs` uses the committed IWLS recording, the app's 23-constituent basis, and the same training/holdout splits as `IwlsFixtureTests`.

```sh
node tools/chs-reference/capture.mjs
node tools/chs-reference/capture.mjs /path/to/engine/packages/engine/dist/index.js
```

The first command captures the frozen bundle in `chs-fit-golden.json`. The second captures the built `@slackwater/engine` package in `chs-fit-parity.json`; build the engine from openwatersio/slackwater#341 first. Both files live in `SlackwaterTests/Fixtures`. The tests compare native coefficients tightly with the per-sample TS reference and compare held-out prediction error with the frozen CHS baseline. Do not regenerate the baseline from the new fitter.
