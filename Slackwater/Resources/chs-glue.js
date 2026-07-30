// Slackwater — GPL v3. JSCore glue for the on-device CHS fit (M0 spike's
// glue.js, trimmed to fit-only: prediction runs natively in TideEngine).
// Expects the chs-bundle.js IIFE global. No fetch, no console use — samples
// arrive as a JSON string of {t: epoch-ms, v: metres} from Swift.
function fitTides(samplesJson) {
  var samples = JSON.parse(samplesJson).map(function (s) {
    return { time: new Date(s.t), value: s.v };
  });
  var t0 = Date.now();
  // Plain BASIS at the 60-day window. The spike's SA/SSA carry-forward applies
  // to >60-day windows only: SA/SSA need 183 days (Rayleigh) and at 60 d they
  // are unseparable — measured on 2026-07-30, they silently absorb Z0 and
  // wreck held-out heights (Sidney val RMSE 9.1 -> 22.0 cm). Add them back
  // if the fit window ever grows past ~183 days.
  var result = CHSConstituents.fit(samples, {
    constituents: CHSConstituents.BASIS,
  });
  return JSON.stringify({
    fitMs: Date.now() - t0,
    offset: result.offset,
    rms: result.rms,
    constituents: result.constituents,
    unseparable: result.unseparable.map(function (p) { return p.constituents.join("/"); }),
  });
}
