# Premium sheet that sells the features, and a free day each month

Design for two changes to Slackwater Premium ([premium](../../premium.md)): a Premium sheet that pitches every Premium feature, starting from the one that brought you there, and a free day of Premium that anyone can turn on once a month. Build the sheet first. The free day lives on it.

## Intent

People reach the Premium sheet because one feature sent them there: they tapped Print, an alert's Remind me, a station calendar, or the sky switch. The sheet today is titled "Support Slackwater", leads with "Support Slackwater's development", and lists a few features in one card above two purchase buttons. It reads as a donation, and it shows the same thing whatever brought you there. Whether to buy then comes down to the one feature that was tapped.

The sheet should show that Premium is much more than that one feature. The model is Tide Guide's paywall: a swipeable card per feature that opens on the one you tapped, then a free vs Premium table, the plans, and one clear button. Support for an independent, open-source app stays, as the closing note rather than the headline.

The free day is for the casual user who opens Slackwater a few times a month. Once a month they can turn on Premium for a day and use all of it: alerts fire, the lock screen shows the tide, the week prints. When the day ends everything goes back to the free app, exactly as a lapsed purchase does, and the next Premium tap brings them back to the sheet, which now pitches the things they just used. The free day is how people try Premium. There is no App Store free trial.

## Goals

- The sheet opens on the feature you tapped and lets you swipe through every other Premium feature.
- A free vs Premium table shows how much of Slackwater is free, and what Premium adds on top.
- One prominent purchase button for the selected plan, with the yearly plan selected.
- A short closing note that Slackwater is independent and open source, and Premium keeps it going.
- Once a calendar month, anyone without a Premium purchase can turn on 24 hours of full Premium from the sheet.
- When the free day ends, alerts stop and widgets go back to their free view without the app having to be opened.

## Non-goals

- No App Store free trial or introductory offer on the yearly plan (owner's call: the free day replaces it).
- No monthly plan. The plans stay yearly and lifetime.
- No change to which features are Premium. [premium](../../premium.md) still decides that; the sheet presents it.
- No awards, ratings or testimonials on the sheet. Slackwater has none to quote yet. A later version can add them when it does.
- No guard against getting extra free days by reinstalling or changing the device clock. This is a casual-user feature, and a determined user getting a few extra days costs nothing.
- No in-app analytics. Slackwater has none, and this doesn't add any. Whether it works is read from App Store Connect sales.

## Anti-goals

- A sheet that makes the free app look crippled. The table's free column is generous on purpose: every prediction at every station, offline, home screen widgets and the watch app are free, and the table says so.
- A free day that keeps working after it ends. A notification that fires, or a widget that shows Premium data, after the 24 hours are up breaks the bargain.
- A free day that nags. No reminders to use it and no countdown alerts. The button sits on the sheet, and the app says when the day ends only where someone looks for it.
- "Scrub" in any user-facing string ([CONTRIBUTING](../../../CONTRIBUTING.md#user-facing-copy)).

## The sheet

One `PremiumView` serves every entry point, as now. It takes the feature that opened it, and opens the carousel on that card. An entry point with no feature (Settings, the station list's Premium row, `slackwater://premium`) opens on the first card.

From top to bottom:

1. **Carousel.** One card per Premium feature: a large example on top, then a title and one or two sentences. Swipe sideways between them, with page dots below. The cards use live examples drawn from the bundled station, the way `PremiumFeaturePreview` does today, not screenshots.
2. **Free vs Premium table.** One row per capability with a Free and a Premium column of checks. The free rows come first: every prediction at every station and date, offline; home screen widgets; the watch app. Then the Premium rows, in the same order as the carousel.
3. **Plans.** Yearly and lifetime as two selectable rows, with yearly selected when the sheet opens. Each shows its price from StoreKit; yearly says it renews every year until you cancel (App Review 3.1.2).
4. **Purchase button.** "Get Premium" with the selected plan's price beneath it. It stays pinned to the bottom of the sheet while the rest scrolls, as Tide Guide's does.
5. **Free day.** When one is available, a second, quieter button: "Try everything free today" (see below).
6. **Support note.** One or two sentences: Slackwater is independent and open source, and Premium is how it keeps going.
7. **Restore purchase, Privacy Policy, Terms of Use**, as now (App Review 3.1.2).

The close button replaces the Done toolbar button, top right. The title is "Slackwater Premium", with `sparkles` per [CONTRIBUTING](../../../CONTRIBUTING.md#user-facing-copy).

### Features on the carousel

In this order, with the tapped one first in view (the others keep their order around it):

- **Print and PDF**: a week of tides and currents on paper or as a PDF (#754, in progress). Added when that ships; the sheet is built so a feature is one more card and one more table row.
- **Alerts**: a reminder before the slack or tide you're waiting for, including the Live Activities that start for short-lead alerts ([alerts](../../alerts.md) §5.3).
- **Calendars**: tides and slack windows in your calendar alongside your plans.
- **Lock screen**: the next tide without unlocking. Shown on phone only, as now.
- **Watch complications**: the tide on your watch face.
- **Sky controls**: a quieter chart, without the sun, moon and stars.

Lock screen, calendar and alert keep the live examples `PremiumFeaturePreview` already draws. Print, watch complications and sky controls get new ones in the same style: a few rows of the printed week, the complication views, and the chart strip with and without the sky. Those three are the builder's to design, using the app's real views wherever they can.

### With Premium

Someone who owns Premium sees the same carousel and table as a tour of what they have, with "You have Premium — thank you" in place of the plans, purchase button and free day. During a free day the sheet shows the plans and purchase button as usual, plus a line saying when the free day ends.

## The free day

**Who.** Anyone whose StoreKit entitlements hold no Premium purchase.

**How often.** Once per calendar month, in the device's current calendar and time zone. The button comes back on the 1st, however late in the previous month the last one was used.

**How long.** 24 hours from the moment it's turned on, so a free day started at 10 pm isn't wasted.

**Where.** The button is on the Premium sheet, under the purchase button. Once this month's is used, the same spot says when the next one becomes available ("Your next free day is December 1"). While one is running it says when it ends.

**What it unlocks.** Everything Premium unlocks, for exactly that window. `PremiumStore.isPremium` becomes true when Premium is purchased or a free day is running, and every existing gate reads it unchanged. Keep the purchase on its own (`hasPurchased`, or similar) for the sheet, which needs to tell the two apart.

**When it ends.** Exactly as a lapsed purchase ([premium](../../premium.md)): alerts stop, widgets and complications go back to their free view, the sky switch is gated again, and every stored setting and rule stays, so buying Premium later brings it all back. Nothing should depend on the app being opened at the end time:

- **Alerts.** While a free day runs, the scheduler plans notifications and Live Activities only for moments before it ends. One whose fire time falls after the end is not scheduled at all. When the app next runs after the end, `isPremium` changes and the existing reschedule clears what is left.
- **Live Activities.** One is started only when its event falls before the free day ends, so none is still on screen counting down after it. (My call: the event, not the start, has to fall inside the day.)
- **Station calendars.** A calendar turned on during a free day is marked as the free day's. When the day ends, Slackwater removes the events it wrote for those stations and stops publishing them; the subscription itself stays, so buying Premium brings them back on the next run. (Removing rather than freezing the events is my call: frozen events would still show tides for weeks.) This is the one place a free day's end differs from a lapse (owner's call): a calendar turned on while Premium was purchased keeps publishing after a lapse, as [alerts](../../alerts.md) §5.1 says. Without this, one free day would unlock a rolling calendar for good. The removal happens on the first reschedule after the end, since calendar events can't expire on their own; the events written during the day reach at most 90 days ahead, as now.
- **Widgets and complications.** The end time is written to the App Group beside the Premium flag. The timeline providers treat a free day as Premium only for entries before its end, and ask for a new timeline at the end, so the widget changes on its own. This uses a free-day end key and leaves the purchase flag as it is. #588, an expired yearly subscription on the watch, stays its own issue (it was deferred by the maintainer); the design shouldn't make it harder, and a later fix can fold both into one "Premium until" date.
- **Print and the sky switch** are only reachable in the app, which rereads `isPremium` when the end time passes while it's open.

**Across devices.** The month's free day is recorded in iCloud's key-value store, as station lists are, so one free day covers every device signed into the same Apple Account. Turning it on on the phone turns it on on the iPad when that app next runs. The watch app reads it the same way and writes the end time to the watch's App Group, so complications turn Premium once the watch app has run during the free day, and turn back on their own at the end. No new WatchConnectivity path. Without iCloud it is recorded on the device alone.

## Copy

All new strings ship in every supported locale in the same pull request ([CONTRIBUTING](../../../CONTRIBUTING.md#localization)). Plain words over Premium jargon: "tides and currents", "your lock screen", "a reminder before you go". The free day is a "free day", never a "trial", which on the App Store means a subscription that starts on its own.

## Documentation

- [premium](../../premium.md) gains the free day: who gets it, how often, what it unlocks, and that its end is a lapse.
- [premium](../../premium.md) and [CONTRIBUTING](../../../CONTRIBUTING.md) call it the Premium sheet, not the Support Slackwater sheet.
- [alerts](../../alerts.md) §6's plan rules say a free day caps the notification and Live Activity horizon at its end, and §5.1 says a calendar turned on during a free day stops publishing when it ends.

## Testing

- Unit: free day eligibility across a month boundary and a time zone change; `isPremium` from purchase and free day; the scheduler's horizon capped at the free day's end; a free-day calendar planned before the end and cleared after, while a purchased one keeps publishing after a lapse; the widget's choice of entry before and after the end.
- UI: each entry point opens the carousel on its own card (seeded, like `-seedPremium`); a free user turns on a free day and Premium gates open; a seeded used free day shows when the next one comes.
- Device: let a free day run out with the app closed, and check that a lock screen widget and a watch complication go back to the free view and that no alert fires after the end.

## Left to the builder

- The visual design within the layout above, in Slackwater's palette rather than Tide Guide's.
- The examples for print, watch complications and sky controls.
- How the feature identifier reaches `PremiumView` from each entry point.
- The exact copy, within the rules above.
