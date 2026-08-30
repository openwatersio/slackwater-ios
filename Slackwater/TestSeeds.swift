// Slackwater — GPL v3. UI-test seed hooks: the -seed*/-resetGate launch
// arguments SlackwaterApp.init honours, and the synthetic state they write.
import Foundation

#if DEBUG
/// The launch-argument hooks a UI test drives the app with, applied once from
/// `SlackwaterApp.init` before anything reads the state they write.
func applySeedHooksIfRequested() {
    // UI-test hooks, like -chsResetModels: -resetGate forces the first-run
    // gate; -seedGate skips it (arguments-domain values would mask the
    // in-app write, so tests set persisted state explicitly instead).
    if CommandLine.arguments.contains("-resetGate") {
        UserDefaults.standard.removeObject(forKey: seenGateKey)
    }
    if CommandLine.arguments.contains("-seedGate") {
        UserDefaults.standard.set(true, forKey: seenGateKey)
    }
    // -seedTideModel <id> (UserDefaults argument domain): writes a
    // synthetic fitted model for one bundled CHS tide port, so a derived
    // gate whose reference it is (Malibu Rapids ← Point Atkinson) renders
    // its detail offline in the fast plan. Opposite ordering trap to
    // -seedOnlineWindow below: ChsFitService.shared's init reads the model
    // directory ONCE into `tideRecords`, so this seed must be on disk
    // BEFORE anything touches `.shared` — and never combined with
    // -chsResetModels, whose wipe runs inside that same later init and
    // would delete the seed. The hook wipes the store itself instead.
    if let id = UserDefaults.standard.string(forKey: "seedTideModel") {
        seedTideModel(stationID: id)
    }
    // -seedOnlineWindow <id> (UserDefaults argument domain): writes a
    // fetched-looking ChsOnlineWindow for one of the 7 online (fit-reject)
    // gates, so a UI test can land on OnlineGateDetailView's fetched
    // single-track detail with no network.
    if let id = UserDefaults.standard.string(forKey: "seedOnlineWindow") {
        // Trap: ChsFitService.shared's own init calls
        // ChsModelStore.resetIfRequested(), which wipes ChsModelStore.dir
        // — the same directory the seed file below lands in. `shared` is a
        // lazy `static let`, so if nothing has touched it yet, its init
        // (and the wipe) fires the first time something does — e.g. the
        // list view's `.task` — which would run AFTER this seed write and
        // silently delete it. Touch `.shared` now so the one-time
        // init/reset happens before the write, never after.
        _ = ChsFitService.shared
        seedOnlineWindow(stationID: id)
    }
    // -seedOnlineFarWindow <id>: same trap, same fix — a second, DISJOINT
    // seeded block (#67 item 4) for the hermetic two-block UI proof.
    if let id = UserDefaults.standard.string(forKey: "seedOnlineFarWindow") {
        _ = ChsFitService.shared
        seedOnlineFarWindow(stationID: id)
    }
}

/// UI-test hook (`-seedTideModel <id>`): a plausible M2+K1 harmonic model for
/// one bundled CHS tide port, stored as if fitted on this device — the
/// reference-port fit a derived gate's slacks derive from, with no network
/// (issue #38). Amplitudes/offset are Point-Atkinson-ish metres; any
/// plausible shape gives TideEngine real highs and lows to lag into slacks.
/// Wipes the model store AND the chunk store first, so the seed is the WHOLE
/// state `ChsFitService.init` finds — determinism without `-chsResetModels`,
/// which this hook must never be combined with (see the init comment). The
/// chunk store matters as much as the model one: a leftover chunk from a
/// full-plan run lets the derived gate render off cached CHS predictions
/// instead of this fit, and the test then passes without exercising what it
/// names.
private func seedTideModel(stationID: String) {
    guard ChsStationInfo.all.contains(where: { $0.id == stationID }) else { return }
    try? FileManager.default.removeItem(at: ChsModelStore.dir)
    try? FileManager.default.removeItem(at: ChsChunkStore.dir)
    let now = appNow()
    let model = ChsModel(
        stationID: stationID, iwlsID: "seeded", iwlsName: "\(stationID) (seeded)",
        fittedAt: now, fitStartMs: (now.timeIntervalSince1970 - 60 * 86_400) * 1000,
        fitEndMs: now.timeIntervalSince1970 * 1000,
        offset: 3.0, rms: 0.05,
        constituents: [Con(name: "M2", amplitude: 1.5, phase: 0),
                       Con(name: "K1", amplitude: 0.9, phase: 90)])
    try? ChsModelStore.save(model)
}

/// UI-test hook (`-seedOnlineWindow <id>`): writes a
/// synthetic `ChsOnlineWindow` covering exactly `Timeline.window(anchor:)`'s
/// span for today — the same definition `ChsFitService.fetchOnlineWindow` uses
/// for a real fetch (`covers`'s neighborhood, ChsCurrentGate.swift) — so
/// `OnlineGateDetailView` reads it as
/// current and renders the fetched detail on first launch, no network
/// involved. An M2-ish sine (12.42h period, ~2 kn amplitude) at 15-min samples
/// gives the strip real slacks and maxima to assert against, not a flat line.
///
/// `-chsResetModels` (ChsStation.swift) already clears this file too: it
/// removes the whole `ChsModelStore.dir`, the same directory `-online.json`
/// files live in beside the fitted `.json`/`-current.json` ones
/// (`ChsModelStore.onlineUrl`) — nothing extra to wipe there.
private func seedOnlineWindow(stationID: String) {
    seedOnline(stationID: stationID, offsetDays: nil, spanDays: nil)
}

/// UI-test hook (`-seedOnlineFarWindow <id>`): like
/// `seedOnlineWindow`, but a DISJOINT far block — [today+30d, today+85d],
/// wide enough that "two months out, cell 10" in the picker always lands a
/// whole strip inside it, and far enough that it can never merge with
/// today's block. Written through `saveOnline` so the test exercises the
/// real disjoint-save path (#67 item 4).
private func seedOnlineFarWindow(stationID: String) {
    seedOnline(stationID: stationID, offsetDays: 30, spanDays: 55)
}

/// nil offset = today's real window (`Timeline.window(anchor: today)`); an
/// offset seeds [today+offset, today+offset+span] instead.
private func seedOnline(stationID: String, offsetDays: Int?, spanDays: Int?) {
    guard let gate = ChsCurrentGateInfo.all.first(where: { $0.id == stationID }) else { return }
    let today = todayLocal(gate.tz)
    let start: Date, end: Date
    if let offsetDays, let spanDays {
        // Calendar days in the gate's zone, not seconds — a seeded window a
        // fixed 86,400 s off drifts an hour across a DST boundary.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = gate.tz
        start = cal.date(byAdding: .day, value: offsetDays, to: today)!
        end = cal.date(byAdding: .day, value: spanDays, to: start)!
    } else {
        let w = Timeline.window(anchor: today)
        start = w.start; end = w.end
    }
    let period = 12.42 * 3600.0   // M2 tidal period, seconds
    let amplitude = 2.0           // kn
    var times: [Double] = []
    var speeds: [Double] = []
    var t = start
    while t <= end {
        times.append(t.timeIntervalSince1970)
        speeds.append(amplitude * sin(2 * .pi * t.timeIntervalSince(start) / period))
        t = t.addingTimeInterval(900)  // 15-min official-sample cadence
    }
    let window = ChsOnlineWindow(
        stationID: gate.id, iwlsName: "\(gate.name) (seeded)", timezone: gate.timezone,
        fetchedAt: appNow(), start: start, end: end,
        floodDirection: 0, ebbDirection: 180, times: times, speeds: speeds)
    // `_ =` because `try?` re-wraps the merged window `saveOnline` returns,
    // and @discardableResult doesn't survive the Optional.
    _ = try? ChsModelStore.saveOnline(window)
}

#endif
