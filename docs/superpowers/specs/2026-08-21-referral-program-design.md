# Referral program — design

*2026-08-21. Depends on `2026-08-21-widgets-premium-design.md` for the free/paid line, the
tier SKUs, and the entitlement cache this design grants against. That spec must land first;
this one adds no new product surface to it.*

## 1. Goal

**Reach, not revenue.** Slackwater's audience is cheap by disposition — the competitor
research is a wall of "littered with ads or need to pay" — and its growth lever is word of
mouth in small marine communities, not spend. The referral program buys installs with
product instead of money, and gives the people who have more time than money a way to
support the app that is genuinely equivalent to buying Premium.

The design consequence of that goal: **we are close to indifferent to being gamed.** Every
choice below spends its complexity budget on making sharing easy, not on making cheating
hard. See §9 for the arithmetic that justifies it, and the one future condition that
invalidates it.

## 2. Shape

- Every install has a **referral code**, generated on device, no account.
- A **new user who enters someone's code** gets **3 months of Premium**, immediately.
- A **referrer whose code is used 5 times** gets **a free year of Premium**.
- **A device may have one code applied, ever.** No stacking, no re-entry, no hoarding.

The rewards are deliberately **asymmetric**: the person doing the work gets the real thing,
the person who merely typed a code gets a taste. §4 explains why that asymmetry is the
entire fraud strategy.

## 3. Why the referee is paid (the attribution problem)

iOS has **no install-referrer API**. Android has one; Apple removed the equivalent
deliberately. What Apple offers instead:

| Mechanism | Why it doesn't work here |
|---|---|
| AdAttributionKit / SKAdNetwork | Built for ad networks. Aggregate, postback-based, privacy-thresholded. Cannot say "user X referred this install" |
| App Store campaign tokens (`?ct=`) | Aggregate per-campaign counts in App Analytics, ~1 day delayed, with a privacy floor that sits right at the 5-install threshold we care about |
| Branch / AppsFlyer / Adjust deferred deep links | Actually solve it, and are flatly incompatible with the no-account, no-tracking, no-SDK posture. Ruled out on positioning |

That leaves exactly one reliable signal: **the new user tells us.** Which means the reward
has to sit on the referee's action, not the referrer's — otherwise nobody types the code and
there is no program. Paying the referee is not generosity, it is the attribution mechanism.

## 4. Reward sizes, and the leak we are designing for

Codes will be posted publicly. A code that is worth a **free year** ends up on a deals
subreddit within a week, and Premium is functionally free for anyone who reads Reddit —
which both erodes the tier and makes the people who paid $5 feel like marks.

The fix is the size of the prize, not a gate:

- **3 months for the referee.** A leaked code is then a trial — something we would happily
  have offered anyway, and it puts the app on a lock screen, which is the entire point. It
  is not worth writing a Reddit post about, and nobody who paid feels cheated by it.
- **A year for the referrer, at five.** Real, and only reachable by actually persuading five
  people to install and type something.

This also keeps the tier honest with `widgets-premium-design.md` §1's "no trials" posture:
we still never *advertise* a trial. A referred user is given one by another human.

## 5. One code, ever

Enforced by a `referralRedeemed` item in **Keychain**, not `UserDefaults` and not the App
Group container. Keychain items survive app deletion; the app container does not. That
single choice closes the delete-and-reinstall loop for free.

Set `kSecAttrSynchronizable` so the flag rides iCloud Keychain: the gate then binds to the
**Apple ID across devices** rather than to one device, so the cheapest attack requires a new
Apple ID rather than a reinstall — and a legitimate user's iPad correctly knows the code was
already used.

Known ceilings, both accepted: Keychain persistence across uninstall is reliable in practice
but is not a documented Apple contract, and "Erase All Content and Settings" or a genuinely
new Apple ID clears it. That is several minutes of work to avoid a few dollars, and the
person willing to do it was never going to pay.

## 6. Codes: format, entry, and the validation we deliberately skip

- **Format:** 5 characters, uppercase, Crockford-style alphabet with `0/O/1/I` removed.
  Case-insensitive on entry, whitespace and dashes stripped.
- **Entry point:** a single field on the **tier sheet** — "Have a code?" — not a first-run
  screen. A first-run code prompt is a nag wearing a different hat, and it would violate
  `widgets-premium-design.md` §5's closed list of surfaces.
- **Prefill, so nobody types:** the share link `https://slackwater.xyz/r/<CODE>`
  is a **universal link**. App installed → opens the tier sheet with the code filled in. Not
  installed → App Store, and the tier sheet offers a **Paste code** button
  (`UIPasteControl`) next to the field. That button, not a silent read: since iOS 16 reading
  the pasteboard programmatically raises the system "Allow Paste?" alert, and firing that at
  a user who just opened the app is precisely the creepy first-run moment we are avoiding.
  One tap to paste, or type five characters.

**We do not validate codes.** Any well-formed code grants the 3 months, with no network call
at all. This is the one decision that keeps the feature compatible with an offline-first app
used in anchorages with no bars — and it deletes an entire validation service, a shared
secret, and an offline-failure mode. A fabricated code costs us a 3-month grant that has
zero marginal cost (§9). The **server** decides separately whether a redemption counts
toward a real referrer's five; the app never needs to know.

## 7. Counting the referrer's five

**Redemptions reported by the app are the count. Link opens are display only, and never
unlock the reward.**

The asymmetry that decides this: a link open costs an attacker one line of `curl`, while a
redemption report requires a real device that really installed the app from the App Store.
If both signals fed the same counter, the farmable one would be the one that pays.

- **Redemption report (authoritative).** The moment the app knows a code, it reports it —
  and it almost always knows at first launch, when network is as close to guaranteed as it
  ever gets, because the user has just downloaded the app from the App Store. Fire-and-
  forget, non-blocking, retried at most once per launch until acknowledged, and it never
  gates anything in the UI: the referee's 3 months are granted locally whether or not the
  report lands (§6).
- **Link opens (display only).** `slackwater.xyz/r/<CODE>` counts the hit and redirects to the App Store. Shown to the referrer as "people who looked", useful for their
  own sense of whether sharing is working, and structurally incapable of unlocking a year.
  On Android/desktop the link resolves to the web client, and those opens are counted here
  too — but only as opens. See the asymmetry below.

**The web half is opens-only, by construction.** The web client is a demo and cannot be the
paid surface: charging on the web requires accounts, and this product is account-free from
the entitlement down ([web-client design](https://github.com/sailingnaturali/slackwater/blob/51648731c02addef265f4839c9632145be962ad0/docs/superpowers/specs/2026-07-20-web-client-design.md)).
So there is nothing on the web to grant a referee, no reason for a web visitor to type a
code, and no redemption for the web to report. Both rewards — the referee's 3 months and the
referrer's year — are **iOS-only**. A shared link that lands someone on the web client is a
real win for reach and contributes nothing to anyone's five.

This inverts an earlier reading of the same fact: web installs are *observable* where iOS
installs are not, which made them look like the precise half of the count. They are precise
and irrelevant. The countable event is a redemption, and redemptions only exist where there
is something to redeem.

**What the report contains:** the redeemed code and nothing else. No device identifier, no
IP retention, no user identity — there is no account to attach one to.

**The gap, stated plainly:** iOS has no deferred deep link. A universal link that bounces a
new user to the App Store is *not* replayed when the app first opens, so the app only knows
a code the referee actively supplied — pasted or typed (§6). An install we can see but not
attribute is worth nothing here: App Store Connect already reports install counts for free.
So the report is not an install counter, it is a redemption courier that leaves at the
moment the network is most reliable.

**The bridge we are not building.** Matching a click to an install by IP + timestamp within
a window is the classic deferred-attribution trick, needs no SDK, and would close that gap.
It is rejected for the same reason §3 rejects Branch and AppsFlyer — it is fingerprinting
with our own name on it — and it would misfire exactly where our users are: several boats on
one marina wifi, or a whole carrier behind CGNAT, share an address and would cross-attribute.

**Infrastructure note — the host has to change.** `slackwater-web` is static on GitHub
Pages with no backend, by design; it cannot count. The lazy fit is a **Cloudflare Worker +
KV** serving `/r/*` and the redemption endpoint, holding nothing but opaque code → two
counts. But a Worker route only intercepts a **proxied** record, and every
`sailingnaturali.com` record is pinned to DNS-only because an orange cloud stops GitHub
Pages provisioning its cert (`infrastructure/dns.md`). So the Worker **cannot** live on
`slackwater.sailingnaturali.com`, which keeps serving the PWA.

It goes on the **`slackwater.xyz` apex** — decided 2026-08-21. The landing page is itself a
Cloudflare **Worker** (TanStack Start on nitro's Cloudflare preset, repo
`openwatersio/slackwater.xyz`), not a static host, so `/r/*` is simply a route in the same
app and the KV namespace binds to the Worker already serving the page. One repo, one deploy,
one hostname. Details and the record plan: `infrastructure/dns.md` § slackwater.xyz.

*An earlier draft put this on `go.slackwater.xyz`, which existed only to dodge GitHub Pages
forcing the apex to grey cloud — a constraint that disappeared with the host choice.*

**The share link is therefore `https://slackwater.xyz/r/<CODE>`**, and that is the host
the universal-link entitlement (§6) must be configured for. All of it lives in the
`openwatersio` org alongside this repo.

## 8. Granting the reward

Three ways to hand someone Premium. We use the first.

| | Mechanism | Verdict |
|---|---|---|
| **A. Local entitlement grant** | Write an expiry date next to the entitlement flag `widgets-premium-design.md` §6 already caches in shared defaults | **Chosen.** No Apple involvement, no quota, no purchase flow. The grant is a date; the widget's existing free/premium check reads it unchanged |
| B. Offer code on the yearly SKU | One-time-use batch from App Store Connect, redeemed via `presentCodeRedemptionSheet` | Rejected: **the free year auto-renews into a charge**, which is exactly the pattern §1 of the premium spec rejects. Also real batch plumbing, and quarterly generation caps to track |
| C. Promo code on the lifetime SKU | 100 per app version per 6 months | Rejected: dies the moment the program works |

Consequences of A, all accepted:

- Grants are **device-local and do not restore** on a new device. This matches the app
  today — favorites are already device-local (#134) — so it is consistent rather than a
  regression. If device sync ever ships, grants ride along with it.
- **A grant expiring is not the free core shrinking.** When the 3 months or the year ends,
  lock-screen widgets return to the quiet locked state from `widgets-premium-design.md` §4.
  Everything in the free core is untouched. No expiry notification, no win-back prompt —
  the widget simply goes quiet, consistent with the no-nag rule.
- **Referrers who already own Premium** get no stacked time. The counter still shows their
  five and thanks them; we do not build grant-stacking or gifting for this case.

## 9. What we deliberately do not build

**No fraud detection of any kind.** No device fingerprinting, no velocity limits, no
self-referral checks, no receipt validation, no rate limiting beyond whatever the Worker
does for free.

The arithmetic: everything in the Premium tier *today* computes on-device from bundled data,
so a granted year has **$0 marginal cost**. A gamed grant is forgone revenue from somebody
who was not paying, not an expense. Any fraud system would cost more to build and maintain
than the revenue it protects.

**The condition that invalidates this:** `widgets-premium-design.md` §2 promises the tier
will grow to include live observed data — weather, swell, wind overlays. Those carry real
per-user cost. At that point a cohort of free-grant holders that arrived under $0-marginal
economics becomes an actual bill. The rule to write down now, before it is a surprise:
**grants cover the on-device tier; live-data features are priced when they ship**, and that
pricing decision gets to look at the size of the granted cohort.

## 10. Surfaces

**No new upsell surface.** The referral offer lives as a second line on the **existing tier
sheet**, below the buy options:

> Don't want to pay? Share it instead. Five people who install with your code and Premium is
> yours for a year.

Plus, on the same sheet, the user's own code with a share button and a quiet `n/5` count.
That is the whole footprint. `widgets-premium-design.md` §5's closed list of three surfaces
is unchanged — this makes the tier sheet less of an ask, rather than adding a fourth place
to be asked.

## 11. Blockers and open questions

1. **Same gate as the tier itself.** `widgets-premium-design.md` §8 requires the Open Waters
   seller entity / revenue-split agreement before any paid tier ships. Giving that tier away
   for reach is a revenue decision under the same agreement, so it belongs *in* that
   conversation, not after it.
2. **Exact reward sizes** (3 months / 5 installs / 1 year) are chosen for shape, not from
   data. They are one-line constants; revisit after the first month of counts.
3. **Ordering.** Nothing here can ship before the premium spec's StoreKit entitlement and
   App Group work exists to grant against.

## 12. Out of scope

Cross-device restore of grants, gifting Premium directly, referral tiers or leaderboards,
any web/Android referral flow beyond the shared link already resolving there, and any
attribution SDK.
