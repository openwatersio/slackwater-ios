import { readFileSync } from "node:fs";
import tzLookup from "tz-lookup";

// The pinned engine's shared golden fixture and the full stamps published by
// each evidence release at github.com/openwatersio/chs-current-validation.
// Pin changes and new evidence releases must confirm their measured recipe.
export const recipe = JSON.parse(readFileSync(new URL("./chs-current-recipe.json", import.meta.url)));
export function currentGate(id, e, ports, stamp = recipe.stamp) {
  const fit = e.chsFit;
  if (fit) {
    const invalid = message => { throw new Error(`${id}: invalid fit disposition: ${message}`); };
    if (!["final", "bounded", "online"].includes(fit.tier)) invalid("unknown tier");
    const fitted = fit.tier !== "online";
    if (fitted ? ![60, 210].includes(fit.days) : fit.days !== undefined) {
      invalid("only fitted gates carry a required 60- or 210-day window");
    }
    const bound = fit.slack_bound_minutes;
    if (fit.tier === "bounded" ? ![35, 40, 45].includes(bound) : bound !== undefined) {
      invalid("only bounded gates carry a required 35-, 40- or 45-minute bound");
    }
    const provisional = fit.provisional_slack_minutes;
    if (provisional !== undefined && (!fitted || fit.days !== 210 ||
        !Number.isInteger(provisional) || provisional <= 0 || provisional > 45 ||
        provisional % 5 !== 0 || (bound !== undefined && provisional < bound))) {
      invalid("a provisional bound needs a 210-day fit, a multiple of 5 up to 45, and cannot be below the full bound");
    }
  }
  const measured = fit && recipe.evidenceReleases[fit.evidence];
  if (fit && (!measured || measured !== stamp)) {
    throw new Error(`${id}: evidence recipe ${fit.evidence} differs from engine recipe ${stamp}`);
  }
  const online = !fit || fit.tier === "online";
  return {
    id, name: e.name, region: e.context, aliases: e.aliases ?? [],
    latitude: e.position[0], longitude: e.position[1], timezone: tzLookup(...e.position),
    tideReference: ports.some(p => p.id === e.tideReference) ? e.tideReference : undefined,
    fitDays: online ? 0 : fit.days,
    provisionalSlackMinutes: online ? undefined : fit.provisional_slack_minutes,
    slackBoundMinutes: fit?.tier === "bounded" ? fit.slack_bound_minutes : undefined,
    recipe: fit ? stamp : undefined,
    online: online || undefined,
    onlineMiss: online && fit?.miss ? {clause: fit.miss.clause, value: fit.miss.value, nearBar: fit.miss.near_bar} : undefined,
    missContext: online ? fit?.miss_context : undefined,
    magnitudeNote: online ? e.magnitudeNote : undefined,
  };
}
