// Slackwater — GPL v3. Station id → engine-ready station for the widget
// process. Bundled NOAA records directly; CHS stations/gates only via their
// fitted models in the shared ChsModelStore — the widget NEVER fits, never
// touches the network, never instantiates ChsFitService.
import Foundation
import TideEngine

enum WidgetStation {
    case tide(any TidePredicting, tz: TimeZone, name: String)
    case current(any CurrentPredicting, tz: TimeZone, name: String)
    case derived(DerivedSlackStation, tz: TimeZone, name: String)
}

/// One record per catalog kind — the loader's only decision (fitted or not,
/// which `ChsModelStore` lookup). Everything downstream (`WidgetCard.build`,
/// `load(id:)`) reads records, never `StationItem` again.
enum WidgetRecord {
    case tide(TideStationRecord, station: any TidePredicting)
    case current(CurrentStationRecord, station: any CurrentPredicting)
    case derived(DerivedGateRecord)
}

enum WidgetStationLoader {
    /// One switch over the catalog. `.chs`/`.chsGate`/`.chsCurrent` go
    /// through `ChsModelStore`'s on-device fitted models — nil when a
    /// station isn't fitted yet.
    static func loadRecord(
        id: String, locator: CatalogFileLocator = .shared
    ) -> WidgetRecord? {
        locator.load { directory in try loadRecord(id: id, directory: directory) }
    }

    private static func loadRecord(id: String, directory: URL) throws -> WidgetRecord? {
        guard let item = try StationItem.widgetItem(id: id, directory: directory) else { return nil }
        switch item {
        case .tide(let r):
            let reference: TideStationRecord? = try r.reference.flatMap {
                try catalogRecord("stations", id: $0, directory: directory)
            }
            return .tide(r, station: r.engineStation(referenceRecord: reference))
        case .current(let r):
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
            // Mirrors ChsFitService's fitted-current path (ChsFitService.swift:179-181):
            // the "-current" suffixed model in ChsModelStore → CurrentStationRecord.
            // Online (fit-reject) gates have no "-current" model — nil, same as unfitted.
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
        _ id: String, defaults: UserDefaults = AppGroup.defaults
    ) -> String {
        guard id == AppGroup.currentLocationStationID else { return id }
        if let cached = defaults.string(forKey: AppGroup.currentLocationStationKey),
           StationItem.widgetItem(id: cached) != nil { return cached }
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
