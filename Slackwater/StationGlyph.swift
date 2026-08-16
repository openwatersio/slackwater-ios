import SwiftUI

/// Was a station's kind, drawn — a wave for a current station, a dome over a
/// datum line for a tide one. The drawing is gone: the two marks were not
/// universal symbols, so they taught a new reader nothing and a returning one
/// scanned the names regardless. Every surface that carried one either needed
/// no kind at all (the list cards, the recent rows) or already said it in
/// words — `kindLabel` in the chooser sheet, "Current · <region>" in the
/// downloads manager. Nothing replaces the mark, VoiceOver included: its
/// `accessibilityLabel` was the only thing announcing kind on a card, and
/// keeping the phrase would have told a VoiceOver user something the card no
/// longer tells anyone else.
///
/// What survives is the half that was never about kind. COLOUR IS STATE — the
/// separation that was the whole point of the glyph outlives it, and the two
/// current detail views still tint by it.
///
/// ponytail: a type named `StationGlyph` that draws no glyph is a misnomer;
/// folding `colour(for:)` into `SN` would be the tidy end of this. Left alone
/// because the rename is churn across two views and six test call sites for no
/// behaviour change.
enum StationGlyph {
    enum Tone { case rising, falling, flood, ebb, slack, unknown }

    static func colour(for tone: Tone) -> Color {
        switch tone {
        case .rising, .flood: SN.flood
        case .falling, .ebb: SN.ebb
        case .slack: SN.go
        case .unknown: SN.steel
        }
    }
}
