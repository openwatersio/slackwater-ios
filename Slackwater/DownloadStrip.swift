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
                Text("Download \(count) more?")
                Spacer(minLength: 8)
                // Marks, not words: the question is already the sentence, and
                // two more words beside it made the row wrap to a second line.
                // Each carries its own label, because a glyph alone tells
                // VoiceOver nothing about what it accepts.
                Button(action: onDecline) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Not now")
                .accessibilityIdentifier("download-strip-decline")
                // Tinted, because `.borderedProminent` otherwise fills with the
                // system accent — the only blue on a screen built from navy and
                // leaf, which reads as an alert dropped into the app rather
                // than part of it.
                //
                // The mark needs its own colour: this row sets
                // `.foregroundStyle(SN.leaf)` below, and a prominent button's
                // label inherits it, so tinting the FILL leaf as well renders
                // leaf on leaf and the glyph disappears entirely.
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(SN.leaf)
                .foregroundStyle(SN.canvas)
                .accessibilityLabel("Download \(count) more")
                .accessibilityIdentifier("download-strip-accept")
            }
            .foregroundStyle(SN.leaf)
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
        }
    }
}
