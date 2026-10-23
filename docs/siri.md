# Siri and Shortcuts

Slackwater includes three App Shortcuts: Next Low Tide, Next High Tide, and Next Slack Window. Installing the app makes them available to Siri, Spotlight, and the Shortcuts app. A separate shortcut download is unnecessary.

Open Slackwater and allow location before asking for a nearby prediction. Try "When is the next high tide in Slackwater?", "When is the next low tide in Slackwater?", or "When is the next slack window in Slackwater?" The actions also appear under App Shortcuts → Slackwater in Shortcuts.

## Place selection

High and low tide requests use the nearest available tide prediction. Slack-window requests use the nearest available current prediction. A recent location fix lets the action answer directly in Siri. When that fix needs refreshing, the action uses App Intents' dynamic foreground continuation before requesting location, with a five-second bound on that request. If foreground continuation is unavailable, or location is denied or unavailable, Siri asks the person to open Slackwater and allow location. A favorite, recent place, or first-run coordinate does not substitute for the person's location.

Predictions use the same bundled and saved models as widgets. A Canadian place that needs a downloaded prediction must have one saved before Siri can use it. Online current predictions must cover the widget loader's full required span. Siri skips a provisional current fit until the place's complete model is saved, so the card does not present its provisional speeds without their warning. A timing-only derived gate cannot answer a request for a measured current window. Selection has no distance cap, so the nearest available prediction can be far away. Each prediction names its place. If the selected current place has data but no slack window in the next 48 hours, Siri reports that at the named place without trying a farther one.

## Answers

Speech names the place and gives an approximate elapsed wait, rounded to whole hours when at least an hour remains and whole minutes below an hour. For example: "The next high tide at Oak Bay is in about six hours." Heights and full dates stay out of speech. An upcoming slack window includes its duration; an open window gives the time remaining, including after the slack instant has passed. Window boundaries use the comfort-current setting shared with the app and widgets.

Duration and remaining-time claims require an observed closing crossing. If a current remains below the comfort setting at the sampled end, Siri omits the ending time: "The slack window at Deception Pass is open now." A clipped sampling boundary never appears as the window's opening or closing. Speech describes the query time; the reused widget's live countdown can continue to advance while the result remains visible.

The visual result leads with the same relative answer Siri speaks. The exact details appear beneath it in smaller text, followed by the shared wide widget content. Tide results include the local event time and height in the selected units. Current results include the observed local window boundaries. Speech and the current card use the same sampled curve, including its reading and countdown. The curve highlights the requested tide or window, even when another event occurs first, and includes the requested event when it falls beyond the widget's usual visible span. When a window has an unobserved boundary, the curve marks its known opening or the current moment instead of showing a complete range.

## Validation

`TideShortcutTests` checks relative answers, tide selection, observed versus clipped window boundaries, provisional-model selection, foreground preparation for stale location, and agreement between spoken and visual results. Rendered snippet attachments cover tides and currents at compact widths, for manual inspection of larger answer and detail text above the fixed-size widget drawing. The tests do not cover Core Location failure callbacks or the five-second timeout. Tests that exercise App Intents in-process do not prove that Siri recognizes a spoken phrase or presents the snippet on a physical device.

Device verification covers all three phrases, Siri with the app closed, location denied or unavailable, a current window before and after slack, and speech alongside the visible result. Website examples should use a verified device capture.
