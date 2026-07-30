# CHS fit spike — M0 exit check: PASS (2026-07-30)

Proves the [milestones spec](../../docs/research/design-readiness-2026-07-22.md)'s M0 wedge risk
dead: **`chs-constituents` runs as-is inside JavaScriptCore** (no library changes, no polyfills
hit), fits Victoria Harbour from live IWLS predictions, and the JSCore output is **bit-identical
to the Node control**. Verdict: **JSCore in the app, no Swift port** — a port would inherit the
same accuracy floor for much more work.

## Numbers

Station **Victoria Harbour** (code 07120, IWLS id `5cebf1df3d0f4a073c4bbd1e`), `wlp`, UTC.
Fit 2026-05-25 → 07-24 (60 d @ 15 min); validation 2026-08-21 → 08-28 (7 d, 4 weeks later).

| Config | RMSE | Max abs | Extreme timing med/max | Fit (JSCore) |
|---|---|---|---|---|
| 60 d, library BASIS (23 const.) | **6.44 cm** | 14.4 cm | **11 min** / 84 min | 324 ms |
| 210 d, BASIS | 6.81 cm | 19.7 cm | 15 / 73 min | 1,111 ms |
| 210 d, BASIS + SA/SSA (Node probe) | 6.06 cm | 16.7 cm | 16 / 73 min | — |

- Comparable ballpark to the engine's Friday Harbor NOAA benchmark (3.5 cm / 7.9 min); the RMSE
  gap is the library's documented 23-constituent source floor, not a JSCore artifact.
- The >30 min timing tail is entirely Victoria's flat double-high plateaus (≈1 cm over 4 h —
  timing is ill-posed there while height stays within ~5 cm). Distinct extremes: 0–11 min.
- Bundle: 118.4 KB IIFE. Extremes matched 20/21 (the miss is a window-boundary artifact).

## What M3 (productizing) must carry forward

1. **iOS `JSContext` = same engine, no JIT** — 1.1 s fit stretches several-fold interpreted;
   fine for once-per-region.
2. **Set `JSContext.exceptionHandler`** — JS errors are silent without it. (Console shim was
   never hit.)
3. **No `fetch` in JSCore** — IWLS fetching lives in Swift/URLSession; hand JSON strings +
   epoch-ms across the bridge.
4. ~~Add `SA`/`SSA` to the constituent list for tide heights~~ — **corrected by M3
   (2026-07-30): only at windows ≥183 d.** SA/SSA are Rayleigh-unseparable below ~183 days
   and silently absorb Z0 — at the shipping 60-day window this *worsened* Sidney validation
   RMSE 9.1 → 22.0 cm (measured). Shipped config is plain BASIS at 60 d; the SA/SSA gain
   (fit RMS 8.2 → 5.0 cm) is real only at the 210-day probe. See `Slackwater/Resources/chs-glue.js`.
5. **IWLS gotchas:** `wlp` is 1-min native (decimate before bridging), 7-day request cap, query
   by Mongo `id` not station `code`, `wlp-hilo` events carry no high/low qualifier (classify
   against neighbours).

## Files

`fetch.mjs` (throttled, cached IWLS fetch) · `entry.ts` → build the IIFE with
`npx esbuild entry.ts --bundle --format=iife --global-name=CHSConstituents --outfile=chs-bundle.js`
(from the `chs-constituents` checkout's node_modules) · `glue.js` (engine-agnostic fit+predict) ·
`control.mjs` (Node control) · `SpikeRunner/` (Swift executable, `import JavaScriptCore`) ·
`fit-window.json` / `validation-window.json` / `validation-hilo.json` (decimated data — rerun
without refetching) · `*-report.json` (observed results). The raw 1-min IWLS cache (48 MB) and
the generated bundle are not committed.
