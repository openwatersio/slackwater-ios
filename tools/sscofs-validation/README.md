# SSCOFS validation tools

This harness fits SSCOFS surface currents and compares them with official station events. The production [fill pipeline](../fill-pipeline/README.md) imports its projection, certification, and fitting helpers. Keep one implementation of those rules.

## Rules

A current prediction must pass the [CHS current acceptance criteria](../../docs/validation/chs-currents.md). The map fill has a separate speed-only contract: a station passes when its best scoreable element has median peak-speed error ≤ 0.5 kn. Published extrema below 0.75 kn are unscoreable. An element is certified only when its nearest scoreable station is passing and within 3 km; a nearer failure masks it. Record sensitivity at 2, 3, and 5 km. Fill certification never grants slack-timing authority or permission to use green.

`prune_proof.py` uses NumPy least-squares fits for sizing only. Its 23-constituent basis comes from the shipping bundle; per-axis R² must reach 0.8, and a constituent survives when either axis clears the larger of 2% of that axis's maximum amplitude and 0.005 kn. The production pipeline verifies survivors with the shipping JavaScript fitter. The bundle budget is 40 MB.

The 60-day box validation measured 2,004 station-element pairs. None of 53 scoreable stations passed all five current bars. This is why SSCOFS fill carries speed context only; slack timing belongs to validated stations. The [recorded measurements](https://github.com/openwatersio/slackwater-ios/blob/47e9c59971924dfa0a637ac3df395704a88f6b52/spikes/sscofs-field/RESULTS.md) remain in Git history. Their report label `210d` refers to the harness's output slot; that experiment supplied only 60 days. Its naive bundle-size extrapolation is superseded by the mesh-capped calculation in `prune_proof.py`.

## Reproduce a box validation

Run from this directory. Python script shebangs use `uv` to supply their dependencies. Matrix scoring also needs Swift and `jq`.

```sh
./mesh_subset.py
./fetch_corpus.py 60
./truth_stations.py
./make_samples.py
./run_matrix.sh
./report.py
./certify.py
./prune_proof.py
```

The mesh, corpus, truth, sample, result, and certification directories are ignored. `run_matrix.sh` resumes from pair markers and accepts `MATRIX_INDEX` for a subset; it uses `/tmp/fit-validation/reports`, so do not run it concurrently with another matrix. Generated `RESULTS.md` is disposable. Keep release evidence with the bundle's provenance or in the PR.

## Offline checks

```sh
uv run --with pytest,numpy,requests pytest -q test_certify.py test_project.py test_prune.py
```

The fill bundle's historical `constituent_basis_source` may name `spikes/sscofs-field/prune_proof.py`; it identifies the source used for that build. The maintained implementation is `prune_proof.py` here.
