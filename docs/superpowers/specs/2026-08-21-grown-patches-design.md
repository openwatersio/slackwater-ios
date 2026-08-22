# Grown Patches — bounded per-pass current fields from validated gate harmonics

**Status: DRAFT — awaiting owner review.**
Third and last piece of the composite current field
(`2026-08-20-current-field-composite-design.md` §5 is the physics sketch this
phase executes; Phase B `2026-08-20-fill-phase-b-design.md` shipped the backdrop
it composes with; the evidence trail is openwatersio/slackwater-ios#99).

**Inherited rulings, not reopened here:** render only what passed validation;
a patch renders only where a validated gate/station anchors it; patch outranks
backdrop; no green in any field ramp; timing/transitability authority stays
with gates/patches; absence stays absence; speed by short-channel continuity
`|u|(x) = |u|_gate · A_gate / A(x)` from bathymetry cross-sections; direction
by depth-weighted Laplace with thalweg tangent as the pre-authorized fallback;
hard bounds at junctions/side embayments and ~1 channel-width past each mouth;
patches feed both render channels through the existing seam family; where
cross-section sensitivity is high, **shrink the patch rather than smooth it**
(composite §9).

## 0. The anchor map — what the 23 masked stations actually are

The Phase B region run left 23 speed-FAIL stations whose 3 km neighbourhoods
are masked out of `fill-salish.bin`. They split into three buckets, and the
buckets decide the whole phase:

| Bucket | Stations | Patch? |
|---|---|---|
| Throats with a **validated harmonic anchor** | Dodd Narrows (chs-dodd-narrows, fitted, M47 PASS, 4.52 kn mesh error — worst in the matrix), Seymour Narrows (fitted 60 d final, best fit in the set), Porlier Pass (fitted PASS), Race Passage (fitted PASS), Gillard Passage (fitted PASS), Deception Pass (NOAA PUG1701, bundled published harmonics), Tacoma Narrows (NOAA PUG1526/PUG1527, bundled harmonics; PUG1524/PUG1528 also in-channel) | **Yes — this phase** |
| Throats **without** a harmonic anchor | Dent Rapids and Beazley Passage — both online-only gates (`fitDays: 0`), no model to evaluate offline | **No** — the standing rule ("no validated model → no patch", the Sechelt rule) already excludes them. Fitting them is a separate M47 decision, not this spec's. |
| **Open water** — no confined channel | Smith Island ×2, Discovery Island, Lawrence Point, Sinclair Island, Point Colville, Cattle Point, San Juan Channel S entrance, Skagit Bay, Juan de Fuca East, Guemes Channel, Upright Channel, Pickering Passage | **Never, under this mechanism.** Short-channel continuity needs banks; these have none (or no anchor gate). They stay masked/absent — the honest answer. |

A patch is a derived rendering of its anchor's validated prediction — same
authority class, labelled depth-averaged (composite §5). Nothing below invents
data past that.

## 1. Ship order

**Tier 1 (this phase):**

| Pass | Anchor | Side | Why |
|---|---|---|---|
| Tacoma Narrows | PUG1527 (anchor), PUG1524/1526/1528 as in-channel checks | US / BlueTopo | **Method-certification channel** — four published harmonic stations in series along one channel; the only place the A(gate)/A(x) law can be graded against independent truth at three points. Also a real constriction with real users. |
| Deception Pass | PUG1701; Yokeko Point PUG1629 in-pass check | US / BlueTopo | Second certification channel (one in-pass check) + the highest-value US gate. Exercises the whole US pipeline. |
| Dodd Narrows | chs-dodd-narrows | BC / NONNA | Worst mesh failure in the matrix (4.52 kn); the composite's own acceptance example (~9.5 kn springs, §8.2); Nanaimo inside route. |
| Seymour Narrows | chs-seymour-narrows | BC / NONNA | The definitive Inside Passage gate; best-fitted model in the set. |
| Porlier Pass | chs-porlier-pass | BC / NONNA | Gulf Islands ⇄ Strait of Georgia gate; 2.62 kn mesh error. |

Sequencing rule inside Tier 1: **the two US certification channels are built
and graded first; no BC patch ships until method certification (§6a) passes.**
The BC rapids have no in-channel check stations — CHS publishes exactly one
current station per rapids (confirmed against IWLS: nothing but water-level
neighbours near Dodd, Seymour, Porlier, Beazley, or Race) — so the method must
earn its trust where trust can be measured, then carry to the passes where it
can't.

**Tier 2 (same pipeline, next release):** Gillard Passage (junction-rich —
Yuculta complex bounds will keep it short), Race Passage.

**Deferred indefinitely:** Dent/Beazley (until fitted and M47-passed), Sechelt
(unchanged), minor NOAA-anchored channels (Guemes, Upright, Pickering, San
Juan S — mechanism would work; value doesn't justify them yet), all open-water
FAILs (forever, see §0).

## 2. Bathymetry pipeline — `tools/patch-pipeline/`

Sibling of `tools/fill-pipeline/`, same conventions: gitignored `data/` cache,
resumable stages, hard asserts, committed outputs only where licence-clean.

- **Sources** (owner ruling 2026-08-21; coverage source-of-record is the
  Open Waters Seascape index, openwaters.io/charts/seascape — if it isn't
  there, it doesn't exist). US: NOAA NBS via the
  `noaa-ocs-nationalbathymetry-pds` bucket — BlueTopo where published;
  **Navigation T&E 4 m BAG surfaces where not** (BlueTopo has no PNW
  coverage; verified against the live tile scheme). Public domain,
  per-tile contributor/licence check recorded in provenance. BC: **GSC
  Canada West Coast Topo-Bathymetric DEM 10 m** (NRCan, Open Government
  Licence – Canada, direct download from open.canada.ca — no portal
  account) as primary; CHS NONNA-10 (clause 7 — commercial derivatives
  permitted, verbatim notice required, tiles deletable on termination) as
  the fallback if the DEM reads too smooth in a throat (the width guards
  and sensitivity sweep decide). Tiles live only in `data/` — never
  committed, never bundled, regardless of source.
- **Per pass:** land/water mask at datum → channel polygon, trimmed by hand at
  the hard bounds (junction, side embayment, ~1 width past each mouth — the
  bounds are geometric judgment and get human review, §6b); thalweg as the
  deepest connected path; cross-sections perpendicular to the thalweg every
  ~100–200 m (spacing recorded per pass); `A(x)` by integrating depth across
  each section.
- **Datum:** areas computed at **mean water level** (Z0-ish), with the chart
  datum recomputation kept as a sensitivity axis (§6b) rather than a second
  shipping variant. In deep passes (Seymour ~90 m) the difference is noise; in
  shallow throats it is exactly the kind of instability the shrink rule
  handles. `ponytail:` single-datum areas; a tide-stage-dependent A(x,t)
  upgrade exists if certification says the physics needs it.
- **Committed derived artifact** (the licence-clean "ours"):
  `tools/patch-pipeline/passes/<slug>.json` — channel polygon, thalweg
  polyline, section positions + `A(x)` profile, datum, bounds rationale
  (which junction/embayment terminated each end), and provenance (source,
  tile ids + sha256, contributor-layer check, retrieval date). Reviewable in a
  PR, drift-testable against a re-derivation (the `station-corrections`
  pattern), and the sole input `pack` needs — the pipeline can lose its tile
  cache without losing the product.
- **Licence surfacing:** BC patches derived from the GSC DEM carry OGL –
  Canada attribution in the app About/credits, shipped in the same change
  as the first BC patch. The verbatim CHS NONNA notice is required only if
  the NONNA fallback actually feeds a shipped patch — composite §6 already
  reserves the slot for it.

## 3. Patch construction

- **Speed:** per-cell scale `s = A_gate / A(cell section)`. Scale is 1 at the
  anchor section by construction.
- **Phase:** the anchor's phase everywhere. Uniform phase along the channel
  *is* the L ≪ λ/4 criterion; the certification channels check it empirically
  (slack-timing error at the check stations, §6a) rather than assuming it.
- **Direction, v1:** section-normal / thalweg tangent per cell — the
  pre-authorized fallback. The Laplace solve is deferred with an explicit
  trigger: build it only if certification-channel bearings or the rendered
  arrows misread at mouths/bends. In a strip of sections perpendicular to the
  thalweg, the tangent field and the Laplace solution agree except near
  widenings — and patches end ~1 width past the mouth anyway.
- **NOAA anchors are treated exactly like CHS anchors:** signed speed on the
  station's flood/ebb axis. The harcon minor-axis/ellipse machinery is **not
  used**: inside a confined channel the banks constrain direction and the
  minor axis is noise; the composite's ellipse note matters where geometry
  doesn't constrain — and patches only exist where it does. (Recorded so
  nobody re-derives the need later.)
- **Cells:** the section strip triangulated into cells (two triangles per
  section interval), each carrying `scale` and `bearingDeg`. Blocky like the
  fill, no smoothing across cells — same honesty rule, same precedent.

## 4. Shipped format

One committed resource, `Slackwater/Resources/patches-salish.bin` + sidecar
JSON — the `fill-salish` format family (little-endian, f32 vertices, f16
payloads, sidecar carries offsets + provenance):

- **Sidecar header:** `format_version`, `region`, `generated`, `bin_sha256`,
  per-patch table: patch id (pass slug), anchor (`provider`,
  station/gate id), source `passes/<slug>.json` sha256, cell count, offsets.
- **Per patch, in the bin:** cell count, then per cell: 3 × (f32 lon, f32
  lat), f16 `scale`, f16 `bearingDeg`.
- Total for Tier 1 is a few hundred cells — **single-digit KB** against the
  40 MB shared budget. No per-patch files, no lazy-loading cleverness.
  `ponytail:` one bundle for all patches; more regions are more files, same as
  fill.

## 5. Runtime — `PatchField`

Mirrors `FillField`, consumes the same seam family; the renderer never learns
a new concept:

- `PatchField()` failable init (same failure honesty: bad header → no
  patches), `cells(at:in:) -> [FillCell]` — patch cells vend as ordinary
  `FillCell`s: polygon + `speedKn` + `bearingDeg`.
- **Evaluation:** per patch per call, evaluate the anchor once —
  CHS: `ChsModelStore.loadCurrent(id)` → `record.engineStation` →
  `speeds(from:to:step:)` one-second-window idiom; NOAA: `currents.json`
  record → same tail. Then per cell: `speedKn = |signed| × scale`,
  `bearingDeg = cell bearing`, +180° when the signed speed is ebb — the
  `setDegrees(signed:)` semantics, reused.
- **Absence stays absence:** a CHS anchor whose on-device fit hasn't completed
  vends no cells (structurally identical to how `ChsFitService` gates the gate
  cards — no new state, no flag). An online-only or absent gate was never in
  the bundle to begin with.
- **Channel 2:** patch cells double as oriented samples — centroid, bearing,
  signed kn, extent = local channel width from the section data. Additive
  method beside `cells(at:)`, per the Phase B forward note; same
  evaluate-at-t contract.
- **Composition:** patches draw **after** (over) the backdrop fill; no
  geometric clipping. The masked holes in `fill-salish.bin` already carve out
  each throat; the only true overlap is the mouth fringe where a patch meets
  certified elements, and draw order *is* the "patch outranks backdrop" rule.
  No smoothing across the seam, ever.

## 6. Validation

**(a) Method certification — runs once, gates the phase.** Build the Tacoma
and Deception patches; at every in-channel check station (Tacoma: PUG1524,
PUG1526, PUG1528 predicted from a PUG1527 anchor; Deception: Yokeko Point
PUG1629 predicted from PUG1701), grade the patch's prediction against the
station's own published-harmonic prediction using the **existing FitValidation
bars (M47: slack timing, extrema timing, ≤ 0.5 kn median peak speed)** — the
patch at a check station must read as well as a shipping gate, graded by the
same tooling, one implementation of the rule, never a fork. Skagit Bay SW of
Hope Island (PUG1628) is recorded as an informative far-field decay check,
not a bar. **Fail → the phase halts** and the fallback conversation is the
composite §7 Discovery-FVCOM path — not a loosened bar.

**(b) Per-patch certification — every patch, including the uncheckable BC
five:**
1. **Anchor identity** — scale = 1 at the anchor section (unit test).
2. **Sensitivity sweep** — recompute `A(x)` with sections shifted ±half a
   spacing, datum swapped MWL ↔ chart datum, and (where tiles overlap) the
   alternate bathy source; any cell whose speed moves more than
   max(10 %, 0.25 kn) at the anchor's spring peak is **truncated** — the
   patch shrinks to the stable core. Shrink, never smooth.
3. **Springs plausibility** — patch speed at the throat within ~15 % of the
   gate's published spring maximum (Dodd ≈ 9.5 kn — composite §8.2's number,
   finally cashed in).
4. **Bounds review** — the patch polygon overlaid on the chart, eyeballed by
   the owner: terminations at the intended junctions/embayments, nothing
   reaching into water the physics doesn't cover. Geometry is judgment;
   judgment gets a human.
5. **Drift** — regenerating `passes/<slug>.json` from pinned tiles must
   reproduce the committed artifact (hash compare, `station-corrections`
   pattern); tile hashes pinned in provenance.

**(c) Tests shipped with the code:** bundle round-trip, synthetic golden
(known scale × known anchor constituents at two instants), one real-bundle
golden cell pinned against this generation — the `FillFieldTests` shapes,
reused.

## 7. Success criteria

1. Method certification (§6a) passes at all four check stations on M47 bars.
2. The Dodd patch shows ≈ 9.5 kn springs from the CHS-fitted gate model where
   the mesh said 1.46 kn — composite §8.2, delivered.
3. Tier-1 bundle ≤ 100 KB (expected single-digit KB); 40 MB budget untouched.
4. Every patch cell traces to a committed `passes/<slug>.json` + a validated
   anchor; everywhere else absence is unchanged.
5. Bathymetry attribution ships in credits in the same release as the
   first BC patch (OGL – Canada for the GSC DEM; the CHS NONNA verbatim
   notice too iff NONNA-derived data ships).

## 8. Out of scope

Render layer and patch styling (#57's, both channels still unbuilt); the
Laplace direction solve (trigger recorded in §3); fitting Dent/Beazley/Sechelt
(separate M47 decisions); minor NOAA-channel patches; open-water FAILs;
Discovery-FVCOM (composite §7, unchanged trigger); tide-stage-dependent
A(x,t).

## 9. Risks

- **10 m bathymetry resolution (GSC DEM / NONNA) in a 60–80 m throat (Dodd):** ~6–8 depth cells
  across the narrows makes A(throat) the noisiest number in the phase — and
  it sits in the denominator at the *anchor*, so it cancels there (scale = 1)
  and matters most mid-patch. The sensitivity sweep is sized to catch exactly
  this; the failure mode is a shorter patch, not a wrong one.
- **Phase non-uniformity** at Deception's long eastern arm — the Yokeko check
  measures it; if slack timing fails there, the patch terminates west of
  Yokeko and the certification is re-run on the shorter patch (shrink rule
  applies to timing too).
- **Gate fit-state coupling:** BC patches are invisible until the gate's
  on-device fit completes — same UX truth as the gate cards today; accepted,
  not worked around.
- **Tile revision drift:** NONNA and BlueTopo re-issue tiles; pinned hashes +
  the drift test make a re-derivation a deliberate release-time decision,
  like the fill refit.

## Decision log (owner review — reply by number)

1. **Ship order** (§1): US certification pair first, then Dodd/Seymour/
   Porlier; Gillard + Race as Tier 2. Alternative considered: BC-first by
   user value — rejected because the BC passes cannot validate the method
   (no in-channel stations exist; confirmed against IWLS).
2. **Method certification gate** (§6a): no BC patch ships before Tacoma +
   Deception pass M47 bars at four check stations. This is the phase's
   go/no-go.
3. **Direction v1 = thalweg/section tangent** (§3), Laplace deferred with a
   named trigger. Alternative: build the Laplace solve now — rejected as
   speculative; the fallback is pre-authorized in the composite and the
   strip geometry makes the two nearly identical inside the bounds.
4. **One bundle, FillCell-shaped** (§4–5): patches vend through the frozen
   seam as ordinary cells + oriented samples; no new renderer concept.
   Alternative (samples-only) fails the "both channels" ruling.
5. **NOAA anchors as 1D signed axis** (§3): harcon ellipse machinery
   explicitly not used inside confined channels.
6. **Datum = MWL** with chart-datum as a sensitivity axis (§2), not a second
   variant.
7. **Dent + Beazley stay out** until someone chooses to fit them (§0) — the
   existing no-model rule decides this, but flagging since they're the two
   named rapids users will ask about. Tracked in #147.
