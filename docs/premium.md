# Premium

**Everyone gets correct readings and the default chart design. Premium gets planning features and advanced chart controls.**

- **Free:** every prediction at every station and date, offline; the chart as designed; the unit and format choices and the comfort current in Settings; the watch app and home screen widgets.
- **Premium planning features:** notification alerts and their Live Activities, favourites calendars (a calendar for each favorite station) and printable tables ([alerts](alerts.md) §2, [detail](detail.md) §8.6).
- **Premium advanced chart controls:** Settings' "Sun, moon and stars" switch ([scrubber](scrubber.md) §14).
- **Premium glance surfaces:** lock screen widgets and watch complications. Without Premium they draw a locked wave labelled "Premium", and a tap opens the Premium sheet (`slackwater://premium`).
- Everything Premium is compiled under `PREMIUM_ENABLED` (`project.yml`); a build without it has no lock screen widgets, complications, Support Slackwater entry points or `slackwater://premium` route.

## Deciding a new feature

- A fix to a wrong or unclear reading is free, whoever asked for it.
- A control that changes what the default chart shows, adding detail or taking it away, is Premium. The default chart never gets worse to sell the control.
- A setting that tunes a reading to the person is free: units, formats, and the comfort current that sets the slack window.
- Only a change away from the default chart is gated. Without Premium, that change opens the Premium sheet and changes nothing; a change back to the default is always free. A stored value stays when Premium lapses, and when a free control becomes Premium. A lapse clears scheduled notifications; calendars keep publishing and can still be turned off ([alerts](alerts.md) §5.1).
- A Premium control is marked with `sparkles`, per [CONTRIBUTING](../CONTRIBUTING.md#user-facing-copy).

## Free day

- **Who:** anyone whose StoreKit entitlements hold no Premium purchase.
- **How often:** once per calendar month, in the device's current calendar and time zone. The button returns on the 1st, however late in the previous month the last one was used.
- **How long:** 24 hours from the tap, so one started late in the evening still covers the next day.
- **Where:** the Premium sheet, under the plans: "Try everything free today" when one is available, "Free day until" its end time while one runs, and "Your next free day is" the 1st of next month once this month's is used. Buying Premium hides it.
- **What it unlocks:** everything Premium unlocks, for exactly that window. `PremiumStore.isPremium` is true while Premium is purchased or a free day is running, and every gate reads it; `hasPurchased` tells the two apart for the sheet.
- **When it ends:** a lapse, as with an expired purchase. Alerts stop, lock screen widgets and watch complications return to their free view at the end time with the app closed, the sky switch is gated again, and every stored setting, rule and subscription stays. A free day never schedules a notification to fire after its end, nor a Live Activity whose event falls after it ([alerts](alerts.md) §6).
- **Calendars are the exception:** a station calendar turned on during a free day stops publishing when the day ends, and its events are removed. The calendar and the subscription stay, so buying Premium fills it again on the next run. A calendar turned on while Premium was purchased keeps publishing after a lapse ([alerts](alerts.md) §5.1). Buying during a free day keeps the calendars it turned on.
- **Across devices:** the start is recorded in iCloud's key-value store, so one free day covers every device signed into the same Apple Account; another device picks it up when its app next runs. The watch reads it the same way and copies the end time into the watch's App Group, so complications turn Premium once the watch app has run during the free day and return to free on their own at the end. Without iCloud the free day is recorded on the device alone.
