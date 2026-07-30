# The whole stack — products, layers, and rollout order

*Written 2026-07-29; shared here 2026-07-30. The full landscape — every product we've talked
about, how they connect, and the order we ship them. Follows on from the split-by-job and
library-move plans already discussed. Same rule as always: written to be argued with.*

## The map

Four layers. Each works without the layer below it, and gets better with it.

```
  Apps (phone/tablet)     Slackwater · Charts · Equipment app
        │  boat WiFi (elevated) / own APIs (standalone)
  Boat platform (Pi)      SignalK · equipment registry · data history
        │  optional
  Agent service           OpenClaw/Poseidon + frontier models (subscription)
        │  optional
  Local compute (Mac)     Mac mini/Studio · local models · deferred work
```

### Layer 1 — the apps, split by job

Exactly the split-by-job shape from `collaboration-plan.md`, now with owners and price posture:

| App | Job (the 3-second test) | Price posture | Owner |
|---|---|---|---|
| **Slackwater** | "Tides in Nanaimo" — curve + next slack | **Low entry, no-brainer.** Polished and cheap on purpose — it's the trust ladder and the funnel | Bryan |
| **Charts** (Brandon's, own name TBD) | "Get me through the Gulf Islands Thursday" — chart with my boat on it | **Premium.** Free offline charting as the base; planning, routing, and the go-window class of features paid | Brandon |
| **Equipment app** (unnamed — name earned, not assigned) | "What's this breaker for" — search over *my boat* | TBD; free-leaning base, see levels below | Bryan |

Every app is **standalone-first**: it reaches its own APIs (tide services, chart tiles, weather)
with no boat present. But when it's on the boat network and finds a local SignalK, it **elevates**
— live vessel data overlaid on the chart, tide/current queries answered locally when there's no
cell coverage, the boat as the data source instead of the internet. The apps never *require* the
boat; the boat makes them better. That makes the Pi's discoverability on the boat network a core
platform feature, not a nice-to-have.

### Layer 2 — the boat platform (the Pi)

Offline-first data collector. SignalK today — it ingests the buses, organizes the vessel model,
and serves the boat network. Whatever the platform underneath becomes long-term, the contract the
apps depend on (local HTTP API, discoverable on the LAN, resources like the equipment registry)
is the stable surface, and evolving the platform stays a background question on the governance
ladder we've already walked — nothing here depends on it.

The platform has **levels**, and the key design point is that the lower levels need no agent and
no subscription:

1. **Data.** SignalK collecting and serving vessel data. Free, open, works forever offline.
2. **Equipment locker.** The equipment registry (`resources/equipment` — already shipped as
   `signalk-equipment-registry`) knows what's installed: manufacturer, model, serial, path
   bindings. The magic moment: plug the Pi into the NMEA network and it **auto-discovers the
   equipment** — it saw the VHF announce itself on the bus, so it goes and fetches the PDF
   manual itself. Indexed locally; the equipment app syncs that index and then works fully
   offline (interrogate your boat in an anchorage with no bars — Slackwater's offline principle
   applied to knowledge). For gear that never speaks on the bus, the agent layer closes the gap:
   **photo-to-understanding** — snap the breaker panel or the nameplate, the agent identifies it
   and files it into the registry. This is the honest merge point: we've both built the manuals
   layer independently, so it's validated and it's nobody's moat — the gathering/indexing/
   embedding pieces are Open Waters infrastructure packages.
3. **History.** Columnar trip/telemetry history (Parquet) so "what was the wind overnight?" has
   real numbers behind it — and so local models have something to chew on. Roadmap, not built.
4. **The OS layer.** What core SignalK distribution lacks: an appliance layer that keeps
   SignalK, the plugins, and the agent runtime updated automatically — the difference between
   "a server a hacker installed" and "a box that just works." Prior art exists (Hat Labs' Halos
   on the HALPI2 already auto-configures and ships SignalK preinstalled); see the hardware
   section — this wants to be a partnership, not a from-scratch build.

### Layer 3 — the agent service (the subscription)

The runtime on the Pi that understands and acts on what SignalK collects — briefings, alarm
triage, Q&A, the agent loop. OpenClaw or Poseidon; the evaluation is in flight (Cerulean proves
the OpenClaw-on-a-Pi topology works; token-cost measurement is the open gate) and the runtime
choice doesn't change the product shape.

This is the one layer with a real recurring cost — frontier-model tokens — so it's the one layer
that's honestly a **subscription**: we manage model access, route to the right models, and meter
tokens to a weekly/monthly budget inside the plan. Two doors in:

- **BYO key — free.** The open-source hacker path: bring your own provider key or subscription,
  run the same open stack, tune it yourself. It costs us nothing, it's true to the OSS posture,
  and it's how the community makes the stack better.
- **Managed — the subscription.** For the person who bought the box: models provisioned, tokens
  metered to the plan, software auto-updating, nothing to think about. The subscription isn't
  just tokens — it's *it just works*, and it's what makes the boxed product below sellable.

The pricing rule across the whole stack falls out of that: **pay once for software, subscribe
only where we carry recurring cost** (models, live observed data, updates-and-it-works). That's
consistent with the Navionics-burn sensitivity and with the tier-3 instinct — the apps stay
cheap or one-time, the recurring revenue lives where the recurring cost lives.

### Layer 4 — local compute (the Mac app)

For boats with a Mac mini/Studio aboard: a Mac app that manages the local-model side — keeps
Ollama and models installed, registers the machine with the boat platform, and lets the agent
swap between local and cloud models by connectivity and power state. This is the "run it all
locally" endgame for people who want it, and it's a distributable version of what we already run.
Later — it needs the agent layer and the history layer to matter.

### The box — a partnership, not a hardware venture

The "buy the box" answer for people who won't flash an SD card already has hardware behind it:
**Hat Labs** (Matti Airas, Finland) ships the Sailor Hat for Raspberry Pi (marine power
management + NMEA interfaces) and the **HALPI2** — a pre-built CM5 boat computer running their
Halos OS with SignalK preinstalled and pre-configured. Today that box ships *core* SignalK; what
it doesn't have is the levels above — the equipment locker, the agent runtime, the managed
subscription.

So this isn't a hardware venture — it's a **software partnership**: our stack (and eventually
the OS-layer auto-updating of it) lands on their hardware, they sell the box, we sell the
subscription that makes it just work. No inventory, no certification, no RMA desk on our side.
Prototype it ourselves first (our own Pi installs are the proving ground); approach the
partnership once the software levels are demonstrably worth bundling.

## Rollout order

Each milestone is a shippable thing with its own audience; none blocks the next from starting.

| # | Milestone | What ships | Depends on |
|---|---|---|---|
| **M1** | **Slackwater launches** | iOS + web, free core + paid planning tier. First app out, sets the design bar and the maker mark | Engine + library moves (in motion) |
| **M2** | **Charts app** | Brandon's app: free offline charting, paid planning/routing | Brandon's timeline; tides/currents embedded via the shared libraries |
| **M3** | **Equipment app + platform levels 1–2** | The Pi as a product (installable image or clear install), equipment locker fetching manuals, the companion app syncing it. No agent required | Registry (shipped), gathering/indexing packages |
| **M4** | **Agent subscription** | The runtime on the Pi as a paid service — managed models, metered tokens | Runtime decision (OpenClaw spike), M3's platform, and the biller question below |
| **M5** | **Mac local-compute app** | Local models managed, local↔cloud swap | M4 + history layer |
| **M6** | **The box** | Hat Labs partnership: our stack + OS-layer auto-updates preinstalled on HALPI2-class hardware, sold with the managed subscription | M3–M4 proven on our own installs |

## Open questions

1. **Charts pricing.** Brandon's written model is a one-time paid download with data revenue
   later; a free-offline-charting + paid-planning ladder is a different shape. Bryan to review
   the written model properly before proposing anything — Brandon owns the app and the call.
2. **Who bills the agent subscription.** A metered service needs a merchant and a model-provider
   contract before it can ship — the who-publishes-the-paid-apps question already on the table,
   now with a forcing function and a deadline (M4). It doesn't block M1–M3.
3. **Runtime.** OpenClaw vs Poseidon — bounded spike per the evaluation doc; decide on
   measurement, not hype.
4. **Android.** Standing question, unchanged; must not gate any iOS launch.
5. **Equipment app name.** Still earned, not assigned.
