// Slackwater — GPL v3. M0 app shell: station list → tide curve.
import SwiftUI

let navy = Color(red: 0x05 / 255.0, green: 0x12 / 255.0, blue: 0x2A / 255.0)

@main
struct SlackwaterApp: App {
    var body: some Scene {
        WindowGroup {
            StationListView()
                .preferredColorScheme(.dark)
        }
    }
}

struct StationListView: View {
    // Launch on Friday Harbor (first station); Back reaches the list.
    @State private var path = Array(TideStationRecord.all.prefix(1))

    var body: some View {
        NavigationStack(path: $path) {
            list
        }
    }

    private var list: some View {
        List(TideStationRecord.all) { station in
            NavigationLink(value: station) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                    Text(station.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(navy.opacity(0.6))
        }
        .scrollContentBackground(.hidden)
        .background(navy)
        .navigationTitle("Slackwater")
        .navigationDestination(for: TideStationRecord.self) { TideDetailView(record: $0) }
    }
}
