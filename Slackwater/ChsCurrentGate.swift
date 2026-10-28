// Slackwater — GPL v3. Curated year-round CHS current gate evidence.
import Foundation
import SlackwaterKit

/// Bundled identity for one validated CHS current gate.
struct ChsCurrentGateInfo: Decodable, Identifiable, Hashable, StationIdentity {
    let id: String        // registry key, e.g. "chs-dodd-narrows"
    let name: String
    let region: String
    let aliases: [String]
    let latitude: Double
    let longitude: Double
    let timezone: String
    /// Registry pairing: a bundled CHS tide port whose water renders as the
    /// second track above the gate's current strip. Absent = current-only.
    let tideReference: String?
    let fitDays: Double
    let provisionalSlackMinutes: Int?
    var online: Bool? = nil
    var slackBoundMinutes: Int? = nil
    var recipe: String? = nil
    var onlineMiss: ChsCurrentOnlineMiss? = nil
    var missContext: String? = nil
    var magnitudeNote: String? = nil

    var isBounded: Bool { !isOnline && slackBoundMinutes != nil }
    var isOnline: Bool { online ?? false }

    var tz: TimeZone { TimeZone(identifier: timezone) ?? .current }

    /// The trailing 60 days — every gate's first fit, and a prefix of the
    /// 210-day fetch, so a provisional answer costs no extra request.
    static let provisionalDays = 60.0

    /// Does this gate get a fast answer before its full model? Only when the
    /// full window is longer than the provisional one AND the measured 60-day
    /// error cleared the floor (both encoded in the bundle by gen-chs-gates).
    var offersProvisional: Bool { fitDays > Self.provisionalDays && provisionalSlackMinutes != nil }

    static let all: [ChsCurrentGateInfo] = bundled("chs-current-gates")
}

struct ChsCurrentOnlineMiss: Decodable, Hashable {
    let clause: String
    let value: Double?
    var nearBar: Bool? = nil
}

/// The gate model's pre-merge name (see ChsModel) — SlackwaterTests still
/// spells it.
typealias ChsCurrentModel = ChsModel

extension ChsModelStore {
    /// Gate models live beside the port models, suffixed so a gate model never
    /// shadows a port model of the same key.
    static func currentUrl(_ stationID: String) -> URL { url(stationID, suffix: "-current") }
    static func loadCurrent(_ stationID: String) -> ChsModel? { load(stationID, suffix: "-current") }
    static func usableCurrent(_ stationID: String) -> ChsModel? {
        guard let gate = ChsCurrentGateInfo.all.first(where: { $0.id == stationID }),
              let model = loadCurrent(stationID) else { return nil }
        return gate.usableModel(model)
    }
    static func saveCurrent(_ model: ChsModel) throws { try save(model, id: model.stationID, suffix: "-current") }

    /// The online gate's fetched window lives beside the fitted models, under
    /// its own suffix — same reason `-current.json` doesn't shadow `.json`.
    static func onlineUrl(_ stationID: String) -> URL { url(stationID, suffix: "-online") }

    /// Store decode first, then the legacy single-window shape (schemaVersion 1,
    /// pre-#67): each fails cleanly on the other's bytes (`blocks` vs
    /// `times`/`speeds` are required keys), so the order is just preference.
    /// The first save rewrites the file in the store shape.
    ///
    /// Decoded stores are memoized because callers treat this as a cheap
    /// getter — the downloads manager reads it inside a sort comparator, per
    /// row, per body evaluation — while the file behind it can reach ~1MB
    /// (`saveOnline`'s no-forward-cap note). Uncached, one render was
    /// hundreds of main-thread decodes and the scene-update watchdog killed
    /// the app at 10s (0x8BADF00D, build 31). The entry is validated by the
    /// file's mtime+size rather than invalidated at call sites, so every
    /// writer and deleter — `saveOnline`, the orphan prune, `-chsResetModels`,
    /// tests using raw FileManager — stays correct without knowing a cache
    /// exists. A file that fails both decodes is cached as nil, so a bad file
    /// (a newer schema after a downgrade) costs one decode until it changes.
    static func loadOnline(_ stationID: String) -> ChsOnlineStore? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: onlineUrl(stationID).path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int else { return nil }
        onlineCacheLock.lock()
        defer { onlineCacheLock.unlock() }
        if let hit = onlineCache[stationID], hit.mtime == mtime, hit.size == size { return hit.store }
        // A read can fail and then succeed with the file unchanged (data
        // protection before first unlock, in the widget), so only a decode
        // failure is cached.
        guard let data = try? Data(contentsOf: onlineUrl(stationID)) else { return nil }
        let decoder = JSONDecoder()
        let store: ChsOnlineStore?
        if let s = try? decoder.decode(ChsOnlineStore.self, from: data) {
            store = s
        } else if let legacy = try? decoder.decode(ChsOnlineWindow.self, from: data) {
            store = ChsOnlineStore(stationID: legacy.stationID, blocks: [legacy])
        } else {
            store = nil
        }
        onlineCache[stationID] = (mtime, size, store)
        return store
    }

    // Every access holds onlineCacheLock, including decoding and replacement.
    nonisolated(unsafe) private static var onlineCache: [String: (mtime: Date, size: Int, store: ChsOnlineStore?)] = [:]
    private static let onlineCacheLock = NSLock()
}

/// Where the next speculative fetch starts: the local midnight at the stored
/// window's far edge. Blocks land on `chunkPlan`'s absolute 7-day grid, so the
/// overlap this creates costs nothing and the seam can never leave a gap.
func prefetchAnchor(after window: ChsOnlineWindow, tz: TimeZone) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.startOfDay(for: window.end)
}

// MARK: - The fetched window (online gates: official CHS predictions, no fit)

/// A window of official CHS current predictions for one online (fit-reject)
/// gate — fetched on demand, never fitted, kept local like the fitted models.
/// `start`/`end` is the span the samples actually cover — 30 days forward of
/// the fetch's anchor, `Timeline.window`'s back-pad behind it — and it grows
/// as later fetches merge in (`merging`). So a stale window is a coverage
/// question, not a staleness heuristic — see `covers`.
struct ChsOnlineWindow: Codable, Sendable {
    var schemaVersion = 1
    let stationID: String
    let iwlsName: String
    /// The gate's own timezone (added beyond the brief's shape), carried
    /// alongside the window's dates without reaching back into the bundled
    /// gate identity.
    let timezone: String
    let fetchedAt: Date
    let start: Date            // Timeline.window(anchor:).start at fetch, pruned forward
    let end: Date              // anchor + Timeline.onlineFetchDays, clamped to the samples
    let floodDirection: Double // IWLS metadata at fetch time, kept local
    let ebbDirection: Double
    let times: [Double]        // epoch seconds, official samples on `ChsGrid`
    let speeds: [Double]       // signed kn along the flood axis (project())

    var points: [CurrentPoint] {
        zip(times, speeds).map { CurrentPoint(time: Date(timeIntervalSince1970: $0), speed: $1) }
    }

    /// Stored online bounds are clamped to the last returned sample, so two
    /// blocks requested to abut can arrive one sample apart. This tolerates
    /// that finite-window seam without bridging a wider hole. It does not make
    /// HTTP endpoints exclusive: complete fitting weeks include both endpoints.
    static let sampleInterval = ChsGrid.seconds

    func signedSpeed(at date: Date) -> Double? {
        let t = date.timeIntervalSince1970
        guard times.count == speeds.count, let first = times.first, let last = times.last,
              t >= first, t <= last else { return nil }
        var lo = 0, hi = times.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if times[mid] < t { lo = mid + 1 } else { hi = mid }
        }
        if times[lo] == t { return speeds[lo] }
        guard lo > 0, times[lo] - times[lo - 1] <= Self.sampleInterval else { return nil }
        let fraction = (t - times[lo - 1]) / (times[lo] - times[lo - 1])
        return speeds[lo - 1] + fraction * (speeds[lo] - speeds[lo - 1])
    }

    /// Union `other`'s samples into this window by timestamp and widen the
    /// bounds, dropping everything before `prunedBefore`.
    ///
    /// Union, not append: the fetch chunks land on an absolute 7-day grid, so
    /// a refetch routinely overlaps what is already stored, and appending
    /// would hand `sampleEvents` a series with every overlapped sample twice.
    ///
    /// `start` follows the prune. If it did not, `covers` would keep claiming
    /// a range whose samples had just been deleted.
    func merging(_ other: ChsOnlineWindow, prunedBefore: Date) -> ChsOnlineWindow {
        // Two blocks separated by more than a sample have no samples between
        // them, and a window spanning both would answer `covers` true for an
        // anchor in the gap — the same lie as an unpruned `start`, from the
        // other end. The newer block wins outright, prune and all: it is a
        // fresh fetch, whose own start is never earlier than the cut.
        let slack = Self.sampleInterval
        guard start <= other.end.addingTimeInterval(slack),
              other.start <= end.addingTimeInterval(slack) else { return other }
        let cut = prunedBefore.timeIntervalSince1970
        var byTime = Dictionary(zip(times, speeds), uniquingKeysWith: { _, b in b })
        for (t, v) in zip(other.times, other.speeds) { byTime[t] = v }
        let kept = byTime.filter { $0.key >= cut }.sorted { $0.key < $1.key }
        return ChsOnlineWindow(
            stationID: stationID, iwlsName: other.iwlsName, timezone: timezone,
            fetchedAt: other.fetchedAt,
            start: max(min(start, other.start), prunedBefore),
            end: max(end, other.end),
            floodDirection: other.floodDirection, ebbDirection: other.ebbDirection,
            times: kept.map(\.key), speeds: kept.map(\.value))
    }

    /// This window with everything before `cut` dropped — nil when nothing
    /// survives. `start` follows the cut for `merging`'s reason: an unpruned
    /// start keeps `covers` claiming a range whose samples are gone.
    func pruned(before cut: Date) -> ChsOnlineWindow? {
        guard start < cut else { return self }
        guard end > cut else { return nil }
        let c = cut.timeIntervalSince1970
        let kept = zip(times, speeds).filter { $0.0 >= c }
        return ChsOnlineWindow(stationID: stationID, iwlsName: iwlsName, timezone: timezone,
                               fetchedAt: fetchedAt, start: cut, end: end,
                               floodDirection: floodDirection, ebbDirection: ebbDirection,
                               times: kept.map { $0.0 }, speeds: kept.map { $0.1 })
    }
}

/// The on-disk shape for an online gate (#67 item 4): DISJOINT fetched
/// blocks, sorted by start. The single start/end window before it made every
/// disjoint merge lossy — a far-forward pick discarded today's block, and
/// paging back refetched ~30 days the app had just held. Blocks stay pairwise
/// separated by more than `sampleInterval`; anything closer merges on save.
/// Coverage questions go to a SINGLE block: the gap between blocks has no
/// samples, and claiming it renders a strip with a dead zone.
struct ChsOnlineStore: Codable {
    var schemaVersion = 2
    let stationID: String
    let blocks: [ChsOnlineWindow]

    /// The block whose span contains `window`'s — what `saveOnline` returns:
    /// the caller's copy must never be narrower than the disk's.
    func block(spanning window: ChsOnlineWindow) -> ChsOnlineWindow? {
        blocks.first { $0.start <= window.start && $0.end >= window.end }
    }

    /// Union `window` in: absorb every stored block that overlaps or abuts it
    /// (within `sampleInterval` slack — the seam a clamped fetch end
    /// produces), keep the rest, prune everything to `cut`, drop empties.
    /// One ascending pass absorbs a chain: stored blocks are pairwise
    /// disjoint, so only the incoming block can bridge two of them, and
    /// sorted order means it meets each neighbour after absorbing the last.
    /// `merging`'s own disjoint guard never fires here — the test above is
    /// the same test it applies.
    func inserting(_ window: ChsOnlineWindow, prunedBefore cut: Date) -> ChsOnlineStore {
        let slack = ChsOnlineWindow.sampleInterval
        var merged = window
        var rest: [ChsOnlineWindow] = []
        for b in blocks.sorted(by: { $0.start < $1.start }) {
            if b.start <= merged.end.addingTimeInterval(slack),
               merged.start <= b.end.addingTimeInterval(slack) {
                merged = b.merging(merged, prunedBefore: cut)
            } else if let kept = b.pruned(before: cut) {
                rest.append(kept)
            }
        }
        if let kept = merged.pruned(before: cut) { rest.append(kept) }
        return ChsOnlineStore(stationID: stationID,
                              blocks: rest.sorted { $0.start < $1.start })
    }
}

extension ChsCurrentGateInfo {
    func usableModel(_ model: ChsModel) -> ChsModel? {
        guard !isOnline, model.stationID == id,
              let recipe, recipe == ChsCurrentFit.stamp,
              model.recipe == recipe, let days = model.fitDays else { return nil }
        guard days == fitDays || (offersProvisional && days == Self.provisionalDays) else { return nil }
        return model
    }

    func isProvisional(_ model: ChsModel) -> Bool {
        usableModel(model) != nil && offersProvisional && model.fitDays == Self.provisionalDays
    }

    func cachedReading(at date: Date) -> (signedKn: Double, floodDirection: Double)? {
        if isOnline {
            guard let window = ChsModelStore.loadOnline(id)?.blocks.first(where: { $0.start <= date && date <= $0.end }),
                  let signed = window.signedSpeed(at: date) else { return nil }
            return (signed, window.floodDirection)
        }
        guard let model = ChsModelStore.usableCurrent(id),
              let signed = record(with: model).engineStation
                .speeds(from: date, to: date.addingTimeInterval(1), step: 1).first?.speed else { return nil }
        return (signed, model.floodDirection ?? 0)
    }

    /// A fitted CHS gate renders through the exact same record/engine/view path
    /// as a bundled NOAA current station — provenance shows only in the footer.
    func record(with model: ChsModel) -> CurrentStationRecord {
        CurrentStationRecord(
            id: id, name: name, region: region, aliases: aliases,
            latitude: latitude, longitude: longitude, timezone: timezone,
            // A gate fit always stores the axis; nil is the merged model's
            // tide-port side, which never reaches here (the store suffixes).
            floodDirection: model.floodDirection ?? 0, ebbDirection: model.ebbDirection ?? 0,
            meanFlow: model.offset, tideReference: tideReference,
            constituents: model.constituents)
    }
}

extension CurrentStationRecord {
    /// Fitted-on-device CHS gate, vs a bundled NOAA harmonic station.
    var isChs: Bool { id.hasPrefix("chs-") }
    /// This record's `StationItem` id — what the favorite star and the
    /// Recents record must write for the list to resolve it. NOAA current
    /// stations are namespaced "current:<id>" (Friday Harbor has both a tide
    /// and a current station); a CHS gate keys the catalog bare. Hand-building
    /// the prefixed form at a call site minted favorites no section could
    /// resolve (fresh-install bug, 2026-08-08).
    var itemId: String { isChs ? id : "current:" + id }
    /// The bundled gate identity behind a fitted CHS record — where the
    /// per-gate window and the fast answer's tolerance live.
    var chsGate: ChsCurrentGateInfo? { ChsCurrentGateInfo.all.first { $0.id == id } }
}
