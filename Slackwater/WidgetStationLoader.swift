// Slackwater — GPL v3. Widgets use only bundled or shared saved predictions;
// the extension never fits stations or fetches from the network.
import Foundation
import TideEngine

enum WidgetStation {
    case tide(any TidePredicting, tz: TimeZone, name: String)
    case current(any CurrentPredicting, tz: TimeZone, name: String)
    case derived(DerivedSlackStation, tz: TimeZone, name: String)
}

enum WidgetRecord {
    case tide(TideStationRecord, station: any TidePredicting)
    case current(CurrentStationRecord, station: any CurrentPredicting)
    case derived(DerivedGateRecord)
}

enum WidgetStationLoader {
    /// Online gates need a saved window; widgets cannot request one themselves.
    static func loadRecord(
        id: String, at date: Date = .now, locator: CatalogFileLocator = .shared
    ) -> WidgetRecord? {
        locator.load { directory in try loadRecord(id: id, at: date, directory: directory) }
    }

    private static func loadRecord(id: String, at date: Date, directory: URL) throws -> WidgetRecord? {
        guard let item = try StationItem.widgetItem(id: id, directory: directory) else { return nil }
        switch item {
        // `widgetItem` hands back identity only (#317), so the record costs a
        // second scan of the same mapped file. ponytail: two scans, not one;
        // give `widgetItem` a record-returning sibling if this ever measures.
        case .tide(let info):
            guard let r: TideStationRecord = try catalogRecord("stations", id: info.id, directory: directory)
            else { return nil }
            let reference: TideStationRecord? = try r.reference.flatMap {
                try catalogRecord("stations", id: $0, directory: directory)
            }
            return .tide(r, station: r.engineStation(referenceRecord: reference))
        case .current(let info):
            guard let r: CurrentStationRecord = try catalogRecord("currents", id: info.id, directory: directory)
            else { return nil }
            let reference: CurrentStationRecord? = try r.reference.flatMap {
                try catalogRecord("currents", id: $0, directory: directory)
            }
            return .current(r, station: r.engineStation(referenceRecord: reference))
        case .chs(let info):
            guard let model = ChsModelStore.load(info.id) else { return nil }
            let record = info.record(with: model)
            return .tide(record, station: record.harmonicStation)
        case .chsGate(let gate):
            // Mirrors DerivedGateRecord.engineGate (ChsGate.swift:40-43): the
            // reference port's fitted model → DerivedSlackStation(hwLag/lwLag).
            // nil when the reference port isn't fitted yet.
            return try derivedRecord(for: gate, directory: directory)
        case .chsCurrent(let info):
            if info.isOnline {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = info.tz
                let neededStart = min(calendar.startOfDay(for: date),
                                      date.addingTimeInterval(-StationCardGraph.backWindow))
                let neededEnd = date.addingTimeInterval(2 * 86_400 + 6 * 3_600)
                guard let window = ChsModelStore.loadOnline(info.id)?.blocks.first(where: {
                    $0.start <= neededStart && $0.end >= neededEnd
                        && $0.times.count > 1 && $0.times.count == $0.speeds.count
                        && ($0.times.first ?? .infinity) <= neededStart.timeIntervalSince1970
                        && ($0.times.last ?? -.infinity) >= neededEnd.timeIntervalSince1970
                }) else { return nil }
                // No harmonic fit exists here; the window supplies the actual predictions.
                let record = CurrentStationRecord(
                    id: info.id, name: info.name, region: info.region, aliases: info.aliases,
                    latitude: info.latitude, longitude: info.longitude, timezone: info.timezone,
                    floodDirection: window.floodDirection, ebbDirection: window.ebbDirection,
                    meanFlow: 0, tideReference: info.tideReference, constituents: [])
                return .current(record, station: window)
            }
            return fittedCurrentRecord(for: info).map { .current($0, station: $0.harmonicStation) }
        }
    }

    static func load(id: String) -> WidgetStation? {
        loadRecord(id: id).map(station(from:))
    }

    /// The engine station a record builds — shared by `load(id:)` and the
    /// timeline provider, which loads the record once and derives both the
    /// snapshot's station and the card from it.
    static func station(from record: WidgetRecord) -> WidgetStation {
        switch record {
        case .tide(let r, let station): .tide(station, tz: r.tz, name: r.name)
        case .current(let r, let station): .current(station, tz: r.tz, name: r.name)
        case .derived(let r): .derived(r.engineGate, tz: r.gate.tz, name: r.gate.name)
        }
    }

    /// The reference port is itself a CHS tide station, resolved by id and
    /// fitted the same way `.chs` above is.
    private static func derivedRecord(for gate: ChsGateInfo, directory: URL) throws -> WidgetRecord? {
        let ports: [ChsStationInfo] = try readCatalog("chs-stations", directory: directory)
        guard let portInfo = ports.first(where: { $0.id == gate.reference }),
              let model = ChsModelStore.load(portInfo.id) else { return nil }
        return .derived(DerivedGateRecord(gate: gate, port: portInfo.record(with: model)))
    }

    /// Mirrors `ChsCurrentGateInfo.record(with:)` (ChsCurrentGate.swift:306-315),
    /// fed by the on-device fitted model — never `ChsFitService`'s in-memory cache.
    private static func fittedCurrentRecord(for info: ChsCurrentGateInfo) -> CurrentStationRecord? {
        guard let model = ChsModelStore.loadCurrent(info.id) else { return nil }
        return info.record(with: model)
    }

    static func resolvedStationID(
        _ id: String,
        defaults: UserDefaults = AppGroup.defaults,
        locator: CatalogFileLocator = .shared
    ) -> String {
        let cacheKey: String? = switch id {
        case AppGroup.currentLocationStationID: AppGroup.currentLocationStationKey
        case AppGroup.nearestTideStationID: AppGroup.nearestTideStationKey
        case AppGroup.nearestCurrentStationID: AppGroup.nearestCurrentStationKey
        default: nil
        }
        guard let cacheKey else { return id }
        if let cached = defaults.string(forKey: cacheKey),
           StationItem.widgetItem(id: cached, locator: locator) != nil { return cached }
        return fallbackStationID(defaults: defaults)
    }

    /// Current Location follows the app's latest fix and is the widget's
    /// zero-configuration default.
    static func defaultStationID() -> String {
        AppGroup.currentLocationStationID
    }

    /// No fix: first favorite, else most-recent, else Friday Harbor.
    static func fallbackStationID(defaults: UserDefaults = AppGroup.defaults) -> String {
        defaults.stringArray(forKey: AppGroup.favoritesKey)?.first
            ?? defaults.stringArray(forKey: AppGroup.recentsKey)?.first
            ?? TideStationRecord.fridayHarborID
    }
}

extension ChsOnlineWindow: CurrentPredicting {
    func speeds(from start: Date, to end: Date, step: TimeInterval) -> [CurrentPoint] {
        guard step > 0, times.count > 1, times.count == speeds.count, let first = times.first,
              let last = times.last else { return [] }
        var result: [CurrentPoint] = []
        var time = start.timeIntervalSince1970
        var index = 1
        while time <= end.timeIntervalSince1970 {
            if time >= first && time <= last {
                while index < times.count - 1 && times[index] < time { index += 1 }
                let span = times[index] - times[index - 1]
                guard span > 0 else { return [] }
                // CHS samples are 15 minutes apart; widget readings also land between them.
                let fraction = (time - times[index - 1]) / span
                let value = speeds[index - 1] + (speeds[index] - speeds[index - 1]) * fraction
                result.append(CurrentPoint(time: Date(timeIntervalSince1970: time), speed: value))
            }
            time += step
        }
        return result
    }

    func events(from start: Date, to end: Date) -> [CurrentEvent] {
        sampleEvents(points).filter { $0.time >= start && $0.time <= end }
    }
}
