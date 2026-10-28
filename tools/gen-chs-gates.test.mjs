import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { currentGate, recipe } from "./chs-current-gates.mjs";
import { curatedRecords } from "./bundle.mjs";
const evidence = "fit-2026-10-22-8f85912-r2";
const entry = {name: "Gate", position: [49, -123], chsFit: {tier: "bounded", days: 210, slack_bound_minutes: 35, provisional_slack_minutes: 40, evidence}};
test("bounded gates carry measured bounds and stamp without online context", () => {
  const g = currentGate("gate", {...entry, magnitudeNote: "context"}, []);
  assert.deepEqual([g.fitDays, g.slackBoundMinutes, g.provisionalSlackMinutes, g.recipe], [210, 35, 40, recipe.stamp]);
  assert.equal(g.online, undefined);
  assert.equal(g.magnitudeNote, undefined);
});
test("online gates carry structured misses and missing evidence stays online", () => {
  const g = currentGate("gate", {...entry, magnitudeNote: "context", chsFit: {tier: "online", miss: {clause: "peak_speed", value: null, near_bar: true}, miss_context: "rapids", evidence}}, []);
  assert.deepEqual(g.onlineMiss, {clause: "peak_speed", value: null, nearBar: true});
  assert.equal(g.missContext, "rapids");
  assert.equal(g.magnitudeNote, "context");
  assert.equal(g.fitDays, 0);
  assert.equal(currentGate("unmeasured", {...entry, chsFit: undefined}, []).online, true);
});
test("a recipe mismatch fails generation", () => {
  assert.throws(() => currentGate("gate", entry, [], "deadbeef"), /differs from engine recipe/);
});
test("the recipe fixture belongs to the engine the app pins", () => {
  const project = readFileSync(new URL("../project.yml", import.meta.url), "utf8");
  assert.ok(project.includes(`revision: ${recipe.engineRevision}`), "refresh the measured recipe fixture when changing the engine pin");
});
test("every curated fit's evidence matches the pinned recipe", async () => {
  for (const [id, e] of Object.entries(await curatedRecords())) {
    if (e.provider === "chs" && e.kind === "current" && !e.derived) currentGate(id, e, []);
  }
});

test("bundled current dispositions exactly match the database evidence", async () => {
  const bundled = JSON.parse(readFileSync(new URL("../Slackwater/Resources/chs-current-gates.json", import.meta.url)));
  const ports = JSON.parse(readFileSync(new URL("../Slackwater/Resources/chs-stations.json", import.meta.url)));
  const expected = Object.entries(await curatedRecords())
    .filter(([, e]) => e.provider === "chs" && e.kind === "current" && !e.derived)
    .map(([id, e]) => currentGate(id, e, ports));
  assert.deepEqual(bundled, JSON.parse(JSON.stringify(expected)));
});

test("an unknown release cannot borrow a matching short recipe prefix", () => {
  assert.throws(() => currentGate("gate", {...entry, chsFit: {...entry.chsFit, evidence: "fit-2026-10-22-8f85912-r999"}}, []), /differs from engine recipe/);
});

for (const [label, changes] of [
  ["unknown tier", {tier: "retired"}],
  ["missing fitted window", {days: undefined}],
  ["unsupported fitted window", {days: 365}],
  ["missing bounded tolerance", {slack_bound_minutes: undefined}],
  ["unrounded bounded tolerance", {slack_bound_minutes: 36}],
  ["bounded tolerance over the bar", {slack_bound_minutes: 50}],
  ["bounded tolerance inside the final bar", {slack_bound_minutes: 30}],
  ["provisional tolerance over the bar", {provisional_slack_minutes: 50}],
  ["unrounded provisional tolerance", {provisional_slack_minutes: 41}],
  ["zero provisional tolerance", {provisional_slack_minutes: 0}],
  ["short-window provisional answer", {days: 60}],
  ["provisional answer worse after refinement", {provisional_slack_minutes: 30}],
  ["online fitted fields", {tier: "online"}],
  ["final bounded tolerance", {tier: "final"}],
]) {
  test(`invalid disposition rejects ${label}`, () => {
    assert.throws(() => currentGate("bad-gate", {...entry, chsFit: {...entry.chsFit, ...changes}}, []), /bad-gate: invalid fit disposition/);
  });
}
