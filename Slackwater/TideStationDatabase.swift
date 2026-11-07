// Slackwater — GPL v3. Bundled tide stations read by id from the memory-mapped
// stations.tcdb that tools/gen-tides.mjs writes (#459).
import Foundation
import SlackwaterDatabase

/// Opens one of a catalog generation's station databases, `<resource>.tcdb`.
/// Mapping the file reads nothing but its 8-byte header; each lookup is a
/// binary search that pages in only the station it finds. `verifying` walks
/// the whole file first, so bytes that are cut short or corrupt throw rather
/// than trap on a later read; catalog validation opens a generation that way
/// once, before it can become the active one.
func stationDatabase(_ resource: String, directory: URL, verifying: Bool = false) throws -> StationDatabase {
    let url = directory.appendingPathComponent(resource + ".tcdb")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CatalogError(resource: resource, stage: .lookup, reason: "file missing")
    }
    do { return try verifying ? StationDatabase(verifyingContentsOf: url) : StationDatabase(contentsOf: url) }
    catch is InvalidStationDatabase {
        throw CatalogError(resource: resource, stage: .decode, reason: "not a station database")
    } catch {
        throw CatalogError(resource: resource, stage: .read, reason: "unable to read file")
    }
}

/// Opens a catalog generation's tide stations.
func tideDatabase(directory: URL) throws -> StationDatabase {
    try stationDatabase("stations", directory: directory)
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
            },
            // nil rather than false, so a record read from the database and the
            // same record decoded from stations.json are the same value. The
            // flag means one thing and absence means the other; two spellings
            // of "no" would make any comparison of the two sources a trap.
            seasonalDominant: station.seasonalDominant ? true : nil,
            // The library resolves a subordinate through its reference — which
            // matters here, because gen-tides writes a subordinate's `datums`
            // into the tcdb empty — rebases to the prediction source's chart
            // datum, and reduces by the same offsets the predictor applies to
            // the extremes. The result is the floor of a prediction rather than
            // a hydrographic datum, which is why it is not in `datums`
            // (tide-database docs/datums.md). gen-tides computes the identical
            // pair for stations.json; `testAstronomicalBoundsMatchTheGeneratedJSON`
            // holds the two implementations to each other.
            latDatum: station.astronomicalBounds?.lat,
            hatDatum: station.astronomicalBounds?.hat,
            source: station.source?.name)
    }
}
