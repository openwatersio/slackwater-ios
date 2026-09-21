// Slackwater — GPL v3. The download strip: what the list says about work in
// flight, and the one question that lets it continue in the background.
//
// It sits at the TOP of the list while active because it is the only surface
// that can carry the tap, and iOS requires a tap before a continued-processing
// task may be submitted. The Settings row is where downloads live the rest of
// the time.
import SwiftUI

struct DownloadStrip: View {
    let state: DownloadStripState
    let onOpen: () -> Void
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        switch state {
        case .absent:
            EmptyView()
        case let .working(done, total):
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Downloading nearby stations")
                        Spacer()
                        Text("\(done) of \(total)").monospacedDigit()
                    }
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(SN.leaf)
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
        case let .asking(count):
            HStack(spacing: 12) {
                // A count, never a duration: locking the phone stops the work,
                // so a time here would be a promise the app cannot keep.
                Text("Download \(count) more nearby?")
                Spacer(minLength: 8)
                Button("Not now", action: onDecline).buttonStyle(.plain)
                // Tinted, because `.borderedProminent` otherwise fills with the
                // system accent — the only blue on a screen built from navy and
                // leaf, which reads as an alert dropped into the app rather
                // than part of it.
                Button("Yes", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .tint(SN.leaf)
            }
            .foregroundStyle(SN.leaf)
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
        }
    }
}
