# The CHS data model — what Canada gives us, and what it doesn't

Standalone reference. Everything needed to reason about Canadian tide and current
data is here, because the deeper planning material lives in a private repo most
readers cannot open. If you are scoping work that touches Canadian coverage,
start here rather than reconstructing it from the source.

Facts are cited to the file that enforces them. When this doc and the code
disagree, the code is right and this doc is stale — fix it.

---

## 1. The one-sentence version

CHS publishes **point predictions at gauged stations**, served through IWLS as
time series. There is no gridded product anywhere in this pipeline, and nothing
CHS-published ships inside the app — Canadian stations are *identities* in the
bundle whose harmonic models are fitted on each user's own device from
predictions that user fetched.

Both halves of that sentence constrain more work than people expect.

---

## 2. What IWLS actually serves

| Series | What | Used for |
|---|---|---|
| `wlp` | water-level predictions, 1-minute native | tide ports — decimated to 15 min before fitting |
| `wcsp1` | current speed predictions | current gates |
| `wcdp1` | current direction predictions | current gates — projected onto the flood axis |
| `wcp1-events` | CHS's own published slack/max events | **validation only**, never shipped |
| `/metadata` | station metadata incl. the flood/ebb axis | the gate's axis, fetched at fit time |

Stations are resolved **by position, never by name** — nearest IWLS station
serving the required series within 3 km of the registry position
(`ChsFitService.swift`, and see the resolve rule in
`spikes/chs-currents-fit/README.md`).

All of these are point series at a gauge. None is a field.

---

## 3. Licensing posture, and why it shapes the architecture

CHS data is used under DFO's licence (clause 10) and is **not to be used for
navigation**. The app's response to that is structural, not cosmetic:

- **Identity only is bundled.** `Resources/chs-stations.json` (1,086 stations)
  and `Resources/chs-current-gates.json` (18 gates) carry name, region, aliases,
  position, timezone, pairings — and **no harmonic constants**.
- **Models are fitted per user, on that user's device**, from predictions that
  user fetched. A fitted `ChsModel` is written to Application Support and never
  re-served to anyone (`ChsStation.swift`).
- The app states this in Settings, and marks *"Predictions — not for
  navigation"* on every detail footer.

Contrast the other two sources, which is why they behave differently:

- **NOAA** — public domain. 1,425 tide stations and 842 current stations ship
  with full constituents, offline from first launch.
- **TICON-4** — the CC BY 4.0 half ships (the non-commercial half can never);
  49 bundled stations cover Canadian water CHS does not gauge. Attribution is in
  Settings. **This is the precedent for bundling third-party harmonic constants**
  — see `tools/gen-tides.mjs`.

---

## 4. The four tiers of current data

Coverage is not uniform, and the differences decide what any feature can render.

| Tier | Count | Flow axis | Speed | Available |
|---|---|---|---|---|
| NOAA current stations | 842 | bundled | bundled constituents | immediately, offline |
| Fitted CHS gates | 11 | IWLS metadata, at fit time | fitted model | after download |
| Online CHS gates | 7 | in the fetched window | official CHS predictions | after fetch, needs signal |
| Derived gate | 1 | **never** | **never** | timing only |

**Fitted gates** (`online` absent/false) are fitted from `wcsp1`+`wcdp1` over the
gate's own validated window — 60 or 210 days, per gate, from the M51 validation,
not a blanket number (`ChsCurrentGateInfo.fitDays`). 210 exists because K1/P1
drive PNW diurnal inequality and separate under Rayleigh only at ≥183 days.

Seven of them additionally offer a **provisional** 60-day fast answer with a
measured worst-case slack error of 20–35 minutes (`provisionalSlackMinutes`),
marked in the UI with a ⚠️ badge and a `~` on every number.

**Online gates** (`online: true`) are the fit-rejects: findable identities backed
by official CHS predictions fetched on demand into a `ChsOnlineWindow`, 30 days
forward, never fitted. Sechelt Rapids carries the reason in its own registry
entry — the on-device model missed published slacks there by up to ~40 minutes.

**The derived gate** — Malibu Rapids, the only entry in
`Resources/chs-gates.json` — is a reference tide port plus fixed high/low lag
offsets. It has timing and nothing else: no speed, no axis, no constituents,
ever. Lag offsets cannot produce a velocity.

---

## 5. What "validated" means here, and why it outranks a model

The M47 pass scored each candidate gate's **fitted** slacks against CHS's own
published `wcp1-events`, held out 28–35 days into the future, on the app's exact
shipping path. The bar was set before scoring
(`spikes/chs-currents-fit/README.md`):

| Quantity | Bar |
|---|---|
| Slack timing, median | ≤ 15 min |
| Slack timing, worst | ≤ 30 min |
| Extremum timing, median | ≤ 20 min |
| Peak speed error, median | ≤ 0.5 kn |
| Axis | no systematic flip |

Slack is the safety quantity — a gate is transited *at slack* — so it gets the
tightest numbers.

**Gates that failed are not bundled at all: absent, not broken-looking.** That is
the house rule for Canadian coverage generally — coverage stops where we can
still tell when the numbers are wrong.

The consequence for any future data source: a shipped gate's numbers have been
measured against CHS's published truth. An unvalidated source that disagrees with
one does not get to quietly win.

---

## 6. Why there is no current field, and why interpolation is not a substitute

Recurring question, settled on #57, recorded here so it stays settled.

Products like PredictWind render a **gridded hydrodynamic model** — velocity at
every point of water. Nothing in the CHS/IWLS pipeline provides that; it serves
predictions at gauges. Our map has points.

The tempting middle path is interpolating a field between our stations. It is
wrong, and wrong asymmetrically:

- Tidal currents are set by **local constriction geometry**. Race Passage runs
  hard because of one specific narrows; a couple of kilometres away in the strait
  it does not.
- Interpolating would paint fast water across open water where there is none —
  embarrassing.
- And it would paint **calm water through every pass we have no gate for** —
  which tells someone an unmodelled pass is safe. That is the dangerous
  direction, and it is the same guess the app already refuses to make at Sechelt.

A real field would need a different **data product** — one storing harmonic
constants per mesh node, which the engine could evaluate offline the way it
already evaluates TICON constants. Whether such a product exists at usable
resolution and under a usable licence is an open investigation, not an
established fact. Resolution is a correctness question there, not a nicety: a
2–4 km global product cannot resolve Dodd Narrows and would render *slow* water
in a fast pass, which is worse than drawing nothing.

---

## 7. Consequences that keep catching people

The practical list. Each of these has cost someone time.

- **Any analysis over "all stations" silently excludes Canada.** CHS carries no
  constants until a model is fitted, so a sweep over the bundled data is a sweep
  over NOAA and TICON only. `tools/ramp-domain.mjs` reports a maximum current of
  ~10 kn; Sechelt Rapids runs ~16 and is simply not in the sample.
- **Zero of the 18 gates carry a flow axis in the registry.** It arrives with the
  fit or the fetched window. Anything drawing direction has staged availability
  and must degrade honestly — `chsPinTones` (`MapScreen.swift`) already models
  this: a station the sync has not reached is absent and draws neutral.
- **Online gates are never queued.** They have no download state, so queue-shaped
  UI does not apply to them.
- **A derived gate resolves only when its reference port is fitted** — it has no
  model of its own.
- **A fitted harmonic model does not expire**; a fetched online window does, and
  expiry there is a *coverage* question (`ChsOnlineWindow.covers`), not a
  staleness heuristic.
- **Canada is roughly 4.4 hours of politely paced IWLS requests** if you fetch
  everything; the request budget is scarce and shared (`ChsFitService.swift`).

---

## 8. Where the numbers live

| Thing | File |
|---|---|
| CHS station identity (1,086) | `Slackwater/Resources/chs-stations.json` |
| CHS current gates (18: 11 fitted, 7 online) | `Slackwater/Resources/chs-current-gates.json` |
| Derived gates (1) | `Slackwater/Resources/chs-gates.json` |
| NOAA tide stations (1,425) | `Slackwater/Resources/stations.json` |
| NOAA current stations (842) | `Slackwater/Resources/currents.json` |
| Regeneration | `cd tools && npm install && npm run build:data` |
| Fit validation history | `spikes/chs-currents-fit/README.md` |
| Peak-magnitude distributions | `tools/ramp-domain.mjs` |
