# Resilient downloads: aggressive caching, self-healing failures, honest readiness

Status: approved design, 2026-09-13. Supersedes nothing; extends the download
set (M53) and the queue (M51).

## The problem

A tester on a shared ship Starlink link — about 45 people on one terminal —
could not get a single Canadian station to download, and the downloads manager
told them to keep tapping Retry. PR #385 cut the bytes (15-minute IWLS
resolution, a disk-cached station list) and added per-request retries. What it
did not change is the shape of the thing: a station that runs out of attempts
is `.failed` for the rest of the session, the download set stops at nine
stations, and the manager's language is built around errors the user is
expected to act on.

The app should download and cache as much as it can, as early as it can, and
report readiness. A failure is a thing the app retries, not a thing the user is
asked to fix.

## What "aggressive" means here

Two tiers exist today: the nearest 6 tide ports and 3 current gates within
150 km (`ChsFitService.autoFitSet`), and everything else in Canada, which
downloads only when opened. This adds the middle: **everything inside the
150 km radius**, gates before ports, nearest first within each.

Around a Victoria fix that is roughly 100 stations, about 85 MB at 15-minute
resolution, and something like 50 minutes at the IWLS request pacing. Around
Halifax it is far fewer. Outside Canadian water it stays zero, which is what
the radius has always been for (#205).

The first screen is unaffected: tier 1 still runs first and still lands the
nearest port in about 30 seconds.

**Low Data Mode is the only brake.** `NWPath.isConstrained` maps to iOS's Low
Data Mode, which is the one signal where the user has actually said "spend less
here". Tier 1 downloads on any path. Tiers 2 and 3 wait while constrained and
join when the constraint lifts. Cellular as such is not special-cased: a ship's
Starlink presents as Wi-Fi, and a phone on LTE off the coast is exactly the user
who needs the data most.

### Chart packs do not follow

`ChartPacks.swift` currently gives every `.ready` station its own z9–z12
satellite disc, roughly 65 tiles and 2–3 MB. At ~100 auto-fitted stations that
is several hundred megabytes of imagery, about ten times today's store, for
ground the user has never looked at.

Station discs follow **favorites and stations the user has opened**, not the
download set. The 3×3 z5 area cells around the fix still cover the
neighbourhood at z5–z8, so the map stays usable everywhere the boat is; the
detail tier is reserved for stations someone chose.

## Failure gets a clock, not a verdict

`ChsJob` gains `attempts`, `retryAfter: Date?` and `lastError: String?`.

A job that fails transiently goes back to `.pending` with `retryAfter` set:
1, 2, 4, 8 minutes, capped at 15. `ChsQueue.nextPending` skips jobs whose
`retryAfter` is still ahead, and when the run loop finds nothing to claim the
service schedules one pump at the earliest `retryAfter` — the same shape as
`ChartPackManager.scheduleRetry`.

`.failed` narrows to **permanent** causes only:

- the IWLS station resolves further than `resolveToleranceKm` from the bundled
  position, or no station serves the series
- IWLS serves an empty series over the whole window
- a gate's metadata carries no flood axis
- the id is not in the bundled catalogs
- HTTP 4xx other than 429

Everything else is transient by default. The default matters more than the
list: a cause nobody anticipated gets retried rather than stranding a station.

Three things clear a backoff immediately: opening the station (`promote`),
`Connectivity` going online, and the manager's "Retry now".

Online gates get the same ladder. `attempted`, which is once per launch per
gate, and `failedOnline`, which is view state in `OfflineManagerList` and is
lost when the sheet closes, both move into the service alongside the queue's
state.

### One pacer

`IwlsFetcher` paces itself per instance at 2.5 s. The fit run builds one and
each online-gate fetch builds another, so two in flight run at ~48 requests a
minute against a 30-per-minute cap — the app rate-limits itself. The pacer
becomes shared across instances (an actor holding the last-request timestamp).

### The run loop stops waiting on a dead path

PR #385's follow-up bounded `timeoutIntervalForResource`, which keeps a denied
path from parking a claimed job forever. The honest fix belongs here: `pump()`
does not start a run while `Connectivity` reports no path, and a rising edge
pumps. With the backoff ladder in place that is no longer a way to strand work.

## The UI reports readiness

Every string below replaces one that either blamed the user or implied a stall.

**Manager rows**

| State | Row says |
|---|---|
| ready | Available offline |
| downloading | Downloading · 12 of 31 |
| pending | Waiting · 4th in line |
| deferred | Retrying in 3 min |
| offline | Waiting for signal |
| permanent | Unavailable · <reason> |

"Retrying in" is calm foam, not amber: the app is working. Only the permanent
row is amber, and it carries the reason rather than a Retry pill — tapping the
row already opens the station, which already retries it.

**Progress** comes from the fit loop publishing requests-done and
requests-total per job; the chunk plan length is known before the first fetch.

**The estimate** stops being `ChsJob.estimatedSeconds`'s flat 2.5 s per
request. The fetcher keeps a moving average of observed seconds per request and
the summary reads "about 12 min at the current speed", which on a ship link is
both more honest and more useful than a constant.

**The summary's action** becomes a quiet "Retry now", shown only while
something is deferred. The amber "Retry N failed" goes.

**The indicator** beside the gear goes amber only for permanent failures, or
offline with stations still missing. A deferred retry is not a warning.

**Cards and the waiting page.** `CardStatus` gains `.retrying`. The three card
sites that pass `failed: true` collapse into one call that reads the job, so a
card can no longer disagree with the queue. The waiting page gains the same
states plus progress.

**The chart card** stops asking for a retry it does not need. While online with
packs unfinished it says they are downloading and resume on their own; the
amber "Retry N unfinished" goes, and "Refresh charts" appears only once every
pack is complete. `ChartPackManager` also reconciles on a connectivity rising
edge.

## Testing

Unit: queue deferral and the ladder; tier ordering and the Low Data Mode gate;
promote and reconnect clearing a backoff; the permanent-versus-transient
classifier as a pure function; `.retrying` rendering.

UI: `-chsFailOnly` keeps meaning permanent, so
`testDownloadsRowRetryButtonWinsOverRowTap` becomes a row-tap retry test — the
Retry pill it asserts on is gone. A new `-chsDeferOnly` seeds a "Retrying in"
row.

Device: a pass behind Network Link Conditioner on a lossy profile. Nothing in
the offline suite demonstrates the slow-link experience this design exists for,
and the PR should say so plainly.

## Out of scope

Provisional tide fits — 60 days is the validated floor, and there is no fast
answer to publish before it. Backoff persisted across launches: a launch
already retries everything. Downloading the whole country. Keeping fetched
chunks after a fit lands. A region picker, still.

## Files

`ChsQueue`, `ChsFitService`, `IwlsClient`, `OfflineDownloads`, `CardStatus`,
`StationCard`, `ChsDetailView`, `ChartPacks`, and their tests.
