# JavaScript fit reference

These frozen JavaScript artifacts are the oracle for FitValidation and the fill/patch pipelines. The app uses the Swift fit in Neaps through `Slackwater/ChsFitter.swift` and bundles no JavaScript.

`capture.mjs` records golden results from the committed IWLS recording for the native fitter's regression tests. Run it from the repository root with `node tools/chs-reference/capture.mjs`. The held-out Victoria and Dodd tests also run the native fitter; FitValidation runs the JavaScript oracle.
