// Engine-agnostic glue: runs identically under Node (control) and JSCore.
// Expects globals: CHSConstituents (the IIFE bundle). No fetch, no console use.
function runSpike(fitSamplesJson, valStartMs, valEndMs, stepSeconds) {
  var samples = JSON.parse(fitSamplesJson).map(function (s) {
    return { time: new Date(s.t), value: s.v };
  });

  var t0 = Date.now();
  var result = CHSConstituents.fit(samples, { constituents: CHSConstituents.BASIS });
  var fitMs = Date.now() - t0;

  var predictor = CHSConstituents.createTidePredictor(result.constituents);
  // 15-min grid aligned to the IWLS validation stamps, for RMSE.
  var grid = predictor.getTimelinePrediction({
    start: new Date(valStartMs),
    end: new Date(valEndMs),
    timeFidelity: stepSeconds,
  });
  // 1-min curve for extremum timing.
  var fine = predictor.getTimelinePrediction({
    start: new Date(valStartMs),
    end: new Date(valEndMs),
    timeFidelity: 60,
  });

  var offset = result.offset;
  var extremes = [];
  for (var i = 1; i < fine.length - 1; i++) {
    var a = fine[i - 1].level, b = fine[i].level, c = fine[i + 1].level;
    if ((b > a && b >= c) || (b < a && b <= c)) {
      extremes.push({ t: fine[i].time.getTime(), v: b + offset, kind: b > a ? "high" : "low" });
    }
  }

  return JSON.stringify({
    fitMs: fitMs,
    offset: offset,
    rms: result.rms,
    nConstituents: result.constituents.length,
    unseparable: result.unseparable,
    constituents: result.constituents,
    predictions: grid.map(function (p) { return { t: p.time.getTime(), v: p.level + offset }; }),
    extremes: extremes,
  });
}
