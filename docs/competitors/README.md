# Competitor and alternative pages — plan

*2026-09-04. Built on [research/market-research-2026-07-17.md](../research/market-research-2026-07-17.md)
and the Tide Guide teardown; every price, version and rating below was re-pulled from the US
App Store today. Page copy lives beside this file; the shared facts live in
[competitors.yaml](competitors.yaml). Change the YAML first, then the pages.*

## Ground rules for this content

- **Only shipped features.** Slackwater 1.9.0 (TestFlight, iOS 26+) has: worldwide tides,
  US + Canada currents with slack/max, offline predictions and offline chart, scrubber, home
  screen widgets (free), lock screen widgets (Premium). It does **not** have a Watch app,
  alerts, Live Activities, weather, or route planning. Every page says so where it matters.
- **No Slackwater prices on slackwater.xyz** (public repo rule in that AGENTS.md). Pages say
  "free core, optional paid add-on for the lock screen". Competitor prices are public facts
  and stay.
- **Competitor strengths stated plainly.** Tide Alert's alerts, Tide Guide's Watch and
  weather, AyeTides' 15-year record and 12,500 stations. The reader will check.
- **"Not for navigation"** on every page, same footer as the app.
- **No testimonials yet.** The app is in beta; the "what switchers say" section is left out
  rather than invented. Add it when real quotes exist (forum threads, support mail with
  permission).
- **Migration is honest:** nothing imports. Favourites are re-added by search; that takes a
  minute and the pages say so.

## Page set, in priority order

| # | URL on slackwater.xyz | Format | Target queries | Why this order |
|---|---|---|---|---|
| 1 | `/compare/best-tide-and-current-apps-iphone/` | Plural roundup | best tide app iPhone, best currents app, tide and current app, best tide app for kayaking / boating | Broadest intent, earns citations, hub for the rest |
| 2 | `/alternatives/tides-near-me/` | Singular alternative | Tides Near Me alternative, Tides Near Me offline, tides near me ads | Largest install base (161K ratings), ads, online-only: the most switchers |
| 3 | `/alternatives/tide-guide/` | Singular alternative | Tide Guide alternative, Tide Guide free, Tide Guide currents | Design leader, subscription-fatigue traffic, weak on currents |
| 4 | `/compare/slackwater-vs-ayetides/` | You vs competitor | AyeTides vs, AyeTides alternative, AyeTides BC currents | The direct offline+currents incumbent; BC paddlers already comparing |
| 5 | `/compare/slackwater-vs-tide-alert/` | You vs competitor | Tide Alert vs, Tide Alert alternative, tide alert slack tide | 44K ratings, now covers Canada; honest "they win on alerts" page |
| 6 | `/compare/slackwater-vs-actual-currents/` | You vs competitor | Actual Currents app, Actual Currents review, Actual Currents offline | Currents-first rival with a subscription; small today, growing |

Deferred: Tides and Currents-USA (27 ratings), PNW Current Atlas (33), XTide iOS (stale).
They appear in the roundup and the YAML, not as their own pages. Add a page only if search
console shows the query.

## Wiring on slackwater.xyz

Same pattern as `src/routes/privacy.tsx`: markdown in `src/content/`, `marked` in a route,
one canonical with a trailing slash. Six routes, or one `compare.$slug.tsx` reading a map of
slugs to markdown files. Add the six URLs to `public/sitemap-static.xml`. Link the hub from
the landing page footer and each page back to the hub and to its siblings. No new dependency.

Nothing on these pages fetches; they cost the site nothing at runtime.

## Maintenance

- Quarterly: re-pull the seven App Store listings, update `competitors.yaml`, fix any page
  that quotes a changed number. The `verified` date in the YAML is the trigger.
- Watch specifically: Actual Currents adding offline, Tide Guide adding current stations,
  AyeTides fixing its BC stations. Each one changes a page's thesis.

## Screenshots

Every page pairs a competitor's screen with ours; that is where a reader rethinks. Files in
`shots/`, referenced from the pages as `/shots/compare/<file>` (copy them to
`slackwater.xyz/public/shots/compare/` when wiring, converted to webp like the existing
`public/shots/`).

- **Slackwater shots** are from [PR #271](https://github.com/openwatersio/slackwater-ios/pull/271),
  the detail redesign, on iPhone 17 Pro simulator on 2026-09-04. In-progress work is fine
  here; re-shoot when the redesign lands so the pages match the build people install.
  Four screens: Nakwakto Rapids at slack and ebbing, St Martins (Fundy) tide, and North end,
  Falmouth MA current (chosen because Tide Alert and Actual Currents both sell on East Coast
  screens, and Actual Currents' listing shot is Cape Cod).
- **Competitor shots** are the developers' own App Store listing images, pulled from the
  iTunes lookup API on 2026-09-04, shown for comparison and captioned as theirs. Use the
  listing, never a private screen from a purchased copy; it is what they chose to be judged
  on. Refresh when the listing changes. The PNGs are deliberately not committed here; the
  webp copies the site serves live in `slackwater.xyz/public/shots/compare/`, and
  `https://itunes.apple.com/lookup?id=<app id>` returns the source URLs (swap the size
  suffix for `1290x2796bb.png`).
- **AyeTides' station database** is analysed in
  [research/ayetides-station-database-2026-09-04.md](../research/ayetides-station-database-2026-09-04.md);
  the vs page quotes only its hedged conclusion.
- **AyeTides** has no current-station screen in either listing (XL or iPhone edition), so the
  page shows their tide day beside ours and says plainly there is nothing to pair with our
  current screen.
- Alt text describes the numbers on screen, not the app's opinion of itself.
