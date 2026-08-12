# Prototype — Claude Design export

Exported 2026-07-30 from the Claude Design project **"Tides and currents iOS app"**
(`claude.ai/design/p/228dab64-4cee-4259-bbb4-8820feb92abf`), so the settled design decisions are
readable in-repo (the design-readiness review's "prototype-visibility" fix). The Claude Design
project remains the live editing surface; this export is the reference copy for reconciling spec
against prototype. Re-export after meaningful design changes.

| File | What |
|---|---|
| `Tides and Currents.dc.html` | The canvas page — lays out the three frames side by side (badges **1a**, **1b**, **FTUE**) |
| `TidesApp.dc.html` | The location detail view, variants `a` (Immersive — full-bleed sky, floating glass) and `b` (Modular — dark canvas, data-forward chart hero) |
| `NearMe.dc.html` | First-run flow: location gate → locating → Near Me list / map toggle, search, location-denied fallback |
| `_ds/…/styles.css` + `_ds_bundle.css` | Sailing Naturali design-system layer — brand fonts (Fraunces/Geist), `--color-sn-*` palette. Bundle is generated from the `web` repo's design system |

These are Claude Design component documents (`<x-dc>` template + a `DCLogic` class), not
standalone web pages — the runtime expects the host to provide React, so view them in the Claude
Design project; read them here. Reference screenshots (`uploads/`) were left in the project.
