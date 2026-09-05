# AyeTides' station database — inherited, not maintained

*2026-09-04. The station list behind AyeTides' web station map is public:
[hahnsoftware.com/resources/stations.js](https://www.hahnsoftware.com/resources/stations.js),
a plain `[lat, lon, name]` array (the host refuses curl's default user agent; send a
browser one). Every number below was recomputed from that file on 2026-09-04 with
[ayetides-station-fingerprint.py](ayetides-station-fingerprint.py) and matches an
independent first pass to within a point. Not legal advice, and it says so where it
matters.*

## The file

12,620 entries: 9,526 tide stations and 3,094 current stations (names ending in
"Current"). 5,584 in US states and territories, 7,036 elsewhere across 268 regions. Names
are XTide's verbatim ("Aberdeen, 28.5 n. mi. E of, Scotland Current"). 893 of the entries
are in England, Scotland, Wales and Ireland.

**Assumption:** this web list is the same corpus the app bundles. There is no way to check
from the app, and the listing's "over 12,500 locations" matches the file's 12,620, so this
note takes it as read and says so. The file is not redistributed here; the copy analysed
on 2026-09-04 has SHA-256
`d3128157b0b39e06b746251205b6e048b1fa3f5c49f28fef07c6c06af6152d97`, so a later fetch can
be compared.

## The claim, in one line

AyeTides' headline of "over 12,500 locations worldwide" is largely inherited from the
pre-2001 IHO/TMGPM harmonic tabulations that XTide and WXTide32 dropped in 2001, and
roughly half of it cannot be refreshed from any live source. Their coverage number
measures what was once transcribed, not what is maintained.

## Method: coordinate precision as a provenance fingerprint

A station pulled from a modern API (NOAA CO-OPS, or a licensed national dataset) carries a
full-precision position. A station transcribed from a printed harmonic table carries the
position the table printed: degrees and whole arc-minutes. The share of a region's
stations sitting on whole minutes is therefore a cheap fingerprint for "typed in from a
table" versus "fetched from a source".

The file stores four decimals of a degree, so a whole-minute value lands up to 0.003
arc-minutes off an integer. The histogram of residuals for non-US stations is bimodal:
4,730 under 0.004, twelve between 0.004 and 0.01, the rest spread out to half a minute.
The threshold is 0.004, in the gap.

| | Stations | On whole arc-minutes |
|---|---|---|
| US states and territories | 5,584 | 10% |
| Everywhere else | 7,036 | **67%** (4,730 stations) |

By region, the two signatures are unmistakable:

| Region | Stations | On whole arc-minutes | Reads as |
|---|---|---|---|
| Russia | 319 | 100% | transcribed tables |
| Newfoundland | 114 | 96% | transcribed tables |
| Nova Scotia | 197 | 95% | transcribed tables |
| New Zealand | 219 | 92% | transcribed tables |
| New Brunswick | 86 | 91% | transcribed tables |
| Australia | 397 | 89% | transcribed tables |
| Nunavut | 193 | 85% | transcribed tables |
| Québec | 202 | 85% | transcribed tables |
| British Columbia | 428 | 82% | transcribed tables |
| Germany | 102 | 80% | transcribed tables |
| Netherlands | 67 | 48% | mixed |
| Japan | 718 | 36% | mixed |
| Ireland | 110 | 26% | mixed |
| Alaska | 1,080 | 26% | mixed (NOAA plus older) |
| France | 200 | 24% | mixed |
| Wales | 90 | 11% | full-precision source |
| England | 414 | 8% | full-precision source |
| California | 403 | 7% | full-precision source (NOAA) |
| Scotland | 246 | 7% | full-precision source |
| Florida | 700 | 3% | full-precision source (NOAA) |

Canada as a whole: 1,314 stations, 51% on whole minutes.

Three stations are in "Karafuto, Sakhalin Island, Russia" (Airo Wan, Anbetsu, Buruny).
Karafuto is the Japanese name for southern Sakhalin, current only until 1945. That is the
vintage of the tabulations the legacy half descends from.

## The public record

**XTide.** Its FAQ ([flaterco.com/xtide/faq.html](https://flaterco.com/xtide/faq.html))
states: "Many data were purged after a legal threat from the U.K. Hydrographic Office
(UKHO) in January 2001," and that "although only the UKHO made an issue of it, the fact
that they did sufficed to 'poison' all of the International Hydrographic Office (IHO) and
Table des Marées des Grands Ports du Monde (TMGPM) data for every country." Some
non-commercial cooperation resumed afterwards; maintenance of the "non-free" datasets
ended in early 2012.

**WXTide32.** Its site ([svhorizon.com/wxtide32](https://svhorizon.com/wxtide32/)) says:
"In 2001, I was notified by the United Kingdom Hydrographic Office (UKHO) that the Crown
claimed copyright ownership of all tidal products for Great Britain, Ireland and
Scotland. My options were to stop distributing tidal data for those areas or purchase a
license." A hobbyist giving software away declined. WXTide32 still lists "more than 9,500
stations worldwide."

WXTide32 cut its UK coverage to a few dozen stations as a result; AyeTides carries 893
across the UK and Ireland.

**AyeTides** is a commercial product on the same XTide lineage, shipping since about 2010,
with the same order-of-magnitude station count as WXTide32's pre-purge era. Its App Store
listing says "tides and/or currents for over 12,500 locations worldwide," and its release
notes through 2024 repeatedly say the database was "updated with the latest NOAA
changes," which is the US half. It names no source, licence or update date per station.

**Debian's `xtide-data-nonfree`** (last upload 2010-05-29,
[sources.debian.org](https://sources.debian.org/src/xtide-data-nonfree/20100529-1.1/)) is
a 509,808-byte TCD. Its boilerplate credits NOAA, Fisheries and Oceans Canada (constants
"derived from sea level data", non-commercial use only), Rijkswaterstaat RIKZ for the
Netherlands (non-commercial, "excludes commercial software"), BSH Germany (12 reference
stations, non-commercial) and Proudman Oceanographic Laboratory for the UK (free software
only). No IHO, no TMGPM. Two things follow: the post-2001 non-free file is nowhere near
6,900 stations, so AyeTides' foreign bulk did not come from it; and every contribution in
it is non-commercial-only, so a paid app could not have used it anyway. AyeTides' Canadian
stations being 82–96% whole-minute also rules out the DFO sea-level-derived set as their
source.

## What the evidence supports

- **Two-thirds of the non-US corpus descends from the pre-2001 IHO/TMGPM tabulations.**
  4,730 of 7,036 stations outside the US sit on whole arc-minutes. The signature across
  Russia, Australia, New Zealand, Germany and all of Atlantic and Pacific Canada, plus
  three Karafutos and XTide's verbatim station names, is hard to read any other way.
- **That fraction is stale and unrefreshable.** Those tabulations have no live successor.
  NOAA publishes an API; CHS publishes predictions but leases constituents; the IHO tables
  are frozen where they stood.
- **The Canadian side is the part that matters to us, and it is measurably worse.** BC at
  82%, Québec 85%, the Maritimes 91–96%, 51% of all 1,314 Canadian stations. For BC the
  whole-minute rows were joined against the OSM coastline (station-metadata's
  `isOnLand` and `inlandMetres`) and, by name, against CHS's own positions
  ([ayetides-bc-join.mjs](ayetides-bc-join.mjs)):

  | AyeTides BC stations | n | On land | More than 200 m inland | Matched to CHS by name | Median distance from CHS position | More than 500 m from CHS |
  |---|---|---|---|---|---|---|
  | Whole arc-minute | 351 | 27% | 15% | 119 | **698 m** | 69% |
  | Full precision | 77 | 13% | 3% | 11 | **70 m** | 0% |

  Storm Bay sits 5.5 km from CHS's Storm Bay, Sullivan Bay 8.8 km, Riley Cove 1.0 km.
  A position rounded to the minute is inherently up to 0.9 km out at this latitude, and
  the transcribed rows are on average worse than that. This is the paddler complaint in
  [market-research-2026-07-17.md](market-research-2026-07-17.md) §2, "clearly placed on
  land", measured. Caveats: the OSM land polygons count rivers and inlet heads as land,
  so the on-land columns are inflated for Fraser and estuary stations in both groups
  (New Westminster reads 10 km inland in the precise group); the CHS-displacement
  columns do not have that problem. The name match is crude and the precise group is
  small.

## What it does not support

The first draft of this analysis inferred a licensing conflict. The per-region breakdown
cuts against that, and it should not be repeated:

- **The UK stations do not carry the legacy signature.** England, Scotland and Wales sit at
  7–11%, the same as NOAA-sourced US states, and there are 893 of them where WXTide32
  kept a few dozen. The one rights holder that actually threatened XTide is the one whose
  data AyeTides appears to have from a full-precision source. The simplest explanation is
  that a paid app licensed it: UKHO sells data licences with recurring fees, and a
  twenty-year commercial product can afford one.
- **Harmonic constants may not be protectable in the US at all.** *Feist v. Rural* (1991)
  ended sweat-of-the-brow copyright; a measured amplitude and phase for M2 at a port is a
  fact. XTide's 2001 purge answered a threat, not a ruling, and its author says so.
- **The EU/UK sui generis database right runs 15 years** from completion, renewable only by
  substantial new investment. Tabulations assembled before 1999 are very likely out of
  term, and Crown copyright on mid-century printed tables (50 years) has expired for
  anything of the Karafuto vintage.
- Whether any of this is a problem for AyeTides depends on agreements nobody outside Hahn
  Software can see, and on legal questions that were avoided in 2001 rather than settled.
  **This note is not legal advice and the pages must not imply a licensing problem.**

## What we do with it

- **On the comparison page.** [`slackwater-vs-ayetides`](../competitors/slackwater-vs-ayetides.md)
  says, under "Coverage everywhere else": AyeTides does not say per station where the
  constituents came from or when they were last updated, and much of its list outside
  the US "appears to date from harmonic tables published before 2001, and cannot be
  refreshed from any live source," with the two-in-three share. Hedged with "appears
  to"; nothing about rights.
- **Structurally.** This is the argument for the per-station `license` object in the Neaps
  tide database (`schemas/station.schema.json`: `type`, `commercial_use`, `url`, required
  on every station) and for Slackwater naming source, datum and licence on every station
  screen. A coverage number without provenance is a number nobody can check.
- **TICON-4 over orphaned stations.** The tide-database `data/ticon/README` records
  TICON-4 as CC-BY-4.0, derived from GESLA-4 observations, with `datums_source` per
  station. That chain is worth more than 6,900 stations nobody can trace.
  *Reconcile:* market-research-2026-07-17.md §4 called TICON/GESLA licensing "mixed, not
  fully spelled out" and recommended shipping NOAA-derived only. That note predates
  tide-database PR #16. One of the two is out of date; decide which before the roundup
  page claims anything about our worldwide tide count's licence.

## To reproduce

```
curl -A 'Mozilla/5.0' -o stations.js https://www.hahnsoftware.com/resources/stations.js
python3 ayetides-station-fingerprint.py stations.js
```

`ayetides-bc-join.mjs` reproduces the BC table; it needs `station-metadata` checked out
beside this repo. The fingerprint script asserts the headline shape (over 12,000 entries, non-US above 60%, US below
15%), so it fails loudly if the file changes under it.

