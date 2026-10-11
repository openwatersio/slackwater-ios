# Alert sentence phrasings

Walked by hand on a device with Apple Intelligence before a release that touches
`alertSentenceInstructions` (docs/alerts.md §10). The bar: trigger and repeat right on every
line; lead, day and daylight may need a tap. The automated subset is
`AlertSentenceTests.testTheModelParsesTheCommonPhrasings`.

## Tide station (feet)

| Sentence | Trigger | Repeats | Also |
|---|---|---|---|
| tell me when the next low tide is | Low tide | no | |
| every high tide | High tide | yes | |
| remind me an hour before tomorrow's low | Low tide | no | lead 1 h, tomorrow |
| when does it drop below 2 feet during the day | Falling past 2.0 ft | no | daylight |
| let me know whenever it rises past 8 ft | Rising past 8.0 ft | yes | |
| lowest low in daylight | Lower low tide | no | daylight |
| every lower low tide | Lower low tide | yes | |
| the higher high tomorrow | Higher high tide | no | tomorrow |
| the low low tide | Lower low tide | no | |
| when is the next high | High tide | no | |
| every low tide between sunrise and sunset | Low tide | yes | daylight (the model drops this one; the toggle needs a tap) |
| ping me 30 minutes before every low tide in daylight | Low tide | yes | lead 30 min, daylight |
| when is high water tomorrow | High tide | no | tomorrow (the model drops the day now and then) |
| is there a lunar eclipse coming | Lunar eclipse | no | |
| alert me at low tide | Low tide | no | |
| each high | High tide | yes | |
| next time it goes under 1 foot | Falling past 1.0 ft | no | |
| when it comes up past 6 feet tomorrow | Rising past 6.0 ft | no | tomorrow |
| low tide the day after tomorrow | Low tide | no | 2 days ahead |
| all the lows this week | Low tide | yes | |
| high tide at night | High tide | no | not daylight |
| a day before the eclipse | Lunar eclipse | no | lead 1 day |
| wind over 20 knots | — word list: not offered | | |
| next slack at Race Passage | — word list: not offered | | |
| sunset tonight | Low tide (a near miss: read it back before Save) | no | |

## Current station

| Sentence | Trigger | Repeats | Also |
|---|---|---|---|
| next slack window | Slack window | no | |
| every slack | Slack window | yes | |
| when can I get through tomorrow morning | Slack window | no | tomorrow |
| tell me 15 minutes before the window opens | Slack window | no | lead 15 min |
| every max ebb | Max ebb | yes | |
| next max flood | Max flood | no | |
| when does it run hardest | Max flood or Max ebb | no | either is right |
| daylight slacks only | Slack window | yes | daylight |
| is there an eclipse this month | Lunar eclipse | no | |
| an hour before every slack in daylight | Slack window | yes | lead 1 h, daylight |
| low tide tomorrow | — word list: not offered | | |
| wind | — word list: not offered | | |
| high water slack | Slack window | no | |

## Derived gate

| Sentence | Trigger | Repeats | Also |
|---|---|---|---|
| the next slack | Slack | no | |
| every slack | Slack | yes | |
| slack tomorrow afternoon | Slack | no | tomorrow |
| half an hour before each slack | Slack | yes | lead 30 min |
| lunar eclipse | Lunar eclipse | no | |
| max ebb | — word list: not offered | | |
