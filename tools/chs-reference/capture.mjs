import fs from "node:fs";
import vm from "node:vm";
import { pathToFileURL } from "node:url";

const fit = process.argv[2]
  ? (await import(pathToFileURL(process.argv[2]))).fit
  : null;

const context = vm.createContext({ console });
for (const name of ["chs-bundle.js", "chs-glue.js"]) {
  vm.runInContext(
    fs.readFileSync(new URL(name, import.meta.url), "utf8"),
    context,
  );
}
const fixtures = new URL("../../SlackwaterTests/Fixtures/", import.meta.url);
const { stations } = JSON.parse(
  fs.readFileSync(new URL("iwls-recording.json", fixtures)),
);
function samples(station, series) {
  const seen = new Set();
  return station.series[series]
    .flatMap((s) => {
      const t = Date.parse(s.eventDate);
      if (!Number.isFinite(t) || seen.has(t)) return [];
      seen.add(t);
      return [{ t, v: s.value }];
    })
    .sort((a, b) => a.t - b.t);
}
const victoria = samples(
  stations.find((s) => s.key === "victoria"),
  "wlp",
).filter((s) => s.t % 900000 === 0);
const dodd = stations.find((s) => s.key === "dodd");
const dirs = new Map(samples(dodd, "wcdp1").map((s) => [s.t, s.v]));
const projected = samples(dodd, "wcsp1")
  .filter((s) => dirs.has(s.t))
  .map((s) => ({
    t: s.t,
    v:
      s.v *
      Math.cos(
        ((dirs.get(s.t) - dodd.metadata.floodDirection) * Math.PI) / 180,
      ),
  }));
const holdout = projected.at(-1).t - 7 * 86400000;
const training = projected.filter((s) => s.t < holdout);
const inputs = {
  victoria: victoria.slice(0, Math.floor((victoria.length * 5) / 6)),
  dodd60: training.filter((s) => s.t >= holdout - 60 * 86400000),
  doddFull: training,
};
const golden = Object.fromEntries(
  Object.entries(inputs).map(([key, input]) => {
    const { fitMs, ...result } = fit
      ? fit(
          input.map(({ t, v }) => ({ time: new Date(t), value: v })),
          context.CHSConstituents.BASIS,
        )
      : JSON.parse(context.fitTides(JSON.stringify(input)));
    return [key, { ...result, fitMs: 0 }];
  }),
);
fs.writeFileSync(
  new URL(fit ? "chs-fit-parity.json" : "chs-fit-golden.json", fixtures),
  JSON.stringify(golden, null, 2) + "\n",
);
