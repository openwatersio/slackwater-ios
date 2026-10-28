/**
 * Generate Resources/chs-gates.json — the derived current gates from the
 * database's curated records (a pass with NO current station of its own,
 * where slack is the reference tide port's high/low water plus a fixed lag —
 * Malibu Rapids today; generic over every `derived` entry so a new gate is a
 * database release + rerun, no app edit) — and Resources/chs-current-gates.json,
 * the current gates with their database-curated year-round fit dispositions.
 *
 * Identity only (name/region/position/aliases/lags/pairing) — nothing
 * CHS-published, same licensing posture as chs-stations.json. The reference
 * must be a bundled CHS tide port (chs-stations.json): the app derives the
 * gate's slacks from that port's on-device fitted model.
 *
 * Run: cd tools && npm install && node gen-chs-gates.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { here, curatedRecords, gateTombstones, writeBundle } from "./bundle.mjs";

const res = join(here, "..", "Slackwater", "Resources");
const registry = await curatedRecords();
const ports = JSON.parse(readFileSync(join(res, "chs-stations.json"), "utf8"));
const readOr = (file, fallback) => {
  try {
    return JSON.parse(readFileSync(join(res, file), "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return fallback;
    throw error;
  }
};
// The gate catalogs as they stood before this run rewrites them: the only
// record of a departing gate's name and position (see the end of this file).
const previousGates = [...readOr("chs-gates.json", []), ...readOr("chs-current-gates.json", [])];

const gates = [];
for (const [id, e] of Object.entries(registry)) {
  if (!e.derived) continue;
  const port = ports.find((p) => p.id === e.derived.reference);
  if (!port) {
    console.warn(`${id}: reference ${e.derived.reference} not bundled — skipped`);
    continue;
  }
  gates.push({
    id,
    name: e.name,
    region: e.context,
    aliases: e.aliases ?? [],
    latitude: e.position[0],
    longitude: e.position[1],
    timezone: port.timezone,
    reference: port.id,
    referenceName: port.name,
    hwLagMinutes: e.derived.hwLagMinutes,
    lwLagMinutes: e.derived.lwLagMinutes,
    magnitudeNote: e.magnitudeNote,
  });
}

writeFileSync(join(res, "chs-gates.json"), JSON.stringify(gates, null, 1) + "\n");
console.log(`${gates.length} derived gate(s): ${gates.map((g) => g.name).join(", ")}`);

// Admission and bounds belong to the database's year-round evidence.
const { currentGate } = await import("./chs-current-gates.mjs");
const gateEntries = Object.entries(registry)
  .filter(([, e]) => e.provider === "chs" && e.kind === "current" && !e.derived);
const currentGates = gateEntries.map(([id, e]) => currentGate(id, e, ports));
writeFileSync(join(res, "chs-current-gates.json"), JSON.stringify(currentGates, null, 1) + "\n");
console.log(`${currentGates.length} current gates (${currentGates.filter(g => g.online).length} online)`);

// A gate that stopped shipping keeps its identity in station-tombstones.json,
// which gen-slugs.mjs then carries like any other tombstone, or drops when the
// gate ships again or a station on its route replaces it.
const stones = gateTombstones({
  previous: previousGates,
  shipping: [...gates, ...currentGates],
  existing: readOr("station-tombstones.json", []),
});
writeBundle(join(res, "station-tombstones.json"), stones);
