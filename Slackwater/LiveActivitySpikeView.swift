// Slackwater — GPL v3. SPIKE, throwaway: answers docs/alerts.md §11 on a phone. Never merge.
import ActivityKit
import SwiftUI

/// Launch with `-laSpike`. Schedules activities that start in `leadMin` minutes, then:
/// 1. force-quit the app and wait — does the alert fire and the activity appear?
/// 2. keep it closed through `event` — does the face flip (isStale)?
/// 3. tap Schedule repeatedly — how many before the error?
struct LiveActivitySpikeView: View {
    @State private var leadMin = 2.0
    @State private var log: [String] = []
    @State private var count = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper("Starts in \(Int(leadMin)) min", value: $leadMin, in: 1...30)
                    Text("Enabled: \(ActivityAuthorizationInfo().areActivitiesEnabled ? "yes" : "NO")")
                    Button("Schedule one") { schedule() }
                    Button("Schedule until refused") { while scheduleOK() {} }
                    Button("End all", role: .destructive) { Task { await endAll() } }
                    Button("List") { Task { await list() } }
                }
                // A home-screen launch has no -laSpike argument, so the flag sticks until cleared.
                Section { Button("Leave spike (next launch is the app)") { UserDefaults.standard.set(false, forKey: "laSpike") } }
                Section("Log") { ForEach(log.indices.reversed(), id: \.self) { Text(log[$0]).font(.caption.monospaced()) } }
            }
            .navigationTitle("Live Activity spike")
            .onAppear { UserDefaults.standard.set(true, forKey: "laSpike") }
        }
    }

    private func schedule() { _ = scheduleOK() }

    private func scheduleOK() -> Bool {
        count += 1
        let start = Date().addingTimeInterval(leadMin * 60)
        let event = start.addingTimeInterval(60)
        let attrs = LiveActivitySpikeAttributes(label: "Spike \(count)", event: event, end: event.addingTimeInterval(3 * 60))
        let content = ActivityContent(state: LiveActivitySpikeAttributes.ContentState(), staleDate: event)
        let alert = AlertConfiguration(title: "Spike \(count) · Slack window", body: "in 1 min", sound: .default)
        do {
            let a = try Activity.request(attributes: attrs, content: content, pushType: nil,
                                         style: .standard, alertConfiguration: alert, start: start)
            log.append("\(stamp()) #\(count) scheduled \(a.id.prefix(6)) start \(time(start)) state \(a.activityState)")
            return true
        } catch {
            log.append("\(stamp()) #\(count) REFUSED: \(error)")
            return false
        }
    }

    private func endAll() async {
        for a in Activity<LiveActivitySpikeAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        log.append("\(stamp()) ended all")
    }

    private func list() async {
        let all = Activity<LiveActivitySpikeAttributes>.activities
        log.append("\(stamp()) \(all.count) ongoing: " + all.map { "\($0.attributes.label)=\($0.activityState)" }.joined(separator: ", "))
    }

    private func stamp() -> String { time(.now) }
    private func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .standard) }
}
