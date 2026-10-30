// Slackwater — GPL v3. The first-run tour's step machine: ordering, the
// arctic skip, and the one-way seen flag.
import XCTest
@testable import Slackwater

@MainActor
final class TourCoachTests: XCTestCase {
    /// The sky switch lives in the App Group the test host shares with the app
    /// on this simulator: a debug run that turned it off would drop the moon
    /// step from every walk below, so each test starts from unset and the
    /// developer's own choice comes back afterwards.
    private var savedSkyBodies: Any?

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: seenTourKey)
        savedSkyBodies = AppGroup.defaults.object(forKey: AppGroup.skyBodiesKey)
        AppGroup.defaults.removeObject(forKey: AppGroup.skyBodiesKey)
        TourCoach.shared.step = nil
        TourCoach.shared.station = nil
    }

    override func tearDown() async throws {
        if let savedSkyBodies { AppGroup.defaults.set(savedSkyBodies, forKey: AppGroup.skyBodiesKey) }
        else { AppGroup.defaults.removeObject(forKey: AppGroup.skyBodiesKey) }
    }

    func testWalksAllFiveStepsThenFinishes() {
        let c = TourCoach.shared
        c.arm()
        c.begin(on: "noaa/9449880", starsAvailable: true, moonAvailable: true)
        XCTAssertEqual(c.step, .read)
        c.advance(); XCTAssertEqual(c.step, .stars)
        c.advance(); XCTAssertEqual(c.step, .moon)
        c.advance(); XCTAssertEqual(c.step, .moonCard)
        c.advance(); XCTAssertEqual(c.step, .star)
        c.advance()
        XCTAssertNil(c.step, "the last advance ends the tour")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: seenTourKey))
    }

    // Above the Arctic Circle in summer there is no sunset in the window, so
    // there is nothing true to say about stars or the moon in the sky.
    func testSkipsSkyStepsWhenThereIsNoNight() {
        let c = TourCoach.shared
        c.arm()
        c.begin(on: "noaa/9449880", starsAvailable: false, moonAvailable: false)
        XCTAssertEqual(c.step, .read)
        c.advance()
        XCTAssertEqual(c.step, .moonCard, "stars and moon are skipped, not shown empty")
        c.advance(); XCTAssertEqual(c.step, .star)
    }

    // A moon only ever up in daylight (`tourMoonTime` nil) must not sink the
    // stars step too — the two are independent, unlike the old single flag.
    func testSkipsOnlyMoonWhenStarsAreAvailableButMoonIsNot() {
        let c = TourCoach.shared
        c.arm()
        c.begin(on: "noaa/9449880", starsAvailable: true, moonAvailable: false)
        XCTAssertEqual(c.step, .read)
        c.advance(); XCTAssertEqual(c.step, .stars)
        c.advance()
        XCTAssertEqual(c.step, .moonCard, "moon is skipped but stars is shown")
        c.advance(); XCTAssertEqual(c.step, .star)
    }

    // Settings' sun, moon and stars switch empties the sky: the moon step has
    // nothing to point at and drops, even when the switch flips mid-tour. The
    // stars step stays, because it is where the tour teaches the swipe.
    func testKeepsTheSwipeLessonButDropsTheMoonWhileTheSkyBodiesAreOff() {
        let c = TourCoach.shared
        c.arm()
        c.begin(on: "noaa/9449880", starsAvailable: true, moonAvailable: true)
        XCTAssertEqual(c.step, .read)
        AppGroup.defaults.set(false, forKey: AppGroup.skyBodiesKey)
        c.advance(); XCTAssertEqual(c.step, .stars, "the swipe lesson does not depend on the sky")
        c.advance()
        XCTAssertEqual(c.step, .moonCard, "an emptied sky has no moon to point at")
        c.advance(); XCTAssertEqual(c.step, .star)
    }

    func testFinishIsOneWayAndArmRespectsIt() {
        let c = TourCoach.shared
        c.arm()
        c.begin(on: "noaa/9449880", starsAvailable: true, moonAvailable: true)
        c.finish()
        XCTAssertNil(c.step)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: seenTourKey))

        c.arm()
        XCTAssertFalse(c.armed, "a seen tour does not re-arm on the next launch")
    }

    // Replay from Settings ignores the seen flag — that is the whole point of
    // it — but only arms; it does not begin (there is no timeline to derive
    // starsAvailable/moonAvailable from at the Settings sheet). The caller
    // (StationListView) opens the station, whose own `begin()` starts it.
    func testReplayArmsButDoesNotBeginAndClearsAnyInProgressTour() {
        let c = TourCoach.shared
        c.arm(); c.begin(on: "noaa/9449880", starsAvailable: true, moonAvailable: true); c.finish()
        c.arm(); c.begin(on: "noaa/9449880", starsAvailable: true, moonAvailable: true)
        c.replay()
        XCTAssertTrue(c.armed)
        XCTAssertNil(c.step, "replay leaves the tour armed, not started")
        XCTAssertNil(c.station, "a half-finished tour does not linger")
    }

    func testFinishGuardPreventsStrayCall() {
        let c = TourCoach.shared
        c.arm()
        c.finish()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: seenTourKey), "finish when no tour is running does not write the seen flag")
        c.arm()
        XCTAssertTrue(c.armed, "after a guarded finish, arm still works")
    }
}
