// Slackwater — GPL v3. Bundled NOAA current stations read by id from the
// memory-mapped currents.tcdb that tools/gen-noaa-currents.mjs writes (#902).
import Foundation
import SlackwaterDatabase

/// Opens a catalog generation's current stations.
func currentDatabase(directory: URL) throws -> StationDatabase {
    try stationDatabase("currents", directory: directory)
}

/// One current station and, for a subordinate, the reference it reduces
/// from, out of a directory's database.
func currentRecord(id: String, directory: URL) throws -> CurrentStationRecord? {
    try currentDatabase(directory: directory).station(id: id).map(CurrentStationRecord.init)
}

extension CurrentStationRecord {
    /// The bundled database, mapped once for the life of the process. A
    /// missing or unreadable bundle is terminal, as it is for every catalog.
    static let database: StationDatabase = {
        do { return try currentDatabase(directory: Bundle.main.resourceURL ?? Bundle.main.bundleURL) }
        catch {
            CatalogDiagnostics.log(error)
            preconditionFailure(String(describing: error))
        }
    }()

    static func record(id: String) -> CurrentStationRecord? {
        database.station(id: id).map(CurrentStationRecord.init)
    }

    /// Every bundled station, alphabetical. This decodes every station's
    /// constituents, so the app looks stations up with `record(id:)` instead.
    static let all: [CurrentStationRecord] = database.map(CurrentStationRecord.init)
        .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }

    /// The engine's record for one database station, as currents.json spells
    /// it. The name, region, timezone and pairing are the ones gen-noaa-currents
    /// resolved and wrote over the database's row.
    init(_ station: SlackwaterDatabase.Station) {
        let current = station.current
        let offsets = current?.offsets
        let minute: (Int?) -> Double? = { $0.map { Double($0) * 60 } }
        self.init(
            id: station.id,
            name: station.name,
            region: station.region ?? "",
            aliases: station.aliases,
            latitude: station.latitude,
            longitude: station.longitude,
            timezone: station.timezone ?? "",
            floodDirection: thousandths(current?.floodDirection ?? 0),
            ebbDirection: thousandths(current?.ebbDirection ?? 0),
            meanFlow: thousandths(current?.meanFlow ?? 0),
            tideReference: current?.tideReference,
            constituents: station.constituents.map(Con.init),
            reference: offsets?.reference,
            slackBeforeFloodOffset: minute(offsets?.slackBeforeFlood),
            slackBeforeEbbOffset: minute(offsets?.slackBeforeEbb),
            floodTimeOffset: minute(offsets?.floodTime),
            ebbTimeOffset: minute(offsets?.ebbTime),
            floodSpeedRatio: offsets?.floodSpeedRatio.map(thousandths),
            ebbSpeedRatio: offsets?.ebbSpeedRatio.map(thousandths),
            // A non-primary bin is in the database only as a subordinate's
            // reference (#269), and its id is the only kind with an "@".
            referenceOnly: station.id.contains("@") ? true : nil,
            // The reader reads an empty minor vector as none; a station that
            // publishes a cross-flow mean without constants still has the axis.
            minorConstituents: current?.minorConstituents.map { $0.map(Con.init) }
                ?? (current?.minorMeanFlow == nil ? nil : []),
            minorMeanFlow: current?.minorMeanFlow.map(thousandths),
            azimuth: current?.azimuth.map(thousandths))
    }
}

private extension Con {
    init(_ c: SlackwaterDatabase.Station.Constituent) {
        self.init(name: c.name, amplitude: thousandths(c.amplitude), phase: thousandths(c.phase))
    }
}

/// gen-noaa-currents writes every value to three places and the file stores
/// them float32, so rounding back recovers the generator's value exactly
/// (0.79 reads 0.7900000214576721). The records then equal currents.json's,
/// which the catalog validation and the tests compare against.
private func thousandths(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
