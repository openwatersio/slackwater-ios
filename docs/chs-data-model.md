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
`docs/validation/chs-currents.md`).

All of these are point series at a gauge. None is a field.

---

## 3. The licence architecture — the load-bearing section

This section documents the app's licence architecture. Source: [CHS online design §2](https://github.com/sailingnaturali/slackwater/blob/51648731c02addef265f4839c9632145be962ad0/docs/superpowers/specs/2026-07-21-chs-online-design.md#2-the-licence-architecture), preserved as an immutable citation. Bare `chs-online-design` references are indexed in [the docs README](README.md#archived-source-citations).

Three CHS clauses interact: **clause 3** bars anyone from handing us a finished
bundle, **clause 4** bars commercial derivatives, and **clause 10** permits the
user's own derivation. That yields three options, of which only one works:

| Approach | Who holds the data | Redistributed by us | Offline |
|---|---|---|---|
| Bundle CHS predictions | us, then everyone | yes — **violates clause 3** | yes |
| Derive via `chs-constituents` | the user, from their own fit | no — clause 10 | yes |
| **Fetch CHS predictions** | the user, from CHS directly | no — nothing is derived | cached only |

> "The third row is not a loophole. It is the ordinary case the licence
> contemplates: a person requesting Canadian tide predictions from the Canadian
> agency that publishes them. We ship a *client*."

So, structurally:

- **Identity only is bundled.** `Resources/chs-stations.json` (1,058 stations)
  and `Resources/chs-current-gates.json` (22 gates) carry name, region, aliases,
  position, timezone, pairings — and **no harmonic constants**.
  `Resources/chs-tombstones.json` is the same posture for stations that have
  since left the bundle: identity we authored, for a favorite that persists a
  bare id and would otherwise have nothing left to name it (issue #91).
  `Resources/unavailable-stations.json` is the posture for the third case —
  stations that never entered the bundle and never can, because upstream
  states their predictions are non-commercial (issue #401). Written by
  `gen-tides.mjs` as the complement of the commercial-use filter below, and
  limited to the 139 that are more than 50 km from anything we do ship: where
  the app has an answer, the fact that a licensed station also sits there is
  not the user's problem. The map draws them as empty rings, which open an
  explanation rather than a forecast.
- **Models are fitted per user, on that user's device**, from predictions that
  user fetched. A fitted `ChsModel` is written to Application Support and never
  re-served — `ChsStation.swift` says it in code: *"fetched by this user, kept
  local, never re-served."*
- CHS data is **not to be used for navigation**; the app says so in Settings and
  marks *"Predictions — not for navigation"* on every detail footer.

`ChsFitter` runs Neaps's native Swift/Accelerate fit for both tide heights and signed current velocities, evaluating astronomy at every sample. `ChsFitter.basis` preserves the validated 23 constituents and excludes SA/SSA from the 60-day fit. Recorded Victoria and Dodd samples check coefficient parity against `@slackwater/engine` and prediction error on held-out data, including comparison with the frozen CHS fitter. The JavaScript artifacts live under `tools/chs-reference` for offline validation and field generation; they are not bundled with the app.

### This pattern does NOT generalise — the rule, and why

Fetch-don't-bundle looks like a general answer to any restrictively licensed
dataset. It is not, and the reason is precise:

> **It works because DFO operates IWLS as a public service the device can query
> directly. It is available for _services_, never for _static datasets_.**

A bulk file — a WebTide mesh, an ADCIRC tarball, a registration-gated TPXO
download — has no equivalent endpoint. Getting it onto devices means *we* host
it, which is exactly the distribution the licence covers. #99 investigated the
field question and hit this wall; see §6.

### The commercial-use gate is already enforced in the build

`tools/gen-tides.mjs` filters on `license?.commercial_use === true` and
re-asserts it on output, because this app's licence is *"a copyleft structure
that holds together with paid distribution"* (Settings). **Non-commercial terms
are a hard stop by a rule that already ships**, not a judgement call. Unknown
terms are worse than "no" — silence is not permission.

### The other two sources, and why they behave differently

- **NOAA** — public domain. 1,429 tide stations and 842 current stations ship
  with full constituents, offline from first launch.
- **TICON-4** — the CC BY 4.0 half ships; 49 bundled stations cover Canadian
  water CHS does not gauge. Attribution is in Settings. **This is the precedent
  for bundling third-party harmonic constants** — see `tools/gen-tides.mjs`.

  The non-commercial half's CONSTANTS can never ship, and none do. Its
  IDENTITY does, for 139 of those stations: name, region and position, with no
  harmonic data, so the map can explain an absence instead of leaving a hole
  (issue #401, `unavailable-stations.json`). Displaying a name to say "there
  is a station here we may not serve" is not a use of the predictions the
  licence restricts — but it is an attribution obligation, paid in Settings
  beside the CC BY 4.0 line.

---

## 4. The four tiers of current data

Coverage is not uniform, and the differences decide what any feature can render.

| Tier | Count | Flow axis | Speed | Available |
|---|---|---|---|---|
| NOAA current stations | 842 | bundled | bundled constituents | immediately, offline |
| Fitted CHS gates | 13 | IWLS metadata, at fit time | fitted model | after download |
| Online CHS gates | 9 | in the fetched window | official CHS predictions | after fetch, needs signal |
| Derived gate | 1 | **never** | **never** | timing only |

**Fitted gates** (`online` absent/false) are fitted from `wcsp1`+`wcdp1` over the
gate's own validated window — 60 or 210 days, per gate, from the M51 validation,
not a blanket number (`ChsCurrentGateInfo.fitDays`). 210 exists because K1/P1
drive PNW diurnal inequality and separate under Rayleigh only at ≥183 days.

Eight of them additionally offer a **provisional** 60-day fast answer with a
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
(`docs/validation/chs-currents.md`):

| Quantity | Bar |
|---|---|
| Slack timing, median | ≤ 15 min |
| Slack timing, worst | ≤ 30 min |
| Extremum timing, median | ≤ 20 min |
| Peak speed error, median | ≤ 0.5 kn |
| Axis | no systematic flip |

Slack is the safety quantity — a gate is transited *at slack* — so it gets the
tightest numbers.

A failed fit never ships as a fitted prediction. An online gate can retain its identity and display official CHS samples, with fetched-coverage checks and provenance. A derived gate has its separate timing-only model.

The consequence for any future data source: a shipped gate's numbers have been
measured against CHS's published truth. An unvalidated source that disagrees with
one does not get to quietly win.

---

## 6. Current fields and their limits

IWLS publishes predictions at stations, not a gridded velocity field. Interpolating between stations would paint calm water through unmodeled passes and spread narrow-channel currents across unrelated open water. The map must leave unsupported water without a current claim.

The app's current-field data has two sources:

- The [fill pipeline](../tools/fill-pipeline/README.md) fits SSCOFS surface u/v independently and ships only certified speed-fill elements. A station passes when its best scoreable element has median peak-speed error ≤ 0.5 kn. Extrema below 0.75 kn are unscoreable. An element's nearest scoreable station must pass and lie within 3 km; a nearer failed station masks it. Record sensitivity at 2, 3, and 5 km. Final fits require R² ≥ 0.8 on both axes. The JavaScript reference fitter decides survival; NumPy fits are prefilters and sizing estimates.
- The [patch pipeline](../tools/patch-pipeline/README.md) uses bathymetric cross-sections and a validated station to bound a local speed-and-direction field. Its committed [certification record](../tools/patch-pipeline/passes/CERTIFICATION.md) records retained geometry and rejected passes. Patch magnitude is depth-averaged and subject to the documented placement, datum, and phase limitations.

Both provide speed context. Slack timing and transitability belong to the station prediction and its validated windows. The field ramp contains no green. Missing or rejected elements remain absent, never calm, and interpolation must not paint across certification boundaries. Keep raw-source and derived-bundle provenance with the generated resources; a model refit is a release decision.

The [SSCOFS validation harness](../tools/sscofs-validation/README.md) records why speed certification is distinct from timing certification: none of the 53 scoreable stations in its 60-day box experiment passed all five current-fit bars. A fine-looking mesh is not proof of slack accuracy. Dodd Narrows is a negative control: a throat about 60–80 m wide is below the resolving scale of roughly 500 m elements. A model field cannot overrule a validated gate there.

## 7. Consequences that keep catching people

The practical list. Each of these has cost someone time.

- **Any analysis over "all stations" silently excludes Canada.** CHS carries no
  constants until a model is fitted, so a sweep over the bundled data is a sweep
  over NOAA and TICON only. `tools/ramp-domain.mjs` reports a maximum current of
  ~10 kn; Sechelt Rapids runs ~16 and is simply not in the sample.
- **Zero of the 22 gates carry a flow axis in the registry.** It arrives with the
  fit or the fetched window. Anything drawing direction has staged availability
  and must degrade honestly — `chsPinStates` (`MapPinState.swift`) already models
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
- **Fetch-don't-bundle is not a general licence workaround.** It applies to
  queryable services, never to static datasets (§3). This has already been
  mistaken for a generalisable pattern once, in #99.
- **An absent gate is honest; a wrong one isn't** (#9). Any future data source is
  a backdrop that yields to validated stations, never a source competing with
  them — and absence renders as *neutral*, never as calm (`MapScreen.swift`).

---

## 8. Where the numbers live

| Thing | File |
|---|---|
| CHS station identity (1,058) | `Slackwater/Resources/chs-stations.json` |
| Identity for stations that have LEFT the bundle (28) | `Slackwater/Resources/chs-tombstones.json` |
| Identity for stations that may NEVER ship (139) | `Slackwater/Resources/unavailable-stations.json` |
| CHS current gates (22: 13 fitted, 9 online) | `Slackwater/Resources/chs-current-gates.json` |
| Derived gates (1) | `Slackwater/Resources/chs-gates.json` |
| NOAA tide stations (1,429) | `Slackwater/Resources/stations.json` |
| NOAA current stations (842) | `Slackwater/Resources/currents.json` |
| Regeneration | `cd tools && npm install && npm run build:data` |
| Fit validation criteria and evidence | `docs/validation/chs-currents.md` |
| Peak-magnitude distributions | `tools/ramp-domain.mjs` |
