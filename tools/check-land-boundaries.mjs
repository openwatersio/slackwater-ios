#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gunzipSync } from "node:zlib";

const root = new URL("..", import.meta.url).pathname;
const work = mkdtempSync(join(tmpdir(), "slackwater-land-test-"));
const failures = [];

for (const name of ["land-usca", "land"]) {
  const archive = join(root, `Slackwater/Resources/${name}.pmtiles`);
  const tile = execFileSync("pmtiles", ["tile", archive, "6", "10", "22"]);
  const mvt = join(work, `${name}.mvt`);
  const json = join(work, `${name}.json`);
  writeFileSync(mvt, gunzipSync(tile));
  execFileSync("ogr2ogr", ["-f", "GeoJSON", json, mvt, "coast"]);

  const boundarySegments = [];
  const visit = (value) => {
    if (!Array.isArray(value)) return;
    if (value.length >= 2 && value.every((n) => typeof n === "number")) return;
    for (let i = 1; i < value.length; i++) {
      const a = value[i - 1];
      const b = value[i];
      if (!Array.isArray(a) || !Array.isArray(b) || a.length !== 2 || b.length !== 2) continue;
      const axisAligned = a[0] === b[0] || a[1] === b[1];
      // Long ruled spans, not short coastline segments that quantization can
      // make exactly horizontal or vertical.
      if (axisAligned && Math.hypot(b[0] - a[0], b[1] - a[1]) >= 100) boundarySegments.push([a, b]);
    }
    value.forEach(visit);
  };

  for (const feature of JSON.parse(readFileSync(json)).features) visit(feature.geometry.coordinates);
  if (boundarySegments.length) {
    failures.push(`${name}: ${boundarySegments.length} coastline spans follow source or tile grid lines`);
  }
}

if (failures.length) throw new Error(failures.join("\n"));
console.log("land tiles contain no stroked tile-boundary segments");
