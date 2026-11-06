# Offline predictions that reach as far as your trip

Design for how far ahead Slackwater keeps CHS online-gate predictions on the device ([detail](../../detail.md) §10.1, [chs-data-model](../../chs-data-model.md) §7). The app remembers how far ahead you have looked, keeps every downloaded online gate filled to that reach, offers to prepare the gates around the one you are planning at, and lets you delete a gate's download when you no longer want it kept up.

This applies only to the CHS online gates, the currents that are fetched as published blocks rather than fitted. Fitted stations and tide ports hold a harmonic model that never expires, so nothing here touches them.

## Intent

The journey that matters is planning, not packing. You are in Seattle in November, you will be in the Gulf Islands over the holidays, so you open Active Pass and slide the calendar out to the end of December. Today that fetches a month of predictions from the date you picked, which is right, and the card then reads "Through Jan 27" because the blocks happened to join up. But nothing remembers that you wanted January. The daily refresh keeps only a month ahead of today, so by late December the far end quietly stops advancing and the trip you planned for is a month away again. Jumping straight to a far week also leaves the weeks between unfetched. And you have prepared one gate, when the trip crosses several.

The card's language makes the same mistake. "Update now" and "keeps about a month" talk about freshness, when the sailor's question is reach: how far ahead can I count on this when I'm out of signal. A sailor getting ready for months away wants to say how far, say it once, and have the app keep it there.

## Goals

- The app remembers the furthest reach you have asked for and keeps every downloaded online gate filled to it, rolling forward each day you are online.
- Looking ahead at a date raises the reach to cover it. So does a "Download more" tap on the card, by a month each time.
- When a look-ahead raises the reach, the card offers to bring the online gates near the one you are viewing out to the same date, so a trip is prepared as an area and not a single gate.
- The weeks between today and the week you looked at are filled in, after the weeks you asked for.
- The card says how far the copy reaches and what the app will keep doing, instead of describing a one-month update.
- A gate's download can be deleted from the Downloads sheet, which stops the app refreshing it.

## Non-goals

- No change to fitted stations, tide ports, derived gates or the watch. The watch has no online gates.
- No change to the 60-day backward retention of blocks.
- No per-gate reach. One number serves the device.
- No new background mode. Background work is still the `BGContinuedProcessingTask` a user action unlocks ([list](../../list.md) §8); Prepare is one more such action.
- No Wi-Fi gating. Low Data Mode keeps its existing rule: a gate missing today still fetches, and nothing else does.

## Anti-goals

- A reach that shrinks on its own. The sailor set it; only the sailor changes what is kept. Deleting a gate is how they stop paying for one.
- A card that reads as a trial running out. The reach is shown as a date, never a count of days left, as the card already insists.
- A quiet fetch that hits the end of what CHS has published and marks the gate failed. Past the published end there is nothing to download, and the card should say that, not apologise.
- The nearby offer appearing on every visit. It is for the moment the reach grows, once, and stays out of the way otherwise.
- "Scrub" in any user-facing string ([CONTRIBUTING](../../../CONTRIBUTING.md#user-facing-copy)).

## Terms

- **Reach**: a whole number of days ahead of today that the app keeps filled, stored in the app group's defaults under `slackwater.onlineReachDays`. It starts at `Timeline.onlineFetchDays` (30) and only ever grows, up to a cap of 365 (my call: a year of 30-day blocks is about a megabyte per gate, and CHS does not publish much further than that).
- **Target end** for a gate on a given day: today in the gate's time zone plus the reach, less the same half day of slack `needsRefresh` already allows.
- **Covered**: the gate's stored block covering today reaches the target end without a gap. Blocks separated by more than a sample are separate blocks, as now; a far block does not count toward coverage until the blocks between it and today have joined it.
- **The refresh set**: the gates the daily refresh serves. Today that is the gates inside the selected radius around the device's fix, the favorites, and any gate opened this session; a completed download does not keep a gate in the set across launches ([list](../../list.md) §8). That is not enough for a trip planned from somewhere else: a gate opened once from Seattle drops out at the next launch and stops rolling. So the set gains a persisted part, the **kept gates**, stored in the app group's defaults under `slackwater.keptOnlineGates`. A gate becomes kept when a look-ahead raises the reach on it, when "Download more" is tapped on it, or when the nearby offer prepares it. It leaves only by Delete. Kept gates are listed in the Downloads sheet whatever the radius, fill to the reach on every pass, and are what Delete removes from. The radius and favorites keep working as they do; the reach changes how far every gate in the set is filled, not which gates the radius or favorites pick.

## What raises the reach

1. **Looking ahead.** When a pick in the week picker, a drag to the strip's edge, or a shared link lands the online detail on an anchor whose fetch would reach past the reach, the reach becomes the days from today to that anchor plus `Timeline.onlineFetchDays`. That is exactly the block the view fetches today for that anchor, so the stored copy and the remembered reach agree. Paging within the reach changes nothing.
2. **Download more.** The card's trailing action, when the copy already reaches the target end, is "Download more". A tap adds `Timeline.onlineFetchDays` to the reach and fetches the next block for this gate from where its stored copy ends, reusing the edge-extension fetch the strip already makes. The card shows progress while it runs and the new "Through" date when it lands.

The reach is raised at once, before the fetch, and persists even if the fetch fails. The daily refresh picks it up.

## Keeping every gate at the reach

The daily refresh's question changes from "does the block covering today reach a month ahead" to "does it reach the target end". When it does not, the fetch is anchored at the day the stored block ends, not at today, and asks for the usual 30 days from there. A gate whose copy is several months short needs several fetches; each lands, merges, and the refresh asks again until the gate is covered or a fetch returns nothing. This is the same serial, one-gate-at-a-time queue, with the same once-a-day marker per gate: one fetch cycle per gate per station-local day, where a cycle runs fetch after fetch until covered. A gate with no block covering today still fetches from today first, as now.

**Priorities.** The queue holds two kinds of work and drains the first kind before the second:

1. **Asked-for weeks.** The block for the anchor the sailor is looking at, on the gate they are looking at, then the same anchor on the gates the nearby offer added. These are the weeks of the trip.
2. **Filling in.** Every gate in the refresh set, brought from where its copy ends up to the target end, nearest gate first by the existing distance order. This fills the weeks between today and the trip, and keeps everything rolling afterwards.

A tap on the card or in Downloads still jumps its gate to the front, as it does now.

**The detail's own fetches stay immediate.** The pick, edge drag and card taps on the gate being viewed fetch at once through `startOnlineWork`, alongside the queue, as they do today; one fetch per gate still coalesces them with any fill of the same gate. The queue's fill cycle checks between blocks whether a gate is held by a caller and lets that gate's own fetch finish before fetching it further, so a pick never waits minutes behind a fill. The IWLS budget is shared between the two the way it already is between the detail and the daily refresh.

**Loud and quiet work.** A gate is active, and so counted in the download count, the list's strip, the Live Activity and the background task, when it has no block covering today, when an asked-for week on it is missing, or when its copy ends more than `Timeline.onlineFetchDays` short of the target end. The daily roll-forward leaves a covered gate at most one block short, so it stays quiet, as the daily refresh is today. A reach raised by months, or a Prepare, is loud until the gates are covered, which is what the preparing row and the background task need. "Ready" in the Downloads sheet means covered to the reach; the row shows the sheet's progress until then.

**Past the published end.** CHS publishes predictions to a finite date. A fetch past it returns an empty series, which the fetch treats as a permanent failure today. For an automatic fill, and for "Download more", it is instead remembered for the day as "nothing further published" on that gate: no failure line, no retry, the refresh tries again tomorrow, and the card says "CHS has published through <date>" in place of "Through <date>" when the copy ends short of the reach for that reason. A pick past the published end, on a gate that has a stored copy, lands on the honesty card with the same sentence instead of "Download failed". A partial series clamps and continues, as now, so the fill walks up to the edge. A quiet chunk boundary that returns nothing stops the gate for the day and resumes tomorrow, which is acceptable. The builder verifies on IWLS that a request past the horizon answers with an empty series; if it answers with an error status instead, that status is the signal and is handled the same way. The reach is not lowered.

## The card

The "Offline available" card keeps its place and its two rows. What changes is the text and the action.

- Title row: the connection symbol, "Offline available", and the validity on the trailing side, as now. The validity still reads "Through <date>" for the stored copy's last full day, or "Expired", or "CHS has published through <date>" when that is why it stops short.
- Second row: "Slackwater keeps predictions through <date> on this device and refreshes them whenever you're online." The date is today plus the reach, less the strip's forward pad, formatted like the validity. While the copy is behind the reach, the sentence adds "Downloading the rest." in place of a failure line, and the existing activity line shows the queue, retry or failure state as now.
- Trailing action: "Download more" when the copy reaches the target end; "Update now" when it does not. Both only while online. Progress replaces the action while a fetch runs, as now. "Update now" keeps its meaning: fetch from today, then the refresh carries on to the reach.

The honesty and extending cards (detail §12.3) keep their text, except that the extending card's sentence becomes "Downloading this week. Slackwater keeps predictions through <date>." so it no longer claims a month.

### The nearby offer

When a look-ahead raises the reach on a gate, and other online gates lie within `DownloadTier.nearbyRadiusKm` (25 km) of it, the card grows a third row:

"Also prepare the N other gates within 25 km through <date>?" with "Prepare" and a dismiss X.

Prepare does three things: makes those gates kept, so they persist and fill to the reach on every pass; queues the asked-for week on each of them, then their fill; and submits the background task, since the tap is the user action iOS needs for continued processing. It does not change the download radius, which is about the device's fix, not the place being planned. The row then reads "Preparing N gates" with the Downloads sheet's progress until they are covered, and disappears. The X dismisses the row for this gate and this reach; raising the reach again brings it back. The offer never appears when every gate it would add is already kept, a favorite, or inside the selected radius, since those already fill to the reach on their own. The offer measures from the gate, not the device's fix: the sailor is planning somewhere they are not.

Low Data Mode shows the offer and honors the existing rule when it runs: the gates download when the mode is off.

## Downloads sheet

Each online gate's row keeps its validity and action. The action becomes "Download more" or "Update now" by the same rule as the card. The sheet's introduction gains one sentence: "Slackwater keeps online currents through <date>. Look further ahead on any station to keep more."

A trailing swipe "Delete" (destructive, full swipe allowed) on an online gate's row removes its stored blocks, cancels any fetch in flight, removes it from the kept gates and from any pending or retry state, and leaves the row reading "Not downloaded" with "Download". A gate the radius or a favorite still wants stays listed and fills again on the next refresh pass; the sheet says why under the row until it does: "Within your 25 km choice. Narrow the radius to stop it downloading." or "A favorite. Unstar it to stop it downloading." Opening a deleted gate's detail fetches it as it does any gate without a block, and does not make it kept. Fitted stations get no swipe; they do not refresh.

## Where things live

- The reach: `slackwater.onlineReachDays` in `AppGroup.defaults`, next to the tier and request keys.
- The kept gates: `slackwater.keptOnlineGates`, a sorted list of gate ids, beside it. Seeded into the refresh set at launch the way requested downloads are.
- The published-end marker and the dismissed-offer marker: in memory on `ChsFitService`, like the daily refresh marker. A relaunch can try again, which is the behaviour we want.
- Blocks: unchanged, the per-gate `-online` file. No forward cap beyond the reach cap.

## Docs to update

- [detail](../../detail.md) §10.1 for the card's rows, actions, the nearby offer, the published-end wording and the refresh rule; §12.3 for the extending card's sentence.
- [list](../../list.md) §8 for the Downloads sheet's sentence, the row action and the swipe to delete.
- [chs-data-model](../../chs-data-model.md) §7 for the refresh rule, the two priorities, the reach and kept-gate keys, the loud and quiet rule, and the published-end marker.
- CONTRIBUTING's user-facing copy section if any new term needs a rule.

## Tests

- Unit: the reach math (a pick raises it to anchor plus 30 days; paging inside it does not; "Download more" adds 30; the cap holds; it never lowers), the covered question against the target end, the anchored fill fetch starting at the stored block's end, the priority order of the queue, the loud and quiet rule, kept gates surviving a relaunch and leaving on delete, the empty-series day marker, and delete clearing every piece of state.
- UI, extending `DownloadStatusTests` and `LiveFetchTests`: the card's sentence and action in each state; the nearby offer appearing after a far pick and not after a near one; Prepare keeping the gates and submitting background work; swipe to delete; the Downloads sheet row.

## Left to the builder

- Exactly how the two priorities are represented in `onlinePending` (two arrays, or a tagged entry), as long as asked-for weeks drain first and a tap still promotes.
- Whether the fill cycle is one Task that loops per gate or re-queues the gate after each block. Either way the once-a-day marker applies to the cycle, not the block.
- The wording of the preparing row's progress, within the sheet's existing style.
- Whether the Downloads sheet's introduction sentence belongs above or below the checklist.
