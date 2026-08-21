// Slackwater — GPL v3. Station id → engine-ready station for the widget
// process. Bundled NOAA records directly; CHS stations/gates only via their
// fitted models in the shared ChsModelStore — the widget NEVER fits, never
// touches the network, never instantiates ChsFitService.
import Foundation
import TideEngine

enum WidgetStation {
    case tide(Station, tz: TimeZone, name: String)
    case current(CurrentStation, tz: TimeZone, name: String)
    case derived(DerivedSlackStation, tz: TimeZone, name: String)
}

enum WidgetStationLoader {
    static func load(id: String) -> WidgetStation? {
        guard let item = StationItem.byId[id] else { return nil }
        switch item {
        case .tide(let r):
            return .tide(r.engineStation, tz: r.tz, name: r.name)
        case .current(let r):
            return .current(r.engineStation, tz: r.tz, name: r.name)
        case .chs(let info):
            guard let model = ChsModelStore.load(info.id) else { return nil }
            let r = info.record(with: model)
            return .tide(r.engineStation, tz: r.tz, name: r.name)
        case .chsGate(let gate):
            // Mirrors DerivedGateRecord.engineGate (ChsGate.swift:40-43): the
            // reference port's fitted model → DerivedSlackStation(hwLag/lwLag).
            // nil when the reference port isn't fitted yet.
            return derivedStation(for: gate)
        case .chsCurrent(let info):
            // Mirrors ChsFitService's fitted-current path (ChsFitService.swift:179-181):
            // the "-current" suffixed model in ChsModelStore → CurrentStationRecord.
            // Online (fit-reject) gates have no "-current" model — nil, same as unfitted.
            guard let r = fittedCurrentRecord(for: info) else { return nil }
            return .current(r.engineStation, tz: r.tz, name: r.name)
        }
    }

    /// Mirrors ChsGate.swift's `DerivedGateRecord.engineGate` construction —
    /// the reference port is itself a CHS tide station, resolved by id and
    /// fitted the same way `.chs` above is.
    private static func derivedStation(for gate: ChsGateInfo) -> WidgetStation? {
        guard let portInfo = ChsStationInfo.all.first(where: { $0.id == gate.reference }),
              let model = ChsModelStore.load(portInfo.id) else { return nil }
        let port = portInfo.record(with: model)
        let derived = DerivedSlackStation(reference: port.engineStation,
                                          hwLagMinutes: gate.hwLagMinutes, lwLagMinutes: gate.lwLagMinutes)
        return .derived(derived, tz: gate.tz, name: gate.name)
    }

    /// Mirrors `ChsCurrentGateInfo.record(with:)` (ChsCurrentGate.swift:306-315),
    /// fed by the on-device fitted model — never `ChsFitService`'s in-memory cache.
    private static func fittedCurrentRecord(for info: ChsCurrentGateInfo) -> CurrentStationRecord? {
        guard let model = ChsModelStore.loadCurrent(info.id) else { return nil }
        return info.record(with: model)
    }

    /// First favorite, else most-recent, else Friday Harbor — the widget's
    /// default when unconfigured.
    static func defaultStationID() -> String {
        AppGroup.defaults.stringArray(forKey: "slackwater.favorites")?.first
            ?? AppGroup.defaults.stringArray(forKey: "slackwater.recents")?.first
            ?? TideStationRecord.fridayHarborID
    }
}
