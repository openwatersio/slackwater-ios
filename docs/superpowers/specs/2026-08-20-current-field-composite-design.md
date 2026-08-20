# The current field, composited — SSCOFS backdrop, station-grown patches, honest edges

**Status:** design, direction approved 2026-08-20 ("1 now / 3 possibly later", #57).
**Scope:** the data architecture that turns Slackwater's point predictions into a
renderable current *field*. Rendering itself stays with #57's particle layer — this
spec decides what feeds it, not what it draws.
**Supersedes:** the "no viable dataset" conclusion of #99 and `docs/chs-data-model.md`
§6's generalization, per the measurement in
[#99 (comment)](https://github.com/openwatersio/slackwater-ios/issues/99#issuecomment-5358204673).
§6 is amended in this branch to match.

## Why now

#99 killed the field on one measured mesh (`ne_pac4`, ~493 m at Dodd Narrows, 2.62 kn
where CHS publishes 9.5) and generalized: *every* gridded model is ~500 m in the Gulf
Islands, so the passes are a station problem. Re-measured 2026-08-20 against NOAA's
operational SSCOFS mesh — same method, same gates, same-24 h window against official
predictions:

| Pass | mesh spacing | official max | SSCOFS max | ratio |
|---|---|---|---|---|
| Active Pass | 479 m | 4.1 kn | 4.10 kn | 1.00 |
| Deception Pass | 117 m | 4.98 kn | 4.62 kn | 0.93 |
| Tacoma Narrows | 250 m | 4.27 kn | 3.85 kn | 0.90 |
| Seymour Narrows | 396 m | 9.16 kn | 7.85 kn | 0.86 |
| Dodd Narrows | 516 m | 6.2 kn | 1.46 kn | **0.24** |

The #99 failure is real but *local*: sub-mesh throats (Dodd-class, 60–80 m against
~500 m elements) fail in any mesh, forever. Everywhere else the field exists,
validates, is public domain, and covers the Canadian Strait of Georgia to 51 °N —
which no other clean-licence source does.

One 24 h neap-day comparison is evidence, not acceptance. The go/no-go for every
region is §4's harmonic-fit validation, on the app's own bar.

## 1. Architecture — three tiers, one rule

**Render only what passed validation. Everything else is visibly absent.**

| Tier | Source | Where it renders |
|---|---|---|
| Backdrop | Harmonic constants we fit per SSCOFS mesh element | Elements in regions certified against the station truth set (§4) |
| Grown patches | Validated gate/station harmonics × bathymetry continuity (§5) | Inside sub-mesh passes with a validated gate, and only there |
| No data | — | Neutral/absent, never calm — the existing `MapScreen` rule, now with a visible domain edge |

A grown patch always outranks backdrop where both exist (the #9 rule — a field is a
backdrop that yields to stations — kept verbatim). The #57 particle layer consumes all
tiers through one interface, shaped by what the animator actually needs (agreed with
the #57 session, 2026-08-20): a **provider returning oriented flow samples evaluated
at time t** — `[(center, bearingDeg, signedKn, extent)]`. Three properties are load-
bearing and fixed here:

- **Evaluate-at-t, not static config.** The animator re-queries on its ~60 s stamp
  (`Gate.speedStamp`); that call site is the seam. Bearing comes back from the same
  call as speed, so a harcon ellipse (bearing = f(t)) or a field sampler slots in
  without a renderer change.
- **N samples per source, not one per gate.** A grown patch or backdrop swatch is just
  many samples; the animator already iterates patches.
- **Absence stays absence.** A provider returns no sample for anything unvalidated —
  no quality/confidence field on the sample. The renderer never makes a validity
  decision; the `chsPinTones` contract, kept.

The renderer does not know which tier it is animating.

## 2. Backdrop pipeline (offline, one-time per release, Studio)

1. **Corpus.** Surface u/v per element from `noaa-nos-ofs-pds` nowcast fields files via
   HTTP ranged reads (h5py + fsspec; verified ~14 MB/hourly file; netCDF4 `#mode=bytes`
   does not work). 190 days → ~64 GB transferred, hourly resolution. 190 days
   separates K1/P1 and S2/K2 outright (no inference) and averages out weather-driven
   residual circulation, which nowcasts contain and a tidal product must not.
2. **Fit.** The existing 23-constituent basis, per element, on u and v independently —
   `ChsFitService` already concedes the 1D projection "is linear, so equivalent to a
   full 2D fit projected onto the same axis"; here we keep both axes.
3. **Clip & prune.** Drop elements outside the rendering domain (the mesh reaches the
   open shelf; we don't), drop constituents below an energy floor per element, quantize.
   Naive full-mesh/full-basis is ~160 MB; the budget is **≤ 40 MB** in the bundle.
   Format decided by measurement in the spike, not here.
4. **Version.** Constants are stable between refits; refit is a release-time decision,
   not a sync. Fitted-model-does-not-expire semantics carry over from CHS fits.

## 3. Spike first (the #57 pattern)

Before committing to the full pipeline: **60-day corpus over one box** (southern Gulf
Islands + San Juans — contains validated CHS gates, dense NOAA stations, Active Pass
at ratio 1.00 and Dodd at 0.24, so both outcomes are represented). Fit, validate
against every truth station in the box, measure the error distribution and the
per-element artifact size. Decision gates:

- median peak-speed error at truth stations in *certifiable* sub-regions ≤ 0.5 kn
  (the existing bar, `spikes/chs-currents-fit/README.md`);
- Dodd-class stations correctly *fail* and mask their neighbourhood (the gate must
  prove it rejects, not only that it accepts);
- extrapolated bundle cost ≤ 40 MB.

Pass → Phase B (full domain, 190 days). Fail → the composite degrades to grown
patches only, and this spec's backdrop sections are marked Plan B, global-coverage
style.

## 4. The validation gate, generalized

The certification unit is a **region** (contiguous element neighbourhood), not the
whole field:

- Every truth station (842 NOAA + fitted/derived CHS gates) grades the elements within
  its neighbourhood: fit the model constants' prediction against the station's, on the
  shipping bar (peak speed, slack timing).
- A region ships only if its graded stations pass and none fail. Ungraded regions far
  from any truth station ship only if enclosed by passing regions of the same water
  body — otherwise they are no-data. Exact adjacency rule to be fixed in the spike.
- The mask is computed offline and shipped as geometry; the app never decides
  trustworthiness at runtime.

## 5. Grown patches (sub-mesh passes)

For a pass with a validated gate but no resolvable mesh: grow the field from the gate.

- **Speed:** short-channel continuity — `|u|(x) = |u|_gate · A_gate / A(x)`, cross
  sections from bathymetry. Valid because every Salish pass is 1–2 orders of magnitude
  inside the L ≪ λ/4 (≈250 km for M2) criterion; transport is conserved along the
  confined channel.
- **Direction:** depth-weighted Laplace solve on the channel polygon, no-flux banks,
  unit flux at the gate section (the operator NOAA VDatum/TCARI uses to anchor fields
  to stations). Thalweg tangent is the acceptable cheap fallback for arrows.
- **Bounds, hard:** patch terminates at any junction or side embayment (transport
  splits), and ~1 channel-width past each mouth (Stommel–Farmer jet/sink asymmetry).
  Computed offline; shipped as polygon + per-vertex scale/direction; the runtime
  evaluates the gate harmonic and multiplies.
- **NOAA stations:** `harcon.json` tidal ellipses (major/minor/azi per constituent,
  verified against the live API) reconstruct true 2D u/v at type-H stations — patches
  there get a time-varying axis, not a fixed bearing.
- **Bathymetry:** CHS NONNA (clause 7: commercial derivatives permitted; verbatim
  notice required; raw tiles never ship; source tiles deletable on licence
  termination — derived cross-sections are ours) and NOAA BlueTopo/CUDEM (public
  domain/CC0; check per-tile contributor restrictions).

A grown patch is a *derived* rendering of a validated prediction — same authority
class as the gate itself, labelled depth-averaged. It never invents data in a pass
without a gate: Sechelt stays empty until it has a validated model, unchanged.

## 6. Licences & credits (all verified against primary sources, #99 comment)

| Source | Status | Obligation shipped in About/credits |
|---|---|---|
| SSCOFS output | Public domain (17 USC §105, NODD), incl. over Canadian water | Attribution requested; no NOAA-endorsement implication; "model guidance" mirrored by our planning-not-navigation disclaimer |
| CHS NONNA | Clause 7 derivative products | Verbatim CHS notice |
| NOAA BlueTopo/CUDEM | Public domain / CC0 | Acknowledgement |
| NOAA harcon | Public domain | — |

SalishSeaCast (Apache-2.0) and ECCC CIOPS-SalishSea (commercial explicitly granted)
are validated fallbacks/cross-checks, not shipped sources — recorded so nobody
re-derives them.

## 7. Out of scope, deliberately

- **Discovery Islands FVCOM run** (the "3 later"): Zenodo CC-BY mesh, 27 m at Seymour,
  full-year 2019 boundary forcing (corrected from #99's "35 days"), exact FVCOM 4.1
  source shipped, ~$100–300 cloud for the validation run. Trigger: Seymour-region
  backdrop + patch fails its bar or reads poorly. Prerequisite: Chen email or SCHISM.
- **Timeline scrubber:** #57 deferred it because per-gate "now" is self-contained.
  A shipped backdrop is the condition that makes it worth building; still not this spec.
- **Rendering decisions** (particle density, patch styling, zoom thresholds): #57's.

## 8. Success criteria

1. Every rendered field pixel traces to either a certified region (§4) or a validated
   gate's grown patch (§5). Enforced by construction: the app ships no other data.
2. The spike's certifiable sub-regions meet the ≤ 0.5 kn median peak-speed bar; Dodd
   Narrows' neighbourhood is masked by the gate, and its grown patch shows ~9.5 kn
   springs from the CHS-fitted gate model, not 1.46 kn from the mesh.
3. Bundle delta ≤ 40 MB; everything works offline after sync, per app baseline.
4. Field coverage visibly ends somewhere a user can see — no fade-to-calm anywhere.

## 9. Risks

- **Nowcast residual contaminates fits** in weakly tidal areas (e.g. mid-Georgia
  Strait drift): mitigated by 190-day span + an R² floor per element in the fit —
  elements whose variance isn't mostly tidal are no-data even inside a certified region.
- **SSCOFS mesh/model revisions** change element IDs between corpus and refit: pin the
  corpus window and mesh hash per release; the drift test pattern from
  `station-corrections` applies.
- **Cross-section sensitivity** at grown patches (A(x) from gridded bathymetry in an
  80 m throat): validate patch speed against the gate's own published values along the
  pass where CHS gives secondary stations; where sensitivity is high, shrink the patch
  rather than smooth it.
