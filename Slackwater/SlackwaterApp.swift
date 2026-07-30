// Slackwater — GPL v3. M1: station list with search + 1a gradient cards.
import SwiftUI
import TideEngine

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
    @State private var query = ""
    @AppStorage(unitsKey) private var units = "imperial"

    private var imperial: Bool { units == "imperial" }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                RadialGradient(colors: [SN.canvasGlow, SN.canvas], center: .top,
                               startRadius: 0, endRadius: 500)
                    .ignoresSafeArea()
                ScrollView {
                    header
                    searchField
                    MonoLabel(text: query.isEmpty ? "Salish Sea" : "Results")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 26)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                    LazyVStack(spacing: 12) {
                        ForEach(TideStationRecord.search(query)) { station in
                            NavigationLink(value: station) {
                                StationCardView(record: station, imperial: imperial)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 44)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TideStationRecord.self) { TideDetailView(record: $0) }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            Text("Slackwater")
                .font(.fraunces(36, .semibold))
                .foregroundStyle(SN.paper)
            Spacer()
            // The prototype's units pill doubles as the setting: tap to toggle.
            Button {
                units = imperial ? "metric" : "imperial"
            } label: {
                Text(imperial ? "FT" : "M")
                    .font(.geistMono(12, .medium))
                    .tracking(1)
                    .foregroundStyle(SN.leaf)
                    .frame(height: 34)
                    .padding(.horizontal, 14)
                    .background(SN.leaf.opacity(0.16), in: Capsule())
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SN.foam.opacity(0.7))
            TextField("Harbor, bay, or channel", text: $query)
                .font(.geist(17))
                .foregroundStyle(SN.paper)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SN.foam.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(SN.leaf.opacity(0.25), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}

/// Variant 1a card: per-station sky gradient, Fraunces name, big height numeral.
struct StationCardView: View {
    let record: TideStationRecord
    let imperial: Bool
    @State private var state: CardState?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .font(.fraunces(23, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(record.region)
                        .font(.geist(13))
                        .foregroundStyle(SN.foam.opacity(0.78))
                    if let next = state?.next {
                        Text("\(next.kind == .high ? "High" : "Low") \(formatHeight(next.height, imperial: imperial)) \(heightUnit(imperial: imperial)) · \(cardTime(next.time, record.tz))")
                            .font(.geist(12))
                            .foregroundStyle(SN.foam.opacity(0.92))
                            .padding(.top, 10)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    if let state {
                        (Text(formatHeight(state.height, imperial: imperial))
                            .font(.fraunces(42))
                         + Text(" \(heightUnit(imperial: imperial))")
                            .font(.fraunces(17)))
                            .foregroundStyle(.white)
                        HStack(spacing: 4) {
                            Text(state.rising ? "▲" : "▼").font(.geist(9))
                            Text(state.rising ? "Rising" : "Falling").font(.geist(11))
                        }
                        .foregroundStyle(SN.foam.opacity(0.9))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(stationGradient(id: record.id))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: 0x001432, opacity: 0.24), radius: 12, y: 10)
        .task { if state == nil { state = record.cardState(at: .now) } }
    }
}
