# Download tiers: what arrives on its own, one small yes, and no finish line

Status: proposed design, 2026-09-20. Extends the download set and queue from the 2026-09-13 resilient-downloads design.

## The problem

A fresh install near Victoria queues 99 Canadian stations — 94 tide ports and 5 current gates, 1,171 IWLS requests, about 49 minutes at the fetcher's 2.5 s pacing. Vancouver is 54 minutes. The work stops whenever the app is not in the foreground, so a user who opens the app, looks at a station and goes back to their day returns to the same incomplete state, having been told an estimate they were never in a position to wait out.

Pacing is not what costs the 49 minutes. IWLS rate-limits at roughly 30 requests a minute, so even unpaced the same queue is 39 minutes. Request count is the only lever that shortens it, and no iOS background mechanism completes work at that scale — `BGContinuedProcessingTask` stops executing when the device locks, and a phone in a pocket is the ordinary case.

So the app should stop presenting one long undifferentiated job. It should download what the user can see without asking, then ask a question small enough to say yes to, and never promise a finish line it cannot reach.

## Three stop points, one queue

The download queue is already sorted by pure distance, nearest first (`ChsFitService.autoFitSet`). The tiers are not three sets of stations or three download systems; they are three places to stop walking that one list.

- **In view** — stop after the stations the list is currently rendering. Downloads automatically, no prompt.
- **Nearby** — stop at 25 km. Requires a yes.
- **Everything** — do not stop. A preference, not a job.

One mechanism with a ceiling, so the manager's language becomes "how far out should I go" rather than three separate explanations. It also makes the last tier honest: it is not "all of Canada", it is "keep going outward from me", which is what a distance-sorted queue does anyway. A user in Victoria will never reach Halifax and should not be offered it.

## What "in view" means

Scroll position is the wrong definition — it is not observable without geometry plumbing, it is not testable, and it would grow the automatic tier as the user reads.

The list already computes the answer. `ListGroups` (`Theme.swift`) produces the deduped rendered set, and `StationListView` passes `nearCount: 4` when there is a fix, because the hero cards under My Location already show the nearest station of each series. The in-view tier is that set: the hero cards plus four Near Me cards — **six stations, 60 requests, about 2.5 minutes** where both a tide port and a current gate are nearby, five where only one series is.

This holds as the user scrolls, because `nearCount` is a constant. Scrolling reveals Favorites and Recents, which are explicit picks with their own download paths — `favoriteDownloads` and `promote` — and do not belong to the automatic tier.

The series filter chips narrow Near Me only. The cohort is captured from the unfiltered ranking and ignores the filter: filtering to Currents is a statement about what the user wants to look at, not about what the app should fetch, and letting the chips re-trigger downloads would make the strip flicker on every tap.

## Asking once

The prompt appears when the in-view tier finishes. That moment has to be stable, because three separate things reorder the list underneath it: `prioritize()` runs on every location update, so fix jitter re-ranks constantly; iCloud delivers favorites after launch through `prioritizeFavorites`; and the filter chips change what Near Me renders.

Latch the set, not the moment. Capture the cohort's station ids once, and let completion be a predicate over that fixed set — every id `.ready` or `.failed`. A set that cannot change cannot flap, so no debounce, no timer, and no suppression window is needed.

Re-capture only when the place changes, not when the fix does: when the hero item changes identity. Arriving somewhere new is a new question and deserves a fresh prompt. Moving fifty metres is not.

"Not now" suppresses the prompt for the session. The manager is the way back in.

## The strip

A progress strip at the top of the station list, present only when there is something to say. It has three states.

**Working.** The in-view tier is downloading. Shows progress by station count. Tapping it opens the downloads manager.

**Asking.** The in-view tier is done and stations remain beyond it. Becomes the question: "Download 14 more nearby?" with "Yes" and "Not now". The count is the offer; no duration appears here.

**Absent.** Nothing queued, or the question was declined this session.

The strip sits at the top while active because it is the only surface that can carry the tap, and a tap is what iOS requires before any of this can continue in the background. The downloads entry in Settings stays where it is for the rest of the time.

## The yes, and what iOS grants for it

`BGContinuedProcessingTask` (iOS 26) is what the yes buys. The rules it comes with shape the design more than the design shapes them.

It must be submitted from the foreground in response to a person's action, which is exactly what the "Yes" tap is — no separate consent dialog is needed or wanted. Registration is the inverse of the other background task types: continued-processing registrations are exempt from the register-before-launch requirement, so the handler is registered at tap time against a concrete identifier and submitted immediately. The `Info.plist` carries the wildcard form, `$(PRODUCT_BUNDLE_IDENTIFIER).<context>.*`, and a handler is never registered against the pattern itself. Both sides derive from the bundle id rather than naming it, because a literal that drifts from the bundle id fails registration silently.

Three limits are load-bearing:

- **Locking the device stops execution.** Apple treats this as a framework bug — the API was intended to hold a wake assertion — but it reproduces on current builds. Background progress happens while the screen is awake and stops when the phone goes in a pocket.
- **Swiping the app away cancels the task with no callback.** The app cannot know it happened and must infer state from queue progress on next foreground.
- **A person can cancel from the Live Activity**, which invokes the same expiration handler as a system kill, with no reason code to distinguish them.

The queue survives all three, because it already does. Every whole seven-day chunk is written to disk before it returns (`ChsChunkStore`), so an interrupted station resumes where it stopped with no refetching. Cancellation of any kind means "resume next time", not "start over".

Progress reported to the task stays honest — requests completed against requests planned. A rate-limit backoff waits at least 60 seconds by design, which makes the bar appear stalled; the subtitle says so through `updateTitle` rather than interpolating fake progress. Apple terminates tasks showing no progress first under resource pressure, but does not kill on a timer.

## The manager

The downloads manager is where the tiers get explained, because it has the room the strip does not. It shows each tier with its station count, its state, and a control:

- **In view** — always on, no control.
- **Nearby (25 km)** — the same offer the strip makes, available after "Not now".
- **Everything** — a switch, not a button: "Keep downloading Canadian stations whenever Slackwater is open." No estimate and no completion percentage, because at 1,073 stations and 11,209 requests there is no finish line to show. Progress is a running count.

Durations belong here and nowhere else. A number the user can act on is worth showing when they have come looking for it; the same number on a strip is an invitation to wait.

## Copy that stays true when the background stops

Since a locked phone stops the work, no surface may promise background completion. "Download 14 more nearby?" is the right shape precisely because it offers a count and not a finish. Anything of the form "we will finish these in the background" becomes false the moment the screen sleeps.

The honest promise the app can make, and should: what you opened is ready and stays ready offline, and the rest accumulates as you use the app without ever re-downloading anything.

## Numbers

Requests per station: a tide port is `ceil(fitDays/7)+1` requests; a current gate is that twice, plus one metadata call. Wall clock is request count times the 2.5 s pacer.

| Tier | Victoria | Vancouver | Halifax |
|---|---|---|---|
| In view (6 stations, 60 requests) | 2.5 min | 2.5 min | 2.5 min |
| Nearby, 25 km | 20 jobs, 253 req, 11 min | 15 jobs, 161 req, 7 min | 3 jobs, 30 req, 1 min |
| 150 km, for reference | 99 jobs, 1,171 req, 49 min | 111 jobs, 1,291 req, 54 min | 61 jobs, 610 req, 25 min |
| Everything | 1,073 jobs, 11,209 req, 7.8 h | — | — |

25 km is chosen to be accepted rather than to maximise coverage. That tap is the only thing that unlocks background execution at all, so its acceptance rate is the whole mechanism; a tier that reads as 45 minutes is declined, and the next tier can always be offered after this one lands.

## Dependencies

**The chunk-boundary yield (#423).** Promotion is the answer to "that station is outside your tier", and it currently waits for the station already downloading to finish — up to 157 seconds behind a 210-day gate. Every tier boundary in this design leans on a tap being responsive. This should land first.

**The tide fit window.** A 35-day window costs 6 requests per port instead of 10 and moves every number above: the in-view tier becomes 1.5 minutes, Victoria's 25 km tier 7 minutes, everything 4.8 hours. Whether 35 days holds against held-out prediction is being established separately. The architecture here does not depend on the answer; only the copy's numbers do.

## Testing

`BGTaskScheduler` is unavailable in the Simulator, so nothing in the background half is reachable from `scripts/test.sh` and no CI lane can cover it. What is testable, and should be:

- `ListGroups` produces the expected cohort for a fix, and the cohort is unchanged by a series filter.
- The completion predicate over a captured id set is true only when every member is `.ready` or `.failed`, and is unaffected by jobs added afterwards.
- Re-capture fires on a hero identity change and not on a small fix move.
- The strip's three states follow queue state, including that a cancelled background task reads as "working" again on next foreground rather than as an error.

The device behaviour — lock, swipe-away, Live Activity cancel — is verified by hand, untethered. Running from Xcode suppresses suspension and returns a false pass.

## Out of scope

- The first-run experience, including any intro tour, which is designed separately.
- The 150 km auto-download radius constant. The tiers make it a stopping point rather than a cliff, and it is not being changed here.
- Rewriting `IwlsClient` onto a background `URLSession`. It cannot honour the IWLS rate limit out of process, and it costs the retry and backoff policy to find out.
- Precomputing constituents server-side, which the CHS licence forbids (see `chs-constituents`).

## Files

- `Slackwater/StationListView.swift` — the strip, and the cohort capture where `ListGroups` is built.
- `Slackwater/ChsFitService.swift` — the tier ceiling on the distance-sorted queue, the captured cohort, the completion predicate.
- `Slackwater/ChsQueue.swift` — tier membership alongside existing job state.
- `Slackwater/OfflineDownloads.swift` — the manager's per-tier rows and the "Everything" switch.
- `Slackwater/Info.plist` via `project.yml` — `UIBackgroundModes` and the wildcard task identifier.
