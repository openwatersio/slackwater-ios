import XCTest
import TideEngine
@testable import Slackwater

/// Issue #59: "Flooding"/"Ebbing" mean nothing to non-sailors, so no surface
/// leans on the word alone. The details lead with the phase word and carry the
/// direction beside it; the tight surfaces (list cards, schedule pills) lead
/// with the direction outright. The shared phase word itself never changes:
/// sailors want it, and it aligns with the CHS/NOAA tables.
final class PhaseGlossTests: XCTestCase {

    func testGlossWords() {
        XCTAssertEqual(CurrentPhase.flood.gloss, "incoming")
        XCTAssertEqual(CurrentPhase.ebb.gloss, "outgoing")
        // Slack is already plain language and needs no gloss word.
        XCTAssertNil(CurrentPhase.slack.gloss)
        // The derived-gate phase glosses identically.
        XCTAssertEqual(DerivedPhase.flood.gloss, "incoming")
        XCTAssertEqual(DerivedPhase.ebb.gloss, "outgoing")
        XCTAssertNil(DerivedPhase.slack.gloss)
        // And the pill words stay the sailors' words.
        XCTAssertEqual(CurrentPhase.flood.word, "Flooding")
        XCTAssertEqual(CurrentPhase.ebb.word, "Ebbing")
    }

    /// Source tripwires (the register ColourAndFormTests' chart guard set):
    /// every lead states the phase in words, and every surface that has room
    /// for a bearing prints the cardinal beside its arrow rather than leaving
    /// direction to a colour.
    func testPhaseWordAndDirectionReachTheirSurfaces() throws {
        // The measured leads — `CurrentLead` draws for both, so the two views
        // cannot drift apart — and the derived gate's own lead, which has a
        // phase but no bearing to point at.
        XCTAssertTrue(try repoSource("Slackwater/CurrentLead.swift").contains("phase.word"),
                      "the measured current lead lost its phase word (#59)")
        XCTAssertTrue(try repoSource("Slackwater/DerivedGateDetailView.swift").contains("phase.word"),
                      "the derived gate's lead lost its phase word (#59)")

        // The list cards lead with arrow + cardinal, rendered once for every
        // card kind by ConditionsItem's `.current` case — a single call site
        // by design, so this asserts presence, not a count. ConditionsItem
        // moved into StationCardFace.swift so the widget extension can share
        // it with the list.
        let cards = try repoSource("Slackwater/StationCardFace.swift")
        XCTAssertTrue(cards.contains("compass16("),
                      "list cards lost their direction-first cardinal (#59)")
        XCTAssertTrue(cards.contains("struct ConditionsItem"),
                      "the single shared reading renderer is gone — if the cards' "
                      + "direction rows have split up again, restore the ≥2 count here")
        XCTAssertTrue(try repoSource("Slackwater/TimelineStrip.swift").contains("compass16("),
                      "schedule pills lost their direction-first cardinal (#59)")
    }
}
