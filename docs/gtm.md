# Slackwater — Go-to-Market

*Private — not for public posts. Started 2026-07-17. Grounded in [market-research-2026-07-17.md](research/market-research-2026-07-17.md).*

## The core insight

The Sailing Naturali YouTube/charter audience (40–55 tech execs — see
`planning/content-strategy.md`) is **not** Slackwater's user. Slackwater's user is a
PNW boater / paddler / fisherman who needs trustworthy current timing. Near-zero overlap.
YouTube sells the brand and the build story; it does **not** move app installs.
Slackwater needs its own distribution, aimed at people already on the water — and the
market research already mapped exactly where they are and what they complain about.

Keep launch timing / roadmap out of any public post (technical & utility framing only).

## Channels, ranked by leverage

| # | Channel | Wedge | Status |
|---|---------|-------|--------|
| 1 | **App Store ASO** | Own the geography keywords nobody else does (Salish Sea, BC currents, Gulf Islands); offline + US-and-Canada differentiator in title/subtitle | Metadata drafted ↓ — do first |
| 2 | **PNW forums** — Sailing Anarchy, Trawler Forum, WestCoastPaddler, sailboatowners, r/sailing, r/kayaking | People literally cobble DeepZoom + chartplotter + printed Ports & Passes; be the answer to "best currents app for the Salish Sea" | Reply template drafted ↓; ongoing, in Bryan's voice, disclosed |
| 3 | **Regional word-of-mouth** — RVYC, Bluewater Cruising Assoc., Council of BC Yacht Clubs, Victoria paddling clubs, marina boards | Region-specific app + member with warm intros | Bryan running this himself |
| 4 | **Accuracy "receipts" post** — golden-vector validation, with the CHS datum / LAT-offset ("why our numbers read higher than the printed tables — and why that's correct") as the hook | The niche's graveyard is accuracy complaints; *provable* accuracy is the marketing | **P2** credibility anchor. **Angle chosen 2026-07-17.** Was going to be a "CHS stations mislocated on land" gotcha — **probed and killed same day** (9/15 Salish stations flag on-land at 1km mask, but that's channel-width artifact in the narrows, not CHS error; CHS coords are basically right). Offline was rejected as an accuracy angle: *offline-but-wrong is worse than online-but-right* — accuracy is the precondition, not a co-selling-point. |
| 5 | **Niche marine press** — 48° North, Three Sheets NW, Waggoner, Good Old Boat | Regional press covers regional tools | 48° North pitch drafted ↓ (recipient TBC) |
| 6 | **OSS cross-pollination** — SignalK community, openwatersio/Neaps, XTide crowd | A **fully open** consumer app (GPL app on the same MIT harmonic engine you know) in an all-proprietary field → high-credibility evangelists | Bryan to post in SignalK off-topic **after** clearing with bkeepers (note drafted) |
| 7 | **DeepZoom users** | *Not a separate channel* — DeepZoom is web-only, same people as #2. "DeepZoom in your pocket, offline" is just the framing for the forum reply. Optional friendly note to its solo maker (complementary, no overlap) | Folded into #2 |
| 8 | **Offline-tides threads beyond boaters** — r/Garmin, dive/spearfishing/watch crowd. Example: [Descent "tides app that works offline?" (Dec 2025)](https://www.reddit.com/r/Garmin/comments/1ptsnma/garming_descent_any_good_tides_app_you_recommend/) — spearfisher, no signal at the spot, top reply is "cache before you go, data expires" | Same pain (#2's wedge) voiced *outside* the boater bubble — proof offline-first isn't a niche ask. Engage genuinely, feedback-ask first (per template #2), **never necro-spam a pile of old threads** — one honest reply where it fits | Added 2026-08-20 (Bryan). Caveat: that OP is UK — outside US/Canada station coverage — so use for pain validation + genuine replies where coverage fits |

## The lazy first sequence

Three free moves where users already are, before any campaign:
1. **ASO** — compounding, metadata-only.
2. **Be present on #2 forums** as yourself, answering real threads (not launch spam).
3. **One accuracy/corrections post** (#4), cross-posted to forums + pitched to 48° North.

Everything else is a follow-on once those show signal. The engineering blog reaches
developers, not boaters — good for OSS credibility (#6), **not** counted as GTM.

## Drafted assets

### #1 ASO metadata
- **Title** (≤30): `Slackwater — Tides & Currents`
- **Subtitle** (≤30): `Offline currents, US & Canada` *(recommended; alts: `Salish Sea slack & tide timing`, `Tides, currents & slack alerts`)*
- **Keywords** (≤100, no spaces, name/title words omitted):
  `salish sea,gulf islands,juan de fuca,ebb,flood,kayak,paddle,sail,fishing,puget sound,knot,boating`
- **First description line:** *Slack and max-current timing you can trust — offline, US and Canadian waters, no subscription.*

### #2 Forum reply template (Bryan's voice, disclosed)
> I got tired enough of cobbling DeepZoom + the chartplotter + a printed Ports & Passes
> that I built my own — Slackwater. Full disclosure, it's mine. It's offline-first, so it
> still works when you're out past cell coverage in the islands, and it covers both US and
> Canadian stations, which is the part everything else gets wrong up here. What I actually
> care about is slack and max timing you can trust — I'm validating predictions against
> known-good vectors, not eyeballing a tide curve. Free core, no ads, no account. Honestly
> I'd rather hear where the timing's off than rack up downloads, so if you run it against
> Active Pass or Race Passage and it's wrong, tell me and I'll chase it.

### #5 48° North pitch — see chat draft (recipient TBC, hold for review)
### #6 bkeepers note — see chat draft
