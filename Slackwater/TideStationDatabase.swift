// Slackwater — GPL v3. Bundled tide stations read by id from the memory-mapped
// stations.tcdb that tools/gen-tides.mjs writes (#459).
import Foundation
import SlackwaterDatabase

/// Opens a catalog generation's tide stations. Mapping the file reads nothing
/// but its 8-byte header; each lookup is a binary search that pages in only
/// the station it finds.
func tideDatabase(directory: URL) throws -> StationDatabase {
    let url = directory.appendingPathComponent("stations.tcdb")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CatalogError(resource: "stations", stage: .lookup, reason: "file missing")
    }
    do { return try StationDatabase(contentsOf: url) }
    catch is InvalidStationDatabase {
        throw CatalogError(resource: "stations", stage: .decode, reason: "not a station database")
    } catch {
        throw CatalogError(resource: "stations", stage: .read, reason: "unable to read file")
    }
}

func tideRecord(id: String, directory: URL) throws -> TideStationRecord? {
    try tideDatabase(directory: directory).station(id: id).map(TideStationRecord.init)
}

extension TideStationRecord {
    /// The bundled database, mapped once for the life of the process. A
    /// missing or unreadable bundle is terminal, as it is for every catalog.
    static let database: StationDatabase = {
        do { return try tideDatabase(directory: Bundle.main.resourceURL ?? Bundle.main.bundleURL) }
        catch {
            CatalogDiagnostics.log(error)
            preconditionFailure(String(describing: error))
        }
    }()

    static func record(id: String) -> TideStationRecord? {
        database.station(id: id).map(TideStationRecord.init)
    }

    /// Every bundled station, alphabetical. This decodes every station's
    /// constituents, so the app looks stations up with `record(id:)` instead.
    static let all: [TideStationRecord] = database.map(TideStationRecord.init)
        .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }

    /// The engine's record for one database station. The name and region line
    /// are the display ones gen-tides resolved. A subordinate keeps its
    /// reference and offsets and no constituents: the reference predicts, and
    /// its own `datumOffset` is the one that applies.
    init(_ station: SlackwaterDatabase.Station) {
        let offsets: SlackwaterDatabase.TideOffsets? = station.tideOffsets
        self.init(
            id: station.id,
            name: station.name,
            region: station.region ?? "",
            aliases: station.aliases,
            latitude: station.latitude,
            longitude: station.longitude,
            timezone: station.timezone ?? "",
            chartDatum: station.chartDatum ?? "",
            datumOffset: offsets == nil ? station.chartDatumShift ?? 0 : 0,
            constituents: offsets == nil
                ? station.constituents.map { Con(name: $0.name, amplitude: $0.amplitude, phase: $0.phase) }
                : [],
            reference: offsets?.reference,
            // NOAA publishes these to 2 dp and the file stores them float32, so
            // round off the representation error (0.79 reads 0.7900000214576721),
            // as gen-tides does for stations.json.
            offsets: offsets.map {
                .init(time: .init(high: Double($0.timeHigh), low: Double($0.timeLow)),
                      height: .init(type: $0.heightType == .fixed ? "fixed" : "ratio",
                                    high: ($0.heightHigh * 1000).rounded() / 1000,
                                    low: ($0.heightLow * 1000).rounded() / 1000))
            })
    }
}
