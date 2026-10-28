# CHS current fit validation

The shipping recipe and year-round measurement are maintained in [the engine's CHS current validation record](https://github.com/openwatersio/slackwater/blob/main/docs/validation/chs-currents.md). [CHS current validation](https://github.com/openwatersio/chs-current-validation) publishes the evidence releases cited by the database's `chs_fit` records.

The app reads those dispositions through `tools/gen-chs-gates.mjs`. Its pinned engine revision, recipe stamp and the full stamp published by each accepted evidence release are recorded in `tools/chs-current-recipe.json`; generator tests reject unknown evidence and evidence from another recipe. See [the CHS data model](../chs-data-model.md#5-what-validated-means-here) for model compatibility and the meaning of the displayed bound.

`tools/FitValidation` retains file-input mode for the fill and patch pipelines. Its frozen JavaScript reference remains required by those pipelines; it does not decide which CHS gates ship.
