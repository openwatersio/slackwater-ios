// Slackwater — GPL v3. Bundled NOAA Salish tide stations (public domain data,
// same file slackwater-web ships: src/data/stations.json).
import Foundation
import TideEngine

struct TideStationRecord: Decodable, Identifiable, Hashable {
    struct Con: Decodable, Hashable { let name: String; let amplitude: Double; let phase: Double }
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let timezone: String
    let chartDatum: String
    let datumOffset: Double
    let constituents: [Con]

    var engineStation: Station {
        Station(constituents: constituents.map { HarmonicConstituent(name: $0.name, amplitude: $0.amplitude, phase: $0.phase) },
                offset: datumOffset)
    }

    static let fridayHarborID = "noaa/9449880"

    /// All bundled stations, Friday Harbor first, rest alphabetical.
    static let all: [TideStationRecord] = {
        guard let url = Bundle.main.url(forResource: "stations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let stations = try? JSONDecoder().decode([TideStationRecord].self, from: data) else { return [] }
        let sorted = stations.sorted { $0.name < $1.name }
        return sorted.filter { $0.id == fridayHarborID } + sorted.filter { $0.id != fridayHarborID }
    }()
}
