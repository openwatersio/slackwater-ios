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

    /// A seen flag from iCloud, arriving after launch, stands down the launch tour wherever it
    /// is, armed, on screen or handed to a linked station, but never a replay the person asked for.
    func testASeenFlagFromAnotherDeviceStandsDownOnlyTheLaunchTour() {
        let c = TourCoach.shared
        c.arm()
        XCTAssertTrue(c.armed)
        TourSeen.shared.onSeen()
        XCTAssertFalse(c.armed, "a returning person setting up a new device does not get the tour")

        c.arm()
        c.begin(on: "noaa/9449880", starsAvailable: true, moonAvailable: true)
        c.advance()
        TourSeen.shared.onSeen()
        XCTAssertNil(c.step, "a launch tour already on screen stands down")
        XCTAssertNil(c.station)

        c.arm()
        c.begin(on: "noaa/9449880", starsAvailable: true, moonAvailable: true)
        c.handOff(to: "chs-nanaimo-harbour")
        TourSeen.shared.onSeen()
        XCTAssertFalse(c.armed, "a launch tour handed to a linked station stands down too")

        c.replay()
        TourSeen.shared.onSeen()
        XCTAssertTrue(c.armed, "a replay stays armed")
        c.begin(on: "noaa/9449880", starsAvailable: true, moonAvailable: true)
        TourSeen.shared.onSeen()
        XCTAssertEqual(c.step, .read, "a replay on screen keeps going")
    }
}

/// The seen flag follows the person through iCloud.
@MainActor final class TourSeenTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var cloud: MemoryTourCloud!

    override func setUp() async throws {
        suite = "TourSeenTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        cloud = MemoryTourCloud()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testAFlagInICloudCountsOnANewDevice() {
        XCTAssertFalse(TourSeen(defaults: defaults, cloud: MemoryTourCloud()).isSeen)
        cloud.values[seenTourKey] = true
        XCTAssertTrue(TourSeen(defaults: defaults, cloud: cloud).isSeen)
    }

    func testALocalFlagFromBeforeSyncIsUploaded() {
        defaults.set(true, forKey: seenTourKey)
        _ = TourSeen(defaults: defaults, cloud: cloud)
        XCTAssertEqual(cloud.values[seenTourKey] as? Bool, true)
    }

    func testAFlagAlreadyInICloudIsKeptLocally() {
        cloud.values[seenTourKey] = true
        _ = TourSeen(defaults: defaults, cloud: cloud)
        XCTAssertTrue(TourSeen(defaults: defaults, cloud: nil).isSeen, "signed out, the tour stays seen")
    }

    func testFinishingMarksBoth() {
        TourSeen(defaults: defaults, cloud: cloud).markSeen()
        XCTAssertTrue(defaults.bool(forKey: seenTourKey))
        XCTAssertEqual(cloud.values[seenTourKey] as? Bool, true)
    }

    func testAFlagArrivingLaterIsSavedAndAnnouncedOnce() {
        let seen = TourSeen(defaults: defaults, cloud: cloud)
        var announced = 0
        seen.onSeen = { announced += 1 }
        cloud.notify(); settle()
        XCTAssertEqual(announced, 0, "a change that carries no seen flag announces nothing")
        cloud.values[seenTourKey] = true
        cloud.notify(); cloud.notify(); settle()
        XCTAssertEqual(announced, 1)
        XCTAssertTrue(defaults.bool(forKey: seenTourKey))
    }

    /// The observer runs on the main queue, which may deliver after `post` returns.
    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
}

private final class MemoryTourCloud: NSUbiquitousKeyValueStore {
    var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func synchronize() -> Bool { true }

    func notify() {
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: self,
            userInfo: [NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreServerChange])
    }
}
