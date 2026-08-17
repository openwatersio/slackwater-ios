/**
 * Does a station's own model agree with the datums its authority publishes?
 *
 * Predict a year of extremes from the station's constituents, take the mean
 * high and mean low, and compare to published MHW/MLW. Both sides are reduced
 * to CHART DATUM first, which is the step that makes the comparison mean
 * anything: NOAA publishes its datums against station datum (STND = 0, so
 * Ford Island's MHW is 7.532 with an MLLW of 7.078), TICON against something
 * near chart datum (Southampton's LAT is 0.066). Skip the reduction and NOAA
 * looks 7 m wrong while UK rows look right by the accident of LAT being ~0.
 *
 * Calibrated 2026-08-16 — NOAA control 0.011 m median / 0.018 m max over 25
 * stations, which is what licenses the tolerance below. Full numbers in
 * docs/validation/world-tide-stations.md.
 *
 * ponytail: one year of extremes per station, no caching. It is ~2 minutes for
 * the whole world bundle and it runs at build time. Cache it when a human is
 * waiting on it.
 */
import { createTidePredictor } from "@neaps/tide-predictor";

/**
 * 0.30 m. Independently justified by the NOAA control alone: its noise floor
 * (0.011 m median / 0.018 m max) sits 16.7-27.3x below this tolerance, on data
 * already known correct. It also clears 97% of UK home waters and 99% of
 * non-UK Europe while still failing Southampton (0.53) and Penarth (0.59) —
 * true, but that was known when 0.30 m was chosen (see
 * docs/validation/world-tide-stations.md's provenance note), so the control
 * argument is what to cite, not this sentence. Tighten to 0.15 m and 5.65% of
 * all checkable non-UK Europe stations fail outright (4.75% of the
 * currently-passing ones newly fail).
 */
export const DATUM_TOLERANCE_M = 0.30;

const YEAR_START = new Date("2026-01-01T00:00:00Z");
const YEAR_END = new Date("2027-01-01T00:00:00Z");

const mean = (a) => a.reduce((x, y) => x + y, 0) / a.length;

/**
 * Metres of disagreement between predicted and published mean high/low water,
 * whichever is worse. `null` when the station publishes nothing to check
 * against — an unjudgeable station is not a failing one.
 */
export function datumDeviation(station) {
  const d = station.datums;
  const cd = d?.[station.chart_datum];
  if (cd === undefined || d?.MSL === undefined) return null;
  if (d?.MHW === undefined || d?.MLW === undefined) return null;

  const constituents = (station.harmonic_constituents ?? [])
    .filter((c) => c.amplitude > 0)
    .map((c) => ({ name: c.name, amplitude: c.amplitude, phase: c.phase }));
  if (constituents.length === 0) return null;

  const z0 = d.MSL - cd;                       // MSL above chart datum
  const extremes = createTidePredictor(constituents)
    .getExtremesPrediction({ start: YEAR_START, end: YEAR_END });
  const highs = extremes.filter((e) => e.high).map((e) => e.level + z0);
  const lows = extremes.filter((e) => e.low).map((e) => e.level + z0);
  if (highs.length === 0 || lows.length === 0) return null;

  return Math.max(Math.abs(mean(highs) - (d.MHW - cd)),
                  Math.abs(mean(lows) - (d.MLW - cd)));
}

export function passesDatumCheck(station) {
  const deviation = datumDeviation(station);
  return deviation === null || deviation <= DATUM_TOLERANCE_M;
}
