// Slackwater — GPL v3. Bundled tide stations read by id from the memory-mapped
// stations.tcdb that tools/gen-tides.mjs writes (#459).
import Foundation
import SlackwaterDatabase

extension TideStationRecord {
    /// The engine's record for one database station. The name and region line
    /// are the display ones gen-tides resolved. A subordinate keeps its
    /// reference and offsets and no constituents, as in stations.json: the
    /// reference predicts, and its own `datumOffset` is the one that applies.
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
            offsets: offsets.map {
                .init(time: .init(high: Double($0.timeHigh), low: Double($0.timeLow)),
                      height: .init(type: $0.heightType == .fixed ? "fixed" : "ratio",
                                    high: $0.heightHigh, low: $0.heightLow))
            })
    }
}
