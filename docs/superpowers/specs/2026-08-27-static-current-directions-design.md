# Static current directions

**Status:** approved in chat 2026-08-27.

## Product boundary

Motion remains the target current-map language. Until a motion renderer meets a real-device
interaction and energy budget, the shipping map shows current speed as the certified colour
fill and current direction as static arrows. Station detail remains authoritative for speed,
slack timing, and transit decisions.

The map must stay fully usable while currents are visible. Pan and zoom take priority over
decorative motion.

## Static renderer

The current layer contains no animation timer and performs no per-frame GeoJSON updates.

- Keep the certified `FillField` and `PatchField` polygons, speed ramp, one-minute refresh,
  land clipping, and current pins.
- During the existing off-main one-minute evaluation, create one direction point at each
  evaluated cell centroid with its `bearingDeg` attribute.
- Put polygon and point features in the existing fill and patch shape sources. Add MapLibre
  symbol layers filtered to points; the patch symbol layer sits above the backdrop symbol
  layer, and both remain below land and station labels.
- Draw a monochrome SDF arrow rotated by `bearingDeg`, aligned to the map. MapLibre's native
  symbol collision and minimum zoom of 9 control density without camera callbacks or a new
  sampling system.
- Where the fitted Dodd model is available, evaluate it on the same one-minute cadence and
  emit one station-local direction point. Do not draw an area or imply certified coverage.
- The existing Currents toggle owns fill and arrows. Current pins remain independent, as they
  are elsewhere on the map. Add no setting, dependency, or data format.
- Reduce Motion needs no separate behavior because the renderer is static.

Patch direction is authoritative where patch and backdrop cells overlap. Omit a backdrop
direction point when its centroid falls inside a patch cell; layer ordering alone is
insufficient if contradictory symbols can both be seen.

## Performance contract

All harmonic evaluation and feature construction stays off the main thread. The main thread
only assigns completed shape collections at the one-minute refresh boundary. Panning and
zooming trigger no current-data computation.

Acceptance requires a physical-phone interaction pass with currents enabled and disabled:

- crossing zoom 9 causes no visible hitch;
- repeated pinch, pan, and rotate gestures remain responsive;
- no animation-rate timer or source replacement appears in an Instruments trace;
- the minute refresh causes no visible interaction stall.

If the static fill itself violates this contract, cull or tile its source as a separate,
measured fix. Do not reintroduce per-frame work.

## Tests

- The current style contains fill and direction symbol layers but no streak source, tail
  layer, head layer, or animation attachment.
- Direction layers use point filters, map-aligned feature rotation, native collision, and
  zoom 9 minimum.
- Evaluated cells produce polygons plus correctly located/bearing-tagged direction points.
- Patch direction wins over backdrop direction in overlap.
- Dodd emits one arrow with the fitted flood bearing on positive flow, the reciprocal on
  negative flow, and nothing without a fitted model.
- Toggle off adds no current sources or layers.
- Existing fill colour, no-green, layer-order, and field-sampling tests remain green.

Prove the regression assertion red against the animation implementation before removing it,
then run the focused tests, compile check, fast suite, and physical-phone interaction pass.

## Real motion follow-up

Real motion is a separate measured renderer decision. Keep the certified field and the
static layer as its fallback.

1. Benchmark a bounded CPU prototype that evaluates the vector field once per minute, stores
   a spatial lookup, advances a small visible particle set at a reduced cadence, and pauses
   all animation during camera gestures. Reject it if GeoJSON source replacement measurably
   worsens interaction or energy use.
2. If the CPU prototype misses the bar, use MapLibre's installed `MLNCustomStyleLayer` to
   render particles with Metal from the minute-stamped vector field. Add no rendering
   dependency. Treat the experimental MapLibre API as the principal maintenance risk.

The motion renderer ships only when physical-phone traces show map interaction within 10%
of the static baseline, no severe animation hitches during the gesture script, average idle
CPU at or below 15%, and Xcode Energy Impact remaining Low over a ten-minute run. Record the
device, OS, build, trace, and result with the implementation decision.

## Out of scope

- A map timeline scrubber.
- New current data, interpolation, or relaxed certification boundaries.
- Changes to the speed ramp, green transit state, station details, or current predictions.
- Preserving animation code that has no shipping caller.
