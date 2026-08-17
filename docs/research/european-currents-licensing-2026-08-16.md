# Tidal currents outside North America — what can actually ship

Research 2026-08-16. Companion to `docs/superpowers/specs/2026-08-16-global-coverage-design.md`,
which deliberately excludes currents.

## Verdict

**There is a viable path, it is a per-country licensing exercise, and no global model
will do it.** The architecture that works is the one Slackwater already has — station-based
harmonic prediction at surveyed current stations with published slack/max offsets — extended
country by country. Not spatial interpolation of a global grid.

Three findings invert what we assumed:

1. **Germany gives away the best tidal-stream atlas in Europe**, commercial use explicitly
   permitted, €0.
2. **France is open for currents and expensive for tides** — the reverse of everywhere else.
3. **The UK has a licence-clean free route** (CMEMS/Met Office AMM15 at 1.5 km) that the
   `chs-data-model.md` §3 rule did not anticipate, because it is neither a service nor a
   restrictively-licensed static dataset.

## The trap to not walk into

The ADMIRALTY Tidal API looks perfect — £120/yr, has streams, modern REST — and is
structurally unusable for an offline app. From `developer.admiralty.co.uk/TandC`:

> **5.7** You shall not permit End Users to store cached Data for more than 24 hours.

with 5.2(a) barring "store in any medium". The FAQ's "caching is permitted" refers to *your
server*, not the phone. EasyTide is closed the same way: its terms prohibit "create a database
in electronic or structured manual form by systematically downloading and storing" the content.

**This is the CHS pattern failing.** `chs-data-model.md` §3 says the fetch-per-user route works
because "DFO operates IWLS as a public service the device can query directly." UKHO operates
one too — and closed it with an explicit cache cap. The pattern needs the *provider's* consent,
not just the shape.

Also stale-trap: a `data.gov.uk` record "UK Tide Times & Heights" is tagged OGL but was last
updated **February 2010** and its only resource is a dead EasyTide link. It licenses nothing.
UKHO's Marine Data Portal genuinely publishes wrecks, limits and bathymetry under OGL v3 —
tidal predictions and streams appear nowhere in it.

## Ranked routes

| # | Route | Streams | Offline in a paid app | Cost |
|---|---|---|---|---|
| 1 | **Germany — BSH** | ✅ 900 m German Bight, 3 nm North Sea | ✅ explicit | **€0** |
| 2 | **France — SHOM currents** | ✅ Channel + Atlantic 2D, 900 m-class 3D | ✅ Licence Ouverte 2.0 | **€0** |
| 3 | **UK — CMEMS AMM15 / Met Office UKMCAS** | ✅ derive from `ubar`/`vbar` | ✅ you own the derivative | **€0 + compute** |
| 4 | **UK — UKHO commercial licence** | ✅ authoritative | ✅ the Imray deal shape | **unpublished** |
| 5 | Tidetech Enterprise | ✅ 100 m Solent | ? terms unpublished | POA |
| 6 | FES2014 currents | open water only | ✅ as Adapted Material | €0 |
| — | TPXO, FES2022, POLPRED, Crown Estate MDE, EasyTide, Admiralty Tidal API | | ❌ **all closed** | |

### 1. Germany — ship free, today

BSH publishes two static ZIPs on `gdi.bsh.de`: North Sea at 3 nm and **German coastal waters
at 900 m**. Each is 13 plain-text files, HW Helgoland −6h…+6h, giving rate and direction for
**mean, spring and neap**:

```
 Lon    Lat      Mean       Spring     Neap
-3.9583 57.9250  0.052 234  0.056 233  0.056 236
```

Licence per the ATOM feed: **Datenlizenz Deutschland – Namensnennung – 2.0**, permitting
"Vervielfältigung, Verbreitung… für **kommerzielle und nichtkommerzielle Nutzung**". Static
since 2019 — bundle once, never stale. German tide predictions are separately free to publish
commercially, with one scheduling rule: **a calendar year's data may only be published from
1 August of the preceding year.** Put that on the release calendar.

Do **not** use the `ftp.bsh.de` GRIB forecasts — different product, restrictive AGB.

### 2. France — currents free, tides at 35% of revenue

SHOM's "Courants de marée 2D" (Channel + Atlantic u/v grids) and the 3D products (Manche,
**Fromveur**, Loire) are **Licence Ouverte 2.0 / Etalab**, `isFreeProduct: true`, granting reuse
"à des fins commerciales ou non… en l'incluant dans son propre produit ou application."

But SHOM kept **tide predictions** on the redevance list, and RIP 2026 names our exact case —
*"dans une application smartphone payante"* — at **T = 35% of revenue**, declared semi-annually.

So: take SHOM currents, pair with a non-SHOM tide source. TICON already covers France with 147
commercial-ok stations, so this is free. **One ambiguity worth an email** — the currents page
also renders a generic "usage commercial nécessite une licence commerciale" widget string that
contradicts its own Licence Ouverte declaration.

### 3. UK — CMEMS AMM15, the free route

`NWSHELF_ANALYSISFORECAST_PHY_004_013`, the Met Office AMM15 model. **~1.5 × 1.9 km**,
16°W–13°E / 46–62.75°N, **tide-resolving with 11 constituents including the M4/MS4/MN4 overtides
that matter in UK estuaries**. Ships `ubar`/`vbar` barotropic depth-integrated velocity — the
right variable for harmonic fitting, not surface `uo`/`vo` which carry wind and Stokes drift.

The licence is unusually permissive:

> **2.2** …worldwide, non exclusive, royalty free, perpetual licence … to **modify, adapt,
> develop, create and distribute Value Added Products or Derivative Work … for any purpose**
> **3.2** All new Intellectual Property Rights created as a result of modifying or adapting
> the Copernicus Marine Service Products **will be owned by the Licensee.**

No non-commercial restriction. **Derived harmonic constituents are a textbook Derivative Work —
we can fit them, ship them, and own the result.** Windy and savvy navvy already source this way.

**A cleaner licence nobody mentions:** the Met Office serves *the same AMM15 model* through
UKMCAS under **OGL v3** — "exploit the Information commercially… by including it in your own
product or application." Shorter, English law, no propagation clause. Check whether the UKMCAS
order form adds terms.

Catches: visible attribution required; §2.6 pushes record-keeping down the licence chain; French
governing law; §8.1 lets them revise at any time; the free-of-charge commitment runs to
30 June 2028 (the grant itself says *perpetual*). And a **10 m minimum-depth clamp** — the PUM
warns against use "in regions where there are extensive areas of bathymetry less than 10 m",
which invalidates drying banks and shallow estuaries. Archive is 2 years rolling; AMM7 reanalysis
(7 km) runs 1993→present. Fitting S2/K2 needs ≥1 year of record, ≈80 GB of hourly 2D fields.

Also open, same family: CEDA hosts 8 discrete months of NOC/BODC AMM15 hourly barotropic
velocity under **OGL v3, Open Access**. Ireland's `IMI_NEATL` ROMS (~1 km, tide-forced) is
**CC-BY 4.0** — cleanest licence of the lot — but only an ~11-day rolling window is served.

### 4. UK — UKHO, the only authoritative streams

UKHO is the monopoly holder and licenses on behalf of ~200 UK port authorities, so one agreement
clears most UK port-derived data at once. Its licensable-datasets catalogue (`REF061a.xlsx`)
lists, under a signed commercial licence:

- **Tidal stream data** — UKHO database, **ASCII text file**, annual supply each October
- **Tidal Stream Data Atlases** — the NP atlases (except NP263/NP265), PDF, on request
- Simplified harmonic constants (ATT Parts II/III), ASCII, annual

UKHO's stated posture is encouraging — *"We do not restrict your re-use of UKHO material…
we may develop a new licence agreement to cover the purpose"* — ~20 working days to an offer.
**Pricing is nowhere public.** The free 1-year licence caps at "total commercial value less than
£10,000 in any one year"; a real app exits that immediately.

**Precedent that this works at consumer pricing:** Imray Tides Planner ships fully offline with
UKHO-licensed data and sells UK/Ireland tidal streams as a **~£5.99 IAP**, with separate
"Hydrographic Office licence" purchases for France, Netherlands, Belgium, Spain, Portugal. That
is the REF061a deal shape, retailed. Whatever the royalty structure is, it supports that price.

## Why no global model reaches our gates

This is the finding that decides the architecture, and it is categorical rather than a matter of
degree.

**FES2022's "1/30°" is interpolation, not resolution.** The native T-UGO mesh is 30 km offshore,
10 km shelf, **4 km coastal**; the 1/30° Cartesian product is "directly interpolated from the
finite element native grid." Sampling a 4 km solution onto a 2.7 km grid adds zero information.
The honest comparison is 4–10 km native against a 200 m–2 km gate:

| Gate | Width | cells @1/16° | @1/30° |
|---|---|---|---|
| Alderney Race — strong-flow core | ~5 km | 0.9 | **1.7** |
| Pentland Firth — Inner Sound of Stroma | 2.4–3 km | 0.5 | **0.9** |
| Corryvreckan | 1.1 km | 0.21 | 0.40 |
| Menai Strait — the Swellies | ~275 m | 0.05 | **0.10** |

Non-recoverable, because peak rate comes from continuity (Q/A) plus hydraulic control. **A cell
wider than the channel averages the cross-sectional contraction away** — a 3×–300× area error,
not a calibration offset.

Published error numbers agree. Timko et al. 2019 (*Ocean Modelling* 136:66–84) against the Global
Multi-Archive Current Meter Database: **55–64% relative RMS error on M2 current ellipses** for
TPXO8 and FES2014 — roughly an order of magnitude worse in relative terms than the same models'
elevation errors (~3–5%). Structural: altimetry constrains height; currents are derived
(transport ÷ depth) and inherit every bathymetry error. Lyard et al. 2021 concede *"bathymetry
still remains unfortunately the limiting error."*

IEC TS 62600-201 requires **< 500 m** grid for Stage 1 feasibility. 1/30° misses that by ~6×.
Operational models at these exact sites run 110–250 m (Alderney Race), 100 m refined to 50 m
(Pentland Firth).

**And the decisive practical point: FES2014 applies no coastal extrapolation to currents.** At
every gate above the mesh does not reach, so you get **no data, not bad data**. FES2014 currents
are useful for approach waters, not for timing a pass.

**This is the same conclusion issue #99 reached for Canada** — "ruled out on resolution, not
licence", `ne_pac4` reading 2.62 kn at Dodd Narrows against CHS's published 9.5. The finding
generalises: the licences permitting commercial bundling are attached to the datasets that
cannot resolve. What is new is that CMEMS AMM15 at 1.5 km is the first dataset that is both
commercially clean *and* fine enough to be worth fitting — for shelf and approaches, still not
for the Swellies.

## Tides, for completeness

| Country | Tide heights, offline in a paid app | Cost |
|---|---|---|
| Germany (BSH) | ✅ incl. commercial publication | €0 |
| Netherlands (RWS) | ✅ **CC0**, 825 stations, 10-min, ~2 yr ahead | €0 |
| Norway (Kartverket) | ✅ CC BY 4.0, **explicitly endorses offline bundling** | €0 |
| Ireland (MI), Denmark (DMI) | ✅ CC BY 4.0, 2–3 yr ahead | €0 |
| **France (SHOM)** | ❌ **35% of revenue** | — |

Kartverket's API doc recommends our exact architecture — *"if you need to have tidal predictions
available off-line, please use the information provided by tidezones to program your own code"* —
46–59 harmonic constants across 33 stations plus 590 coastal zones, **under 400 KB shipped**.

For **streams** in NL there is a licence conversation with a working precedent (the Navy's HP33
data is non-commercial by default, but *"soms is een licentie gratis"*, and Stroomatlas Noordzee
already ships all 91 charts under Koninklijke Marine licence). In NO, IE and DK there is simply
no stream product — Kartverket's own page on Saltstraumen admits no reliable measurements exist.

## Recommended sequence

1. **Germany first.** Finished, static, free, commercially licensed, machine-readable. It proves
   the non-NOAA current path end to end against a dataset with no licence risk at all.
2. **France currents** next — same shape, one clarifying email first.
3. **UK via CMEMS/UKMCAS** — real work (fit constituents from a year of `ubar`/`vbar`), free, and
   we own the output. Good for approaches, honest about not resolving the famous gates.
4. **UKHO** in parallel, because the answer takes ~20 working days and the price is the single
   largest unknown in this document.

## Outbound needed — all require Bryan's review before sending

- `LicensingTeam@ukho.gov.uk` — REF061a tidal stream data + atlases, commercial mobile app,
  offline bundling. **The only way to learn the price.**
- `diffusion-commercial@shom.fr` — resolve the Licence Ouverte 2.0 declaration against the
  contradicting "licence commerciale" widget string on the currents pages.
- `aviso@altimetry.fr` — written confirmation that FES2014 currents are commercially licensable
  as Adapted Material under Issue 20. **The product pages still carry the superseded Issue-19
  "scientific purposes only" wording**, so the contradiction is live.
- Met Office UKMCAS — whether the order form adds terms beyond OGL v3.

## Sources

[UKHO REF061a](https://copyright.ukho.gov.uk/Docs/Licensable%20Datasets%20(REF061a).xlsx) ·
[ADMIRALTY developer T&Cs](https://developer.admiralty.co.uk/TandC) ·
[UKHO copyright licensing](https://copyright.ukho.gov.uk/aboutus.aspx) ·
[CMEMS licence](https://marine.copernicus.eu/user-corner/service-commitments-and-licence) ·
[AMM15 PUM](https://documentation.marine.copernicus.eu/PUM/CMEMS-NWS-PUM-004-013.pdf) ·
[Met Office marine data](https://www.metoffice.gov.uk/services/data/met-office-marine-data-service) ·
[AVISO Licence Issue 20](https://www.aviso.altimetry.fr/fileadmin/documents/data/License_Aviso.pdf) ·
[FES2022 handbook](https://www.aviso.altimetry.fr/fileadmin/documents/data/tools/hdbk_FES2022.pdf) ·
[TPXO registration](https://www.tpxo.net/tpxo-products-and-registration) ·
[SHOM data](https://data.shom.fr/) · [BSH geodata](https://gdi.bsh.de/) ·
[Kartverket tidal API](https://vannstand.kartverket.no/) ·
[Timko et al. 2019](https://os.copernicus.org/articles/17/615/2021/) ·
[IEC TS 62600-201](https://webstore.iec.ch/en/publication/66064) ·
[Tidetech pricing](https://www.tidetech.org/pricing/) ·
[Imray FAQs](https://www.imray.com/about/support-faqs/)
