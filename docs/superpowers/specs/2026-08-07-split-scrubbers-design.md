# Split the tide and current scrubbers

2026-08-07. Approved in brainstorm; supersedes the combined-strip anatomy from
the detail-hero spec (2026-08-03). Based off `detail/when-row-polish` (PR #25,
still working through a CI issue) — expect a rebase when its final fix lands.

## Decision (settled, do not relitigate)

The combined tide+current strip — one centerline time scrubbing both tracks —
is retired. A scrubber only ever scrubs ONE track: a tide detail scrubs tide, a
current/gate detail scrubs current. The combined strip was why the current and
derived-gate details were crowded; the freed space goes to the current story
itself.

Implementation approach: delete the combined case in place. `TimelineStrip`
stays one component; the UIScrollView host, magnet, and centering logic
(build-7 riding dot, M52 rounding — hard-won) do not fork into per-track
copies.

## §1 What dies

- `TimelineGeo` case `(true, true)` (height 362) and its constants
  (`tideBottom` 170, `sepY` 192, `curTop` 216, `curBottom` 342), the separator
  line, and everything else only the combined case reaches.
- `TimelineData.build`'s paired-tide input on the current path
  (`build(tide: pairedTide, current: record, …)` becomes current-only; the
  derived-gate builder keeps the port ONLY as the source of slack times, not
  as a drawn track).
- The "Tide at \<port\>" scrub-following readout blocks in
  `CurrentDetailView.scrubCard` and `DerivedGateDetailView.scrubCard`, and the
  engine `portHeight(at:)` calls behind them.
- Port high/low rows in the current and derived-gate schedules
  (`scheduleEntries` keeps only current events; tide extremes leave with the
  track).
- The "Tide shown is \<port\> — the … reference port, not this station" footer
  honesty lines in both views: nothing tide-shaped is shown anymore, so the
  disclaimer has nothing to disclaim.
- The strip's "Tide" / "Current" overlay track labels: with one track per
  strip, naming the track is noise — the page title already names it.
- Sunrise/sunset ROWS in `MultiDaySchedule` (the sun moves into the day
  header, §5). The strip's day-chrome sun dots/labels stay.

What survives, explicitly: the strip's extreme time labels (the absolute time
lives on the event itself — 2026-08-07 feedback), and the `ScrubWhen` when-row
(PR #25).

## §2 Current detail (`CurrentDetailView`)

- Strip is current-only on a TALLER geometry: ~340pt (vs today's 286
  single-track case) — curve half-height grows ~25%, so speed labels and the
  FLOOD/EBB reference lines breathe. Exact constants tuned in implementation;
  the intent is "the reclaimed vertical space goes to the current curve".
- LARGER time/value labels on the canvas: extreme/event time labels 8pt →
  10–11pt, other labels sized in step. Still fixed-size `.system(size:)`
  labels — the `TimelineGeo` fixed-point-geometry rule stands; the sizes grow
  with the geometry, they do not become Dynamic Type.
- Slack window under "Next slack": `under 0.5 kn · 2:32–2:58 PM · 26 min` —
  the workable window, not just the slack instant. Computed from the existing
  10-min `currentPoints` series: linear interpolation at the |v| = 0.5 kn
  crossings bracketing the slack. Threshold is a named constant (0.5 kn,
  the cruising "weak current" convention); no setting until someone asks.
  Under a provisional (fast-answer) model the window renders amber with the
  `~` prefix, like every other number on the page.
- Tide context becomes ONE quiet link at the bottom of the scrub card, in the
  list's `matchingButton` visual convention (caption weight-medium, `SN.leaf`,
  leading-aligned): **"Tide at \<port\> →"**, navigating to the port's own
  `TideDetailView`. Both `CurrentStationRecord.pairedTide` and
  `DerivedGateRecord.port` are `TideStationRecord`, so one
  `navigationDestination` type covers both callers.

## §3 Derived gate (`DerivedGateDetailView`)

Same shape as §2, minus everything speed-shaped — a derived gate is still
solving "when is slack":

- Schematic ±1 half-sine track only, slack dots on the zero line. No
  tide-turn markers on the strip; the derivation lives entirely in text.
- No slack window (no speeds exist to threshold). The readout keeps
  "speeds not predicted for this pass".
- The explanation stays where it already is: the "Shape only — slack times
  are derived from high and low water at \<port\> (+N min…)" note, the
  "at high/low water" line under Next slack, and the provenance footer.
- Schedule = slack rows + sun-in-header only.
- Same "Tide at \<port\> →" link.

## §4 Tide detail (`TideDetailView`)

Untouched except the shared changes: sun-in-day-header schedule (§5) and the
strip label font bump (§2) for consistency. Its strip geometry (258 /
`tideTop` 48 / `tideBottom` 226) does not change in this pass.

## §5 Schedule sun move (`MultiDaySchedule`)

Sunrise/sunset rows removed. Each day-group's left header column (74pt) gains
small `↑6:04 / ↓8:42` times under the day name — sunrise/sunset tones from
`SunPill`, small fixed/caption2-scale type. Rows become purely tide/current
events, so highs/lows and slacks/maxes get the vertical space. `SchedulePill`
loses `.sunrise`/`.sunset` if nothing else consumes them.

## §6 Recents collapse fix

`StationGroups.collapse` maps any id to its nearest namesake; Favorites are
exempt because "a starred station is an explicit pick". A station opened via
the matching-station chooser is exactly as explicit a pick, yet Recents is
collapsed today — so after choosing the farther "Discovery Island", the
Recents row silently shows and reopens the nearest one.

Fix: `recentIds: recents.ids` — uncollapsed, same principle as Favorites.
Two namesakes may then both appear in Recents, distinguished by their region
field (the M50 disambiguator). Near Me stays collapsed: that is distance
ranking, not user choice. The chooser link itself stays in the list; the
detail views only borrow its visual style (§2).

## §7 Tests

- ScreenshotTests pinning the combined layout — paired-detail, M46 derived
  gate, M52 — amended to the single-track layouts. Any frame assertions use
  the `settledFrame` pattern (one layout, not two).
- New unit coverage: slack-window computation (threshold crossings,
  interpolation at series edges, slack near the window boundary, provisional
  rendering) and uncollapsed Recents (chooser-opened namesake returns to
  itself; Near Me still collapses).
- `./scripts/test.sh` green on both simulators. Runs take 40–70 min and
  outlive the 10-min Bash cap: launch detached (`nohup … & disown`), poll the
  log with until-loops.

## House rules for the implementation

Branch-and-PR off `detail/when-row-polish`; never merge own PR; rebase when
PR #25's CI fix lands. Spec → plan → subagent-driven execution.
