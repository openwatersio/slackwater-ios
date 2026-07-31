/**
 * Generate Resources/chs-gates.json — the derived current gates from the
 * station-corrections registry (a pass with NO current station of its own,
 * where slack is the reference tide port's high/low water plus a fixed lag —
 * Malibu Rapids today; generic over every `derived` entry so a new gate is a
 * registry bump + rerun, no app edit).
 *
 * Identity only (name/region/position/aliases/lags) — nothing CHS-published,
 * same licensing posture as chs-stations.json. The reference must be a
 * bundled CHS tide port (chs-stations.json): the app derives the gate's
 * slacks from that port's on-device fitted model.
 *
 * Run: cd tools && npm install && node gen-chs-gates.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const here = dirname(fileURLToPath(import.meta.url));
const res = join(here, "..", "Slackwater", "Resources");
const registry = JSON.parse(readFileSync(
  createRequire(import.meta.url).resolve("@sailingnaturali/station-corrections/data/registry.json"),
  "utf8",
));
const ports = JSON.parse(readFileSync(join(res, "chs-stations.json"), "utf8"));

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
  });
}

writeFileSync(join(res, "chs-gates.json"), JSON.stringify(gates, null, 1) + "\n");
console.log(`${gates.length} derived gate(s): ${gates.map((g) => g.name).join(", ")}`);
