import XCTest
import TideEngine
@testable import Slackwater

/// Issue #59: "Flooding"/"Ebbing" mean nothing to non-sailors. Roomy surfaces
/// (the detail heroes) gloss the word in place — "Flooding · incoming" — and
/// tight surfaces (list cards, schedule pills) lead with the direction
/// instead. The shared phase word itself never changes: sailors want it, and
/// it aligns with the CHS/NOAA tables.
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
    /// each detail hero renders the gloss; the tight surfaces render the
    /// cardinal beside the arrow rather than gloss text.
    func testGlossAndDirectionReachTheirSurfaces() throws {
        for hero in ["CurrentDetailView.swift", "OnlineGateDetailView.swift",
                     "DerivedGateDetailView.swift"] {
            XCTAssertTrue(try repoSource("Slackwater/\(hero)").contains(".gloss"),
                          "\(hero): detail hero lost its plain-word gloss (#59)")
        }
        // Both list cards (OnlineGateCardView, CurrentCardView) lead with
        // arrow + cardinal.
        let cards = try repoSource("Slackwater/SlackwaterApp.swift")
        XCTAssertGreaterThanOrEqual(cards.components(separatedBy: "compass16(").count - 1, 2,
                                    "list cards lost their direction-first cardinal (#59)")
        XCTAssertTrue(try repoSource("Slackwater/TimelineStrip.swift").contains("compass16("),
                      "schedule pills lost their direction-first cardinal (#59)")
    }
}
