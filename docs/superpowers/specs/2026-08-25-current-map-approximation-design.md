# Current map approximation

**Status:** approved in chat 2026-08-25. Supersedes the Dodd stage-aware patch
prerequisite in `2026-08-25-dodd-vector-streaks-design.md`; retains its certified-field
streak design where coverage exists.

## Product boundary

The map is an at-a-glance approximation of current speed and direction. It is not a
passage-planning instrument. The station detail view remains authoritative for predicted
speed, slack timing, and transit decisions.

The map must therefore prefer a useful local indication over pretending to know the full
water field. A station-local animation may show what the fitted station predicts near its
position, but it must not paint a bounded current area unless the field geometry passed
the existing certification pipeline.

## Evidence and decision

Dodd's fitted current model is valid, but neither available 10 m bathymetry source can
certify a drawable grown patch:

- GSC West Coast DEM: corrected anchor passes placement sensitivity, but the stable range
  collapses to one transect (`[20,20]`) and packs zero cells.
- CHS NONNA-10 tile `NONNA10_4910N12390W.tiff`: resolves a 50 m throat, but the 1.3x flare
  rule initially leaves one transect; the spec-permitted 1.6x diagnostic includes adjacent
  80 m sections, which then fail the unchanged 10% sensitivity bar by 12.6–32.9%.
- The stage interpolation itself is not the constraint: withheld half-metre heights pass
  with 0.9164% maximum error.

No bar is relaxed and no singleton transect is invented into an area. The stage-aware
patch implementation is not shipped because it has no surviving consumer.

## Rendering design

### Certified coverage

Where `FillField` or a shipped `PatchField` contains the coordinate, advect streaks through
the local sampled vector. Patch sampling wins over backdrop sampling. Leaving coverage
recycles the particle; absence never becomes zero current.

### Dodd station-local fallback

Dodd alone gets a compact visual cluster centered on its corrected hydraulic-control
position. It consumes the fitted Dodd signed current model directly:

- evaluate signed speed once per minute;
- use the fitted flood direction for positive flow and its reciprocal for negative flow;
- constrain roughly 12 deterministic streaks to a 300–400 m long, narrow visual envelope;
- use the existing speed ramp on each streak head, reaching `#c93a32` at the high-speed
  ceiling, with a short foam-white tail showing motion direction;
- scale legible animation speed from current magnitude, while making no wall-clock travel
  claim;
- omit the cluster when the fitted model is unavailable;
- freeze advancement, but retain visible direction marks, under Reduce Motion.

The envelope is a particle lifecycle bound, not rendered geometry. It has no fill, outline,
polygon, or chart legend suggesting certified spatial extent.

No other uncertified station receives this fallback in this change. Add another only after
its fitted model, position, and local axis are explicitly reviewed.

## Integration

Graduate the existing MapLibre GeoJSON particle spike. Reuse its strong source retention,
`.common` timer, zoom/visible-bounds culling, deterministic particle placement, and local
tangent coordinate math. Do not add Metal, a dependency, a setting, or a launch-only
shipping path.

The existing current-fill toggle owns speed fill and streaks. Streak layers sit above the
current fill and below land/station labels. Tide markers remain static.

## Tests and acceptance

- Point-in-triangle field sampling returns the existing cell's speed/bearing; patch wins;
  absent coverage returns nil.
- Pure advection follows local bearing, retains bounded curved history, and recycles on nil.
- Dodd fallback evaluates its fitted model once, reverses on ebb, stays inside its visual
  envelope, and disappears without a model.
- At a pinned Dodd peak, the head color is `#c93a32` and one animation step moves along the
  expected set direction.
- Reduce Motion freezes advancement without hiding the direction marks.
- Toggle-off style remains free of streak sources/layers; no state-pin color expression is
  reused.
- Run focused and full app suites, then record Dodd at peak on an iPhone simulator and
  inspect direction, density, label overlap, and frame behavior.

## Delivery

Keep the reviewed `station-corrections` hydraulic-control correction as its own PR. Build
the renderer from current `origin/main` in a fresh `slackwater-ios` worktree; do not base it
on the unshipped stage-aware patch commits. Open an internal PR and do not merge it.

## Out of scope

- Passage timing or transit recommendations on the map.
- A Dodd filled polygon or claimed current-area boundary.
- Relaxing bathymetry certification.
- Stage-aware patch bundle support without a certified consumer.
- Extending station-local fallbacks beyond Dodd.
- Dent Rapids and Beazley Passage (#147), or the map timeline scrubber (#159).
