// Slackwater — GPL v3. The station list: its groups, the location slot, the
// swipe actions, and how a station presents itself in a row.
//
// One of the weight-balanced screenshot classes — see ScreenshotTestCase.swift
// for the helpers and for why the suite is split this way.
import UIKit
import XCTest

final class ListAndFavoritesTests: ScreenshotTestCase {
    // The list's groups — My Location hero (nm pill, 3-dp coords, no
    // match-grade sentence), Recents after a visit, Near Me, and nothing else
    // (no catalog section, no units pill).
    func testM41GroupedListAndRecents() throws {
        // Deterministic Victoria fix via the -fixLat/-fixLon hook. Favorites
        // reset too: this test asserts group ORDER from a clean list, so its
        // launch args enforce that — not the goodwill of every earlier test
        // on the simulator (a leaked favorite pushed RECENTS past the iPad
        // sidebar's bounded scroll, 2026-08-08).
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
        XCTAssert(app.staticTexts["MY LOCATION"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["NEAR ME"].exists)
        // No full-catalog section, no units pill.
        XCTAssertFalse(app.staticTexts["SALISH SEA"].exists)
        XCTAssertFalse(app.buttons["FT"].exists)
        XCTAssertFalse(app.buttons["M"].exists)
        // Tile copy: coordinates only — no "to station"/match-grade sentence.
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '°N'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'to station'")).firstMatch.exists)
        // No recents yet on a clean run.
        XCTAssertFalse(app.staticTexts["RECENTS"].exists)

        // Visit a station; it must appear under Recents — the very BOTTOM
        // group (order: My Location → Favorites → Near Me → Recents).
        openFridayHarbor(app)
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        let near = app.staticTexts["NEAR ME"].firstMatch
        XCTAssert(near.waitForExistence(timeout: 5))
        let recentsLabel = app.staticTexts["RECENTS"].firstMatch
        scrollTo(recentsLabel, in: app)
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists)
        // Both labels realized (tall screens / short lists): direct order
        // check. The sidebar reflows as CHS pending cards above update, so
        // read both frames together and wait them out (settled — see
        // testM50RecentsNamesFit) rather than reading each live.
        if near.exists {
            let f = settled { [near.frame, recentsLabel.frame] }
            XCTAssert(f[0].minY < f[1].minY,
                      "Recents must render below Near Me")
        }
    }

    // Location denied — the amber card sits in the My Location slot, above
    // Near Me ranked from the fallback.
    func testM41DeniedSlot() throws {
        let app = launch("-seedGate", "-resetRecents", "-locDenied")
        XCTAssert(app.staticTexts["Location unavailable"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Go to Settings"].exists)
        XCTAssertFalse(app.staticTexts["MY LOCATION"].exists)
        XCTAssert(app.staticTexts["NEAR ME"].exists)
    }

    func testM41AuthorizedLocationKeepsItsSlotWhileWaitingForAFix() throws {
        let app = launch("-seedGate", "-resetRecents", "-locAuthorizedNoFix")
        XCTAssert(app.staticTexts["MY LOCATION"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Finding your location…"].exists)
        XCTAssert(app.staticTexts["NEAR ME"].exists)
        save(app, "m41-location-pending.png")
    }

    /// A station that hasn't downloaded yet can still be favorited from its
    /// detail. Fresh-install bug (2026-08-08): the waiting page's star wrote
    /// "current:chs-…" while the catalog keys CHS gates bare, so the favorite
    /// was a phantom id — the star lit, and no Favorites group ever appeared.
    /// The sharp assertion is the FAVORITES section label itself: it only
    /// renders when a favorite id RESOLVES, so the phantom leaves it absent.
    func testFavoritePendingChsGateFromDetail() throws {
        // Fit only Victoria, so Dodd Narrows deterministically stays the
        // pending ⚠️ waiting page.
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-chsResetModels", "-chsFitOnly", "chs-victoria",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "dodd")
        pickSearchResult(app, app.staticTexts["Dodd Narrows"].firstMatch)

        // The pending detail still carries the header star — tap it.
        let star = app.buttons["detail-favorite"].firstMatch
        XCTAssert(star.waitForExistence(timeout: 5), "favorite star missing from the waiting detail")
        star.tap()
        XCTAssert(app.buttons["Remove favorite"].waitForExistence(timeout: 5),
                  "star did not flip to favorited on the waiting detail")

        // Back to the list: the favorite must RESOLVE — a Favorites group
        // with the gate in it, not a phantom id and no group at all.
        app.buttons["detail-back"].firstMatch.tap()
        // iPhone closes search with the push; the iPad sidebar keeps it open.
        if app.buttons["Close search"].firstMatch.exists { closeSearch(app) }
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["FAVORITES"].waitForExistence(timeout: 5),
                  "favoriting a pending CHS gate produced no Favorites group — the star wrote an id the list cannot resolve")
        let row = app.staticTexts["Dodd Narrows"].firstMatch
        XCTAssert(row.exists, "the favorited pending gate is missing from the Favorites group")

        // Leave the simulator as found: swipe-unfavorite the row so later
        // tests that assume a clean favorites store aren't ambushed.
        row.swipeLeft()
        XCTAssert(app.buttons["Unfavorite"].waitForExistence(timeout: 5))
        app.buttons["Unfavorite"].firstMatch.tap()
        _ = app.staticTexts["FAVORITES"].waitForNonExistence(timeout: 10)
        XCTAssertFalse(app.staticTexts["FAVORITES"].exists,
                       "cleanup unfavorite left the Favorites group behind")
    }

    // Favorites — the detail-header star files a station under a Favorites
    // group (My Location → Favorites → Recents → Near Me), favorites/hero never
    // repeat in Recents, swipe actions manage the groups, and the speed-unit
    // setting rewrites a current detail's readout.
    func testM43FavoritesSwipesAndSpeedUnits() throws {
        // Deterministic Victoria fix; clean favorites/recents.
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        // Star Friday Harbor from its detail (upper-right, back's mirror).
        openFridayHarbor(app)
        let star = app.buttons["detail-favorite"].firstMatch
        XCTAssert(star.waitForExistence(timeout: 5), "favorite star missing from detail header")
        star.tap()
        XCTAssert(app.buttons["Remove favorite"].waitForExistence(timeout: 5),
                  "star did not flip to favorited in the header")

        // Back: a Favorites group holds it, and it does NOT repeat in Recents
        // (it was just visited — favorites win the dedupe).
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["FAVORITES"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["RECENTS"].exists,
                       "a favorited station must not also render under Recents")

        // Visit a second station so Recents renders too — all four groups.
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass State Park"].firstMatch)
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["MY LOCATION"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["FAVORITES"].exists)
        XCTAssert(app.staticTexts["NEAR ME"].exists)
        // Recents is the last group — scroll down to it.
        let recentsLabel = app.staticTexts["RECENTS"].firstMatch
        scrollTo(recentsLabel, in: app)

        // Swipe open the Recents row: red destructive Remove.
        let parkRow = app.staticTexts["Deception Pass State Park"].firstMatch
        scrollTo(parkRow, in: app)
        parkRow.swipeLeft()
        XCTAssert(app.buttons["Remove"].waitForExistence(timeout: 5),
                  "trailing swipe did not reveal the Recents remove action")
        app.buttons["Remove"].firstMatch.tap()
        _ = app.staticTexts["Deception Pass State Park"].waitForNonExistence(timeout: 10)
        XCTAssertFalse(app.staticTexts["Deception Pass State Park"].exists,
                       "remove-from-recents left the row behind")

        // Swipe-unfavorite Friday Harbor (back near the top): it leaves
        // Favorites and re-files under Recents — a move, not a deletion —
        // which means the bottom of the list.
        listContainer(app).swipeDown()
        listContainer(app).swipeDown()
        let fridayRow = app.staticTexts["Friday Harbor"].firstMatch
        XCTAssert(fridayRow.waitForExistence(timeout: 5))
        fridayRow.swipeLeft()
        XCTAssert(app.buttons["Unfavorite"].waitForExistence(timeout: 5),
                  "trailing swipe did not reveal the favorites remove action")
        app.buttons["Unfavorite"].firstMatch.tap()
        _ = app.staticTexts["FAVORITES"].waitForNonExistence(timeout: 10)
        XCTAssertFalse(app.staticTexts["FAVORITES"].exists,
                       "unfavorite left the Favorites group behind")
        let recentsAgain = app.staticTexts["RECENTS"].firstMatch
        scrollTo(recentsAgain, in: app)
        // Scroll to the ROW, not just the group label: how many rows Recents
        // has depends on what this simulator has downloaded, so the label can
        // land on the last visible line with the row below the fold.
        let refiled = app.staticTexts["Friday Harbor"].firstMatch
        scrollTo(refiled, in: app)
        XCTAssert(refiled.exists, "unfavorited station did not re-file to Recents")
        listContainer(app).swipeDown()
        listContainer(app).swipeDown()

        // Speed units: switch to km/h in Settings, the current detail follows.
        app.buttons["Settings"].tap()
        let kmh = app.buttons["km/h"]
        XCTAssert(kmh.waitForExistence(timeout: 5), "speed-unit switch missing from Settings")
        kmh.tap()
        app.buttons["Done"].tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'km/h'")).firstMatch.waitForExistence(timeout: 5),
                  "current detail readout did not follow the km/h setting")
        // Leave the store on knots for the other tests.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        let kn = app.buttons["Knots"]
        XCTAssert(kn.waitForExistence(timeout: 5))
        kn.tap()
        app.buttons["Done"].tap()
    }

    // MARK: - Station identity presentation

    /// The subtitle bug Bryan found on the iPad: "7.6 mi. Sse" — a compass
    /// point title-cased by station-corrections' cleanName, and statute miles
    /// on a card whose distance pill speaks nm.
    func testM50RegionSubtitleIsNauticalAndShouts() throws {
        // Upright: the split-layout test leaves the device in landscape, and
        // these screenshots are the ones a human reads.
        XCUIDevice.shared.orientation = .portrait
        let app = launch("-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "discovery island")
        XCTAssert(app.staticTexts["6.6 nm SSE"].firstMatch.waitForExistence(timeout: 5),
                  "the fixed subtitle is missing — expected nautical miles and SSE")
        XCTAssertFalse(app.staticTexts["7.6 mi. Sse"].exists,
                       "the broken subtitle is still rendering")
        XCTAssert(app.staticTexts["3.0 nm NE"].firstMatch.exists,
                  "the sibling station's already-correct subtitle changed")
        closeSearch(app)
    }

    /// Same-named stations render as ONE entry in Near Me, with the namesakes
    /// behind the chooser — two "Discovery Island" cards side by side look
    /// identical. Pick the non-nearest one from that chooser and Recents
    /// remembers exactly which one you opened: no namesake collapse on an
    /// explicit pick.
    func testM50MatchingStationChooser() throws {
        // Upright: the split-layout test leaves the device in landscape, and
        // these screenshots are the ones a human reads.
        XCUIDevice.shared.orientation = .portrait
        // The fix is put ON Discovery Island, not on Victoria: at national
        // scale the six stations nearest a Victoria fix are all harbour gauges
        // inside 5 km, which is what Near Me is FOR and not what this test is
        // about. Standing at the station is the deterministic way to put a
        // collided name in the list.
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.452", "-fixLon", "-123.155")  // Discovery Island
        XCTAssert(app.staticTexts["NEAR ME"].waitForExistence(timeout: 10))

        // One entry, not two: the nearer Discovery Island renders, the farther
        // one is behind the chooser.
        // Scoped to the LIST: at regular width the detail pane auto-opens on the
        // first row, so an unscoped count also picks up its header title.
        let cards = listContainer(app).staticTexts
            .matching(NSPredicate(format: "label == %@", "Discovery Island"))
        XCTAssertEqual(cards.count, 1, "same-named stations must render as one entry")
        XCTAssert(app.staticTexts["3.0 nm NE"].firstMatch.exists, "the nearest one is the entry")
        XCTAssertFalse(app.staticTexts["6.6 nm SSE"].exists,
                       "the farther namesake must not render as its own card")

        let chooserButton = app.buttons["matching-stations"].firstMatch
        XCTAssert(chooserButton.waitForExistence(timeout: 5),
                  "no matching-station affordance on a collided name")
        XCTAssert(app.staticTexts["2 matching stations"].firstMatch.exists)
        chooserButton.tap()

        // The chooser: both stations, each with what it measures and how far.
        XCTAssert(app.otherElements["station-chooser"].waitForExistence(timeout: 5)
                  || app.staticTexts["3.0 nm NE"].firstMatch.waitForExistence(timeout: 5),
                  "the chooser sheet did not open")
        XCTAssert(app.staticTexts["6.6 nm SSE"].firstMatch.waitForExistence(timeout: 5),
                  "the chooser must offer the station the list collapsed")
        XCTAssert(app.staticTexts["CURRENT · NOAA"].firstMatch.exists,  // MonoLabel uppercases
                  "a chooser row must say what it measures and whose data it is")

        // Picking the collapsed one opens it — it is not lost, just quiet.
        app.staticTexts["6.6 nm SSE"].firstMatch.tap()
        XCTAssert(app.staticTexts["Discovery Island"].firstMatch.waitForExistence(timeout: 8))
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 8),
                  "the chooser pick did not open a station detail")

        // Recents keeps the station actually opened: the chooser pick is an
        // explicit choice, not the distance ranking. Collapse it into the
        // nearest namesake's id and Recents silently shows and reopens "3.0 nm
        // NE" instead of the "6.6 nm SSE" station tapped. Same disambiguating
        // field the chooser assertions above key on (each station's region is
        // literally its bearing string), so a bare text match is unambiguous.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        let recentsLabel = app.staticTexts["RECENTS"].firstMatch
        scrollTo(recentsLabel, in: app)
        let recentPick = app.staticTexts["6.6 nm SSE"].firstMatch
        scrollTo(recentPick, in: app)
        XCTAssert(recentPick.exists,
                  "Recents must keep the chooser-picked station, not collapse it into the nearest namesake")
    }

    /// "Deception Pas…" — the compact Recents row starved the name column so
    /// two different stations truncated to the same string.
    func testM50RecentsNamesFit() throws {
        // Upright: the split-layout test leaves the device in landscape, and
        // these screenshots are the ones a human reads.
        XCUIDevice.shared.orientation = .portrait
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        for name in ["Deception Pass (Narrows)", "Deception Pass State Park"] {
            openSearch(app, "deception")
            pickSearchResult(app, app.staticTexts[name].firstMatch)
            XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 8))
            app.buttons["detail-back"].firstMatch.tap()
            XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        }

        let recents = app.staticTexts["RECENTS"].firstMatch
        scrollTo(recents, in: app)
        let long = app.staticTexts["Deception Pass State Park"].firstMatch
        scrollTo(long, in: app)
        XCTAssert(long.exists, "the visited station is not in Recents")
        // The sidebar reflows asynchronously while the CHS pending card above
        // Recents updates its status line, and the row's name/reading gap is
        // only ~2pt — so the name and EVERY reading come out of one `settled`
        // read. Settling the name alone and reading the readings after it let
        // a 3pt shift land in between and failed CI (PR #25).
        let readingLabels = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^-?\\d+\\.\\d+ (ft|m|kn)$"))
        let frames = settled {
            [long.frame] + readingLabels.allElementsBoundByIndex.compactMap {
                $0.exists ? $0.frame : nil
            }
        }
        let nameFrame = frames[0]
        // The name owns the row's width now. Truncated, its frame collapsed to
        // the ~150pt column left over beside the reading (iPad sidebar).
        XCTAssert(nameFrame.width > 165,
                  "the Recents name column is still starved: \(nameFrame.width)pt")
        // And the reading sits below the name, not beside it. Only this row's —
        // the Near Me cards above carry readings too.
        let readings = frames.dropFirst().filter {
            $0.minY >= nameFrame.minY && $0.maxY <= nameFrame.maxY + 34
        }
        XCTAssertFalse(readings.isEmpty, "the Recents row lost its reading")
        for frame in readings {
            XCTAssert(frame.minY >= nameFrame.maxY - 1,
                      "the reading still shares the name's line: \(frame) vs name \(nameFrame)")
        }
    }

    /// iPad: opening a second station of the SAME kind must not keep the first
    /// one's chart and map — same destination type at the same depth is the
    /// same SwiftUI identity, so @State can survive the swap. The stale-@State
    /// tell is the schedule contents themselves — timeline-derived, so a stale
    /// detail keeps the previous station's rows verbatim — plus the
    /// tide-at-port link (record-derived: Discovery Island has none, Deception
    /// Pass (Narrows) does) as the layout check.
    func testM50DetailSwapsBetweenSameKindStations() throws {
        // Split layout only: on iPhone the detail covers the search FAB, so a
        // second station is always reached through a pop first.
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-only split-layout swap")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch("-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "discovery island")
        pickSearchResult(app, app.staticTexts["3.0 nm NE"].firstMatch)
        XCTAssert(app.otherElements["detail-map-header"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "tide-at-port").firstMatch.exists,
                       "an unpaired current station has no reference port to link")
        let before = scheduleRowLabels(app)
        XCTAssert(!before.isEmpty, "no schedule rows read from the first station")

        // Second station, same kind — in the split layout this replaces the
        // detail pane without a pop.
        openSearch(app, "deception pass (n")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Deception Pass (Narrows)"].firstMatch
            .waitForExistence(timeout: 8))
        XCTAssert(app.descendants(matching: .any).matching(identifier: "tide-at-port")
            .firstMatch.waitForExistence(timeout: 8),
                  "a paired gate links to its reference port")
        XCTAssert(scheduleRowLabels(app) != before,
                  "the detail kept the previous station's timeline — schedule did not change")
        XCUIDevice.shared.orientation = .portrait
    }

    func testM53DoesNotShowNoCurrentCoverageNoticeAtPortsmouth() throws {
        let app = launch("-seedGate", "-resetRecents", "-fixLat", "50.80", "-fixLon", "-1.11")

        let notice = app.staticTexts["Current predictions not available here"].firstMatch
        XCTAssertFalse(notice.waitForExistence(timeout: 2),
                       "Near Me must not show an unactionable current-coverage warning")
    }

    // MARK: - Issue #91: a favorite whose station left the bundle

    /// `chs-north-galiano` is one of the 28 CHS withdrew: it shipped, it is
    /// tombstoned, and it resolves to no StationItem. Such a favorite still
    /// gets a row — render nothing at all and, with one favorite, the
    /// "FAVORITES" header goes with it (#91). Assert the row, not its
    /// neighbour: the card's TITLE has to be the station's real name, which is
    /// the only thing the tombstone file exists to supply.
    func testRemovedFavoriteKeepsItsRowAndOffersAReplacement() throws {
        let app = launch("-seedGate", "-resetRecents",
                         "-seedFavorites", "chs-north-galiano",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
        defer {
            // Leave the simulator as found. `-seedGate` too: FavoritesStore is a
            // lazy singleton, so a relaunch that stops at the first-run gate
            // never touches it and the reset never happens.
            app.launchArguments = ["-seedGate", "-resetFavorites", "-noCloudSync"]
            app.launch()
        }

        XCTAssert(app.staticTexts["FAVORITES"].waitForExistence(timeout: 10),
                  "the section header went with the station it could not render")
        // The TITLE, not the presence of an amber card: the name is the one
        // thing only the tombstone file can supply, so it is the assertion.
        let title = app.staticTexts["North Galiano"].firstMatch
        XCTAssert(title.waitForExistence(timeout: 5),
                  "the removed favorite rendered no row, or rendered one it could not name")
        scrollTo(title, in: app)
        save(app, "issue91-removed-favorite.png")

        // The offer: nearest to where the station WAS. Chemainus is ~50 km up
        // island from the Victoria fix, so a chooser anchored on the user
        // instead of the tombstone would list a visibly different set.
        // ChsAmberCard's action is a .plain Button — the denied-card test reads
        // its twin as a staticText, so accept either element type.
        tapAmberAction(app, "Pick a replacement")
        // `descendants(matching: .any)`, not `otherElements`: the identifier
        // sits on the sheet's root ZStack and does not reliably surface as an
        // `otherElement` (the same reason `listContainer` queries this way).
        let sheet = app.descendants(matching: .any)["station-chooser"].firstMatch
        XCTAssert(sheet.waitForExistence(timeout: 5), "the replacement chooser did not open")
        save(app, "issue91-replacement-chooser.png")

        // THE assertion for #91's anchoring: every offer is a station near
        // where North Galiano WAS (Chemainus, ~1-4 nm) rather than near the
        // simulated Victoria fix ~30 nm south. Anchor the chooser on the user
        // instead and this named gate is nowhere in the list.
        let pick = app.staticTexts["Galiano & Valdes Islands"].firstMatch
        XCTAssert(pick.waitForExistence(timeout: 5),
                  "the chooser is ranked from the wrong position — it offered no Galiano-area station")
        pick.tap()

        // Picking swaps the favorite in place and opens the station.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["FAVORITES"].waitForExistence(timeout: 5),
                  "the swap emptied Favorites instead of taking the removed station's slot")
        XCTAssertFalse(app.staticTexts["North Galiano"].firstMatch.exists,
                       "the removed station is still starred after picking a replacement")
        XCTAssert(app.staticTexts["Galiano & Valdes Islands"].firstMatch.exists,
                  "the replacement did not land in Favorites")
    }

    /// The other exit: there is no Recents to re-file a removed station to, so
    /// its swipe action is true deletion — and it has to actually be reachable.
    func testRemovedFavoriteCanBeRemovedOutright() throws {
        let app = launch("-seedGate", "-resetRecents",
                         "-seedFavorites", "chs-north-galiano",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
        defer {
            // Leave the simulator as found. `-seedGate` too: FavoritesStore is a
            // lazy singleton, so a relaunch that stops at the first-run gate
            // never touches it and the reset never happens.
            app.launchArguments = ["-seedGate", "-resetFavorites", "-noCloudSync"]
            app.launch()
        }

        let title = app.staticTexts["North Galiano"].firstMatch
        XCTAssert(title.waitForExistence(timeout: 10))
        scrollTo(title, in: app)
        title.swipeLeft()
        let remove = app.buttons["Remove"].firstMatch
        XCTAssert(remove.waitForExistence(timeout: 5), "no swipe action on the removed-station row")
        // bounded retap (see pickSearchResult); once the tap lands the button is gone
        let row = app.staticTexts["North Galiano"].firstMatch
        for _ in 0..<3 {
            if remove.exists, remove.isHittable { remove.tap() }
            if row.waitForNonExistence(timeout: 5) { break }
        }
        XCTAssertFalse(row.exists, "the removed favorite came back")
        XCTAssertFalse(app.staticTexts["FAVORITES"].exists,
                       "the only favorite is gone — the group should be too")
    }
}
