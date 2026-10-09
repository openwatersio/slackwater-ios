// Slackwater — GPL v3. The station list: its groups, the location slot, the
// swipe actions, and how a station presents itself in a row.
//
// One of the weight-balanced screenshot classes — see ScreenshotTestCase.swift
// for the helpers and for why the suite is split this way.
import UIKit
import XCTest

final class ListAndFavoritesTests: ScreenshotTestCase {
    func testEmptySearchShowsAnAnswerAndKeepsFiltersAvailable() {
        let app = launch("-seedGate", "-locDenied")
        openSearch(app, "zzzzzzzz")
        XCTAssert(app.staticTexts["No matches"].appears(within: 5))
        XCTAssert(app.buttons["Show tides"].exists)
        XCTAssert(app.buttons["Show currents"].exists)
        save(app, "list-no-matches.png")
    }

    func testMissingLocationNamesTheFallbackAnchor() {
        let app = launch("-seedGate", "-resetRecents", "-locDenied")
        XCTAssert(app.staticTexts["Showing places near Chesapeake Bay"].appears(within: 5))
        save(app, "list-location-fallback.png")
    }

    func testMissingLocationNamesTheLastOpenedPlace() {
        let app = launch("-seedGate", "-resetRecents", "-locDenied")
        openFridayHarbor(app)
        goBack(app)
        let origin = app.staticTexts["Showing places near Friday Harbor"].firstMatch
        scrollTo(origin, in: app)
        XCTAssert(origin.exists)
        save(app, "list-location-last-place.png")
    }

    func testApproximateLocationDoesNotPresentPreciseCoordinates() {
        let app = launch("-seedGate", "-resetRecents", "-locApproximate",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
        XCTAssert(app.staticTexts["Approximate location"].appears(within: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '°N'")).firstMatch.exists)
        save(app, "list-location-approximate.png")
    }

    // The list's groups — My Location hero (nm pill, 3-dp coords, no
    // match-grade sentence), Recents after a visit, Near Me, and the utility
    // footer (no catalog section, no units pill).
    func testM41GroupedListAndRecents() throws {
        // Deterministic Victoria fix via the -fixLat/-fixLon hook. Favorites
        // reset too: this test asserts group ORDER from a clean list, so its
        // launch args enforce that — not the goodwill of every earlier test
        // on the simulator (a leaked favorite pushed RECENTS past the iPad
        // sidebar's bounded scroll, 2026-08-08).
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
        XCTAssert(app.staticTexts["My Location"].appears(within: 10))
        XCTAssert(app.staticTexts["Near Me"].exists)
        // No full-catalog section, no units pill.
        XCTAssertFalse(app.staticTexts["Salish Sea"].exists)
        XCTAssertFalse(app.buttons["FT"].exists)
        XCTAssertFalse(app.buttons["M"].exists)
        // Tile copy: coordinates only — no "to station"/match-grade sentence.
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '°N'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'to station'")).firstMatch.exists)
        // No recents yet on a clean run.
        XCTAssertFalse(app.staticTexts["Recents"].exists)

        // Visit a station; it must appear under Recents — the last station
        // group (order: My Location → Favorites → Near Me → Recents).
        openFridayHarbor(app)
        goBack(app)
        let near = app.staticTexts["Near Me"].firstMatch
        XCTAssert(near.appears(within: 5))
        let recentsLabel = app.staticTexts["Recents"].firstMatch
        scrollTo(recentsLabel, in: app)
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists)
        // Both labels realized (tall screens / short lists): direct order
        // check. The sidebar reflows as CHS pending cards above update, so
        // read both frames together and wait them out (settled — see
        // `settled`'s doc in ScreenshotTestCase) rather than reading each live.
        if near.exists {
            let f = settled { [near.frame, recentsLabel.frame] }
            XCTAssert(f[0].minY < f[1].minY,
                      "Recents must render below Near Me")
        }
        let settings = app.buttons["Settings"].firstMatch
        scrollTo(settings, in: app)
        let signature = app.staticTexts["Slackwater"].firstMatch
        scrollTo(signature, in: app)
        XCTAssert(app.buttons["offline-status"].firstMatch.isHittable)
        XCTAssert(settings.isHittable)
        XCTAssert(app.staticTexts["by Open Waters"].isHittable)
        XCTAssert(settings.frame.maxY < signature.frame.minY)
        save(app, "m41-list-footer.png")
        settings.tap()
        XCTAssert(app.navigationBars["Settings"].appears(within: 5))
        app.buttons["Done"].tap()
        let downloads = app.buttons["offline-status"].firstMatch
        scrollTo(downloads, in: app)
        downloads.tap()
        XCTAssert(app.navigationBars["Downloads"].appears(within: 5))
    }

    /// #359: the My Location tile is ONE List row carrying two cards, and a
    /// List row activates every navigation link inside it — cards that carry
    /// links land a tap two pushes deep, on the other hero station, with the
    /// one you tapped underneath it on the back stack.
    func testHeroCardOpensTheStationYouTapped() throws {
        // Victoria fix: the hero is the CHS port "Victoria" (nearest, tide)
        // over "Tillicum Bridge" (the nearest current inside the nearby
        // radius) — NationalScaleTests pins that this fix gets both series.
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")
        XCTAssert(app.staticTexts["My Location"].appears(within: 10))
        let hero = listContainer(app).staticTexts["Victoria"].firstMatch
        XCTAssert(hero.appears(within: 10), "the My Location tile has no Victoria card")
        hero.tap()

        let title = app.descendants(matching: .any)["detail-title"].firstMatch
        XCTAssert(title.appears(within: 10), "the hero card opened no detail")
        XCTAssert(title.label.contains("Victoria"),
                  "tapping the first hero card opened \(title.label)")
        // One back, and you are on the list — not on the other hero station.
        goBack(app)
    }

    // Location denied — the amber card sits in the My Location slot, above
    // The example area is labeled honestly when location is denied.
    func testM41DeniedSlot() throws {
        let app = launch("-seedGate", "-resetRecents", "-locDenied")
        XCTAssert(app.staticTexts["Location unavailable"].appears(within: 5))
        XCTAssert(app.images["Location unavailable"].exists)
        XCTAssert(app.staticTexts["Go to Settings"].exists)
        XCTAssert(app.staticTexts["My Location"].exists)
        XCTAssert(app.staticTexts["Chesapeake Bay"].exists)
        XCTAssert(app.staticTexts["Annapolis (US Naval Academy)"].firstMatch.exists)
        XCTAssert(app.staticTexts["Greenbury Point, 1.6 nm east of"].firstMatch.exists)
    }

    /// Past the gate with the choice never made — the "or search" bypass, or
    /// iOS "Ask Next Time Or When I Share" resetting an answered app. That
    /// state used to render an empty slot and never prompt.
    ///
    /// `-locUndetermined` rather than simply omitting the location flags: the
    /// no-flag version reads the simulator's OWN authorization, which is
    /// undetermined only on a device that has never answered. It passed on a
    /// clean simulator and failed on CI, whose device carries an `Authorization`
    /// key from an earlier answer.
    func testM41UndeterminedSlotOffersTheAsk() throws {
        let app = launch("-seedGate", "-resetRecents", "-locUndetermined")
        XCTAssert(app.staticTexts["Location unavailable"].appears(within: 5))
        XCTAssert(app.images["Location"].exists)
        XCTAssert(app.staticTexts["Find tides near me"].exists)
        XCTAssert(app.staticTexts["Showing places near Chesapeake Bay"].exists)
        XCTAssert(app.staticTexts["Chesapeake Bay"].exists)
        save(app, "m41-location-ask.png")
    }

    func testM41AuthorizedLocationKeepsItsSlotWhileWaitingForAFix() throws {
        let app = launch("-seedGate", "-resetRecents", "-locAuthorizedNoFix")
        XCTAssert(app.staticTexts["My Location"].appears(within: 5))
        XCTAssert(app.staticTexts["Finding your location…"].exists)
        XCTAssert(app.staticTexts["Chesapeake Bay"].exists)
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
        XCTAssert(star.appears(within: 5), "favorite star missing from the waiting detail")
        star.tap()
        XCTAssert(app.buttons["Remove favorite"].appears(within: 5),
                  "star did not flip to favorited on the waiting detail")

        // Back to the list: the favorite must RESOLVE — a Favorites group
        // with the gate in it, not a phantom id and no group at all.
        goBack(app)
        // iPhone closes search with the push; the iPad sidebar keeps it open.
        if app.buttons["Close search"].firstMatch.exists { closeSearch(app) }
        XCTAssert(stationList(app).appears(within: 5))
        XCTAssert(app.staticTexts["Favorites"].appears(within: 5),
                  "favoriting a pending CHS gate produced no Favorites group — the star wrote an id the list cannot resolve")
        let row = app.staticTexts["Dodd Narrows"].firstMatch
        XCTAssert(row.exists, "the favorited pending gate is missing from the Favorites group")

        // Leave the simulator as found: swipe-unfavorite the row so later
        // tests that assume a clean favorites store aren't ambushed.
        settleLayout(row)
        listContainer(app).cells.containing(.staticText, identifier: row.label).firstMatch.swipeLeft()
        XCTAssert(app.buttons["Unfavorite"].appears(within: 5))
        app.buttons["Unfavorite"].firstMatch.tap()
        _ = app.staticTexts["Favorites"].disappears(within: 10)
        XCTAssertFalse(app.staticTexts["Favorites"].exists,
                       "cleanup unfavorite left the Favorites group behind")
    }

    /// The origin report: a fresh install can FIND Sechelt Rapids by its
    /// "skookumchuck" alias, and the tap lands on the honest explanation, not a
    /// dead end. `-chsResetModels` leaves no stored window (it wipes the
    /// whole `ChsModelStore.dir`, `-online.json` included — same directory as
    /// the fitted files); `-networkKillSwitch` is what keeps the honesty card
    /// up for the length of the test — without it, `OnlineGateDetailView.onAppear`
    /// fires a REAL IWLS fetch the moment the honesty card would otherwise be
    /// asserted, and a fetch that lands mid-test would swap it for the fetched
    /// detail out from under the assertions (TestSeeds.swift's
    /// `seedOnlineWindow` doc comment covers the other half of this same
    /// coverage question). The nearest-gate-link push is NOT a list-driven
    /// reset (`OpenChsRouteKey`'s doc comment, Theme.swift): it
    /// stacks onto Sechelt's own detail, so one `detail-back` lands back on
    /// Sechelt, not the list — which is exactly the page this test stars, to
    /// exercise the bare-id favorite rule (ChsCurrentGate.swift's `itemId`
    /// comment, the 2026-08-08 fresh-install bug) on an online gate
    /// specifically, never fitted, never queued.
    func testOnlineGateUnfetchedShowsHonestyCard() throws {
        let app = launch("-chsResetModels", "-seedGate", "-networkKillSwitch",
                         "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        openSearch(app, "skookumchuck")
        pickSearchResult(app, app.staticTexts["Sechelt Rapids"].firstMatch)

        let honesty = app.descendants(matching: .any)["online-honesty-card"].firstMatch
        XCTAssert(honesty.appears(within: 5),
                  "an online gate with no window must show the honesty card, never a dead end")
        // Cold open: nothing downloaded, so no week the picker could reach is
        // any better than this one — the bar stays down (#172). The recovery
        // case, a stored window paged off, keeps it: OfflineCoverageTests
        // .testOnlineGatePagedBeyondItsWindowOffline.
        XCTAssertFalse(app.descendants(matching: .any)["week-range-bar"].firstMatch.exists,
                       "no stored window: the week-range bar has nowhere to go")

        // Its one tap out: the nearest of the 11 shipped (fittable) gates —
        // Dodd Narrows, ~67 km away. Bundled-identity distance, independent of
        // the fix, so this is deterministic without depending on -fixLat/-fixLon.
        let link = app.descendants(matching: .any)["nearest-gate-link"].firstMatch
        XCTAssert(link.appears(within: 5), "nearest-gate-link missing from the honesty card")
        if !link.isHittable { app.swipeUp() }  // it sits under the honesty card — likely already clear
        XCTAssert(link.isHittable, "nearest-gate-link exists but never became hittable")
        link.tap()

        // Scoped to the now-active detail header, not a bare name lookup: on
        // iPad the persistent sidebar can carry "Dodd Narrows" in its own Near
        // Me ranking independently of what's pushed, so the name alone is a
        // secondary tell at best.
        let header = app.otherElements["detail-header"].firstMatch
        XCTAssert(header.appears(within: 5), "nearest-gate-link did not open a detail")
        XCTAssert(header.staticTexts["Dodd Narrows"].firstMatch.exists,
                  "nearest-gate-link did not land on the nearest shipped gate's detail")

        // Back to Sechelt's own (still-honesty) detail — one pop, since the
        // link pushed rather than reset the path.
        goBack(app, to: app.descendants(matching: .any)["online-honesty-card"].firstMatch)
        XCTAssert(app.descendants(matching: .any)["online-honesty-card"].firstMatch.appears(within: 5),
                  "one back from the nearest-gate-link push should land on Sechelt's own honesty card")

        // Star round-trip on the online gate itself — the bare-id rule.
        let star = app.buttons["detail-favorite"].firstMatch
        XCTAssert(star.appears(within: 5), "favorite star missing from the honesty-card detail")
        star.tap()
        XCTAssert(app.buttons["Remove favorite"].appears(within: 5),
                  "star did not flip to favorited on the honesty-card detail")

        // Back to the list: the favorite must RESOLVE — a Favorites group with
        // Sechelt Rapids in it, not a phantom id and no group at all.
        goBack(app)
        // iPhone closes search with the push; the iPad sidebar keeps it open.
        if app.buttons["Close search"].firstMatch.exists { closeSearch(app) }
        XCTAssert(stationList(app).appears(within: 5))
        XCTAssert(app.staticTexts["Favorites"].appears(within: 5),
                  "favoriting an online gate produced no Favorites group — the star wrote an id the list cannot resolve")
        let row = app.staticTexts["Sechelt Rapids"].firstMatch
        XCTAssert(row.exists, "the favorited online gate is missing from the Favorites group")

        // Leave the simulator as found.
        settleLayout(row)
        listContainer(app).cells.containing(.staticText, identifier: row.label).firstMatch.swipeLeft()
        XCTAssert(app.buttons["Unfavorite"].appears(within: 5))
        app.buttons["Unfavorite"].firstMatch.tap()
        _ = app.staticTexts["Favorites"].disappears(within: 10)
        XCTAssertFalse(app.staticTexts["Favorites"].exists,
                       "cleanup unfavorite left the Favorites group behind")
    }

    // Favorites — the detail-header star files a station under a Favorites
    // group (My Location → Favorites → Recents → Near Me), favorites/hero never
    // repeat in Recents, and the swipe actions manage the groups.
    func testM43FavoritesAndSwipeActions() throws {
        // Deterministic Victoria fix; clean favorites/recents.
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        // Star Friday Harbor from its detail (upper-right, back's mirror).
        openFridayHarbor(app)
        let star = app.buttons["detail-favorite"].firstMatch
        XCTAssert(star.appears(within: 5), "favorite star missing from detail header")
        star.tap()
        XCTAssert(app.buttons["Remove favorite"].appears(within: 5),
                  "star did not flip to favorited in the header")

        // Back: a Favorites group holds it, and it does NOT repeat in Recents
        // (it was just visited — favorites win the dedupe).
        goBack(app)
        XCTAssert(app.staticTexts["Favorites"].appears(within: 5))
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Recents"].exists,
                       "a favorited station must not also render under Recents")

        // Visit a second station so Recents renders too — all four groups.
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass State Park"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        goBack(app)
        XCTAssert(app.staticTexts["My Location"].appears(within: 5))
        XCTAssert(app.staticTexts["Favorites"].exists)
        XCTAssert(app.staticTexts["Near Me"].exists)

        // Swipe open the Recents row: red destructive Remove. Recents is the
        // last group, so scroll to the ROW — and to the row rather than the
        // group label, because the swipe has to land on the row itself and not
        // on the FAB pinned over the bottom of the list (see `scrollTo`).
        let parkRow = app.staticTexts["Deception Pass State Park"].firstMatch
        scrollTo(parkRow, in: app)
        listContainer(app).cells.containing(.staticText, identifier: parkRow.label).firstMatch.swipeLeft()
        XCTAssert(app.buttons["Remove"].appears(within: 5),
                  "trailing swipe did not reveal the Recents remove action")
        app.buttons["Remove"].firstMatch.tap()
        _ = app.staticTexts["Deception Pass State Park"].disappears(within: 10)
        XCTAssertFalse(app.staticTexts["Deception Pass State Park"].exists,
                       "remove-from-recents left the row behind")

        // Swipe-unfavorite Friday Harbor (back near the top): it leaves
        // Favorites and re-files under Recents — a move, not a deletion —
        // which means the bottom of the list.
        listContainer(app).swipeDown()
        listContainer(app).swipeDown()
        let fridayRow = app.staticTexts["Friday Harbor"].firstMatch
        XCTAssert(fridayRow.appears(within: 5))
        settleLayout(fridayRow)
        listContainer(app).cells.containing(.staticText, identifier: fridayRow.label).firstMatch.swipeLeft()
        XCTAssert(app.buttons["Unfavorite"].appears(within: 5),
                  "trailing swipe did not reveal the favorites remove action")
        app.buttons["Unfavorite"].firstMatch.tap()
        _ = app.staticTexts["Favorites"].disappears(within: 10)
        XCTAssertFalse(app.staticTexts["Favorites"].exists,
                       "unfavorite left the Favorites group behind")
        // Scroll to the ROW, not to the group label: how many rows Recents has
        // depends on what this simulator has downloaded, so the label can land
        // on the last visible line with the row below the fold.
        let refiled = app.staticTexts["Friday Harbor"].firstMatch
        scrollTo(refiled, in: app)
        XCTAssert(refiled.exists, "unfavorited station did not re-file to Recents")
        // The device is left as found: the unfavorite above — an assertion in
        // its own right — empties Favorites again, and Recents is what the
        // tests that care about it reset with -resetRecents.
    }

    // The speed-unit setting rewrites a current detail's readout. Its own
    // launch and its own test: the setting is app-wide persisted state, so it
    // is switched and put back inside one test rather than shared with the
    // favorites walk above, which then needs no scroll back up to Settings.
    func testM43SpeedUnitRewritesTheCurrentReadout() throws {
        // Deterministic Victoria fix; clean favorites/recents.
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "48.4235", "-fixLon", "-123.3705")

        // Speed units: switch to km/h in Settings, the current detail follows.
        openSettings(app)
        let kmh = app.buttons["km/h"]
        XCTAssert(kmh.appears(within: 5), "speed-unit switch missing from Settings")
        kmh.tap()
        app.buttons["Done"].tap()
        XCTAssert(stationList(app).appears(within: 5))
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'km/h'")).firstMatch.appears(within: 5),
                  "current detail readout did not follow the km/h setting")
    }

    // MARK: - Station identity presentation

    /// Same-named stations render as ONE entry in the list, with the namesakes
    /// behind the chooser on the station page — four "Cape Cod Canal" cards
    /// side by side look identical. Pick the non-nearest one from that chooser
    /// and the list shows that one from then on.
    func testM50MatchingStationChooser() throws {
        // Upright: the split-layout test leaves the device in landscape, and
        // these screenshots are the ones a human reads.
        XCUIDevice.shared.orientation = .portrait
        // The fix is put ON the Bournedale gauge: standing at the station is
        // the deterministic way to put a collided name at the top of the list.
        let app = launch("-seedGate", "-resetRecents", "-resetFavorites",
                         "-fixLat", "41.77", "-fixLon", "-70.5617")  // Cape Cod Canal, Bournedale
        XCTAssert(app.staticTexts["Near Me"].appears(within: 10))

        // One entry, not four: the nearest gauge renders, the others are
        // behind the chooser. Sagamore, 2.3 km away, would rank in Near Me.
        // Scoped to the LIST: at regular width the detail pane auto-opens on the
        // first row, so an unscoped count also picks up its header title.
        let cards = listContainer(app).staticTexts
            .matching(NSPredicate(format: "label == %@", "Cape Cod Canal"))
        XCTAssertEqual(cards.count, 1, "same-named stations must render as one entry")
        XCTAssertFalse(listContainer(app).staticTexts["Sagamore"].exists,
                       "a farther namesake must not render as its own card")

        // The list offers no chooser; the station page does.
        XCTAssertFalse(listContainer(app).descendants(matching: .any)["matching-stations"].exists,
                       "the list must not offer the chooser")
        cards.firstMatch.tap()
        let header = app.otherElements["detail-header"].firstMatch
        XCTAssert(header.appears(within: 8), "the entry did not open its station")
        // By region, scoped to the header: a current station named Bournedale
        // sits 600 m away, so a bare text match would find its card instead.
        XCTAssert(header.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Bournedale"))
            .firstMatch.exists, "the nearest one is the entry")
        let chooserButton = app.buttons["matching-stations"].firstMatch
        XCTAssert(chooserButton.appears(within: 8), "no matching-station affordance on the station page")
        XCTAssertEqual(chooserButton.label, "Other locations (3)")
        chooserButton.tap()

        XCTAssert(app.descendants(matching: .any)["station-chooser"].firstMatch.appears(within: 5),
                  "the chooser sheet did not open")
        func labelled(_ query: XCUIElementQuery, _ text: String) -> XCUIElement {
            query.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        let rows = app.buttons.matching(identifier: "chooser-station")
        XCTAssert(rows.firstMatch.appears(within: 5))
        XCTAssertEqual(rows.count, 4)
        let shownRow = labelled(rows, "Cape Cod Canal, Bournedale")
        let farRow = labelled(rows, "Cape Cod Canal, RR. Bridge")
        XCTAssert(farRow.exists, "the chooser must offer the station the list collapsed")
        XCTAssert(shownRow.isSelected, "the chooser must open on the station the list shows")
        XCTAssert(labelled(rows, "from you").exists, "a row must say what its distance is from")
        XCTAssert(app.staticTexts["Tide · NOAA"].firstMatch.exists,
                  "a chooser row must say what it measures and whose data it is")

        // The map holds exactly the candidates; a pin selects its row and
        // does not open the station.
        let pins = app.buttons.matching(identifier: "chooser-pin")
        XCTAssert(pins.firstMatch.appears(within: 15), "the chooser map drew no pins")
        XCTAssertEqual(pins.count, 4)
        let farPin = labelled(pins, "Cape Cod Canal, RR. Bridge")
        farPin.tap()
        wait(for: [expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: farRow)],
             timeout: 5)
        XCTAssert(farPin.isSelected)
        XCTAssertFalse(shownRow.isSelected, "selection must move, not add")
        // Opened from a station page, so a header is always under the sheet;
        // the sheet itself staying up is what says the pin opened nothing.
        XCTAssert(app.descendants(matching: .any)["station-chooser"].firstMatch.exists,
                  "a pin tap closed the chooser")
        save(app, "chooser-map.png")

        // Picking the collapsed one opens it — it is not lost, just quiet.
        farRow.tap()
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "RR. Bridge"))
            .firstMatch.appears(within: 8), "the chooser pick did not open that station")
        save(app, "chooser-detail-link.png")

        // The pick opened on top of the nearest station's page: back twice to
        // the list, which remembers it — the chosen station takes the place's
        // entry. Landed on the nearest station's page, by its region in the
        // header — the pushed page has a header and a back button of its own,
        // so neither says which page is showing. Scoped to the header: the
        // iPad sidebar carries the same string.
        goBack(app, to: app.otherElements["detail-header"].firstMatch.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Bournedale")).firstMatch)
        goBack(app)
        let list = listContainer(app)
        XCTAssert(list.staticTexts["RR. Bridge"].firstMatch.appears(within: 5),
                  "the list must show the chosen station")
        // The previously opened namesake remains in Recents below this replacement.
        save(app, "chooser-remembered.png")
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
        pickSearchResult(app, app.staticTexts["Discovery Island, 3.0 nm NE of"].firstMatch)
        XCTAssert(app.otherElements["detail-header"].appears(within: 8))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "tide-at-port").firstMatch.exists,
                       "an unpaired current station has no reference port to link")
        let before = scheduleRowLabels(app)
        XCTAssert(!before.isEmpty, "no schedule rows read from the first station")

        // Second station, same kind — in the split layout this replaces the
        // detail pane without a pop.
        openSearch(app, "deception pass (n")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Deception Pass (Narrows)"].firstMatch
            .appears(within: 8))
        XCTAssert(app.descendants(matching: .any).matching(identifier: "tide-at-port")
            .firstMatch.appears(within: 8),
                  "a paired gate links to its reference port")
        XCTAssert(scheduleRowLabels(app) != before,
                  "the detail kept the previous station's timeline — schedule did not change")
        XCUIDevice.shared.orientation = .portrait
    }

    func testM53DoesNotShowNoCurrentCoverageNoticeAtPortsmouth() throws {
        let app = launch("-seedGate", "-resetRecents", "-fixLat", "50.80", "-fixLon", "-1.11")

        let notice = app.staticTexts["Current predictions not available here"].firstMatch
        XCTAssertFalse(notice.appears(within: 2),
                       "Near Me must not show an unactionable current-coverage warning")
    }

    // MARK: - Issue #91: a favorite whose station left the bundle

    /// `chs-north-galiano` is one of the 28 CHS withdrew: it shipped, it is
    /// tombstoned, and it resolves to no StationItem. Such a favorite still
    /// gets a row — render nothing at all and, with one favorite, the
    /// "Favorites" header goes with it (#91). Assert the row, not its
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
            app.launchArguments = testArguments(["-seedGate", "-resetFavorites"])
            app.launch()
        }

        XCTAssert(app.staticTexts["Favorites"].appears(within: 10),
                  "the section header went with the station it could not render")
        // The TITLE, not the presence of an amber card: the name is the one
        // thing only the tombstone file can supply, so it is the assertion.
        let title = app.staticTexts["North Galiano"].firstMatch
        XCTAssert(title.appears(within: 5),
                  "the removed favorite rendered no row, or rendered one it could not name")
        XCTAssert(app.images["Station removed"].exists)
        scrollTo(title, in: app)
        save(app, "issue91-removed-favorite.png")

        // The offer: nearest to where the station WAS. Chemainus is ~50 km up
        // island from the Victoria fix, so a chooser anchored on the user
        // instead of the tombstone would list a visibly different set.
        // ChsAmberCard's action is a .plain Button — the denied-card test reads
        // its twin as a staticText, so accept either element type.
        tapAmberAction(app, "Choose another station")
        // `descendants(matching: .any)`, not `otherElements`: the identifier
        // sits on the sheet's root ZStack and does not reliably surface as an
        // `otherElement` (the same reason `listContainer` queries this way).
        let sheet = app.descendants(matching: .any)["station-chooser"].firstMatch
        XCTAssert(sheet.appears(within: 5), "the replacement chooser did not open")
        save(app, "issue91-replacement-chooser.png")

        // THE assertion for #91's anchoring: every offer is a station near
        // where North Galiano WAS (Chemainus, ~1-4 nm) rather than near the
        // simulated Victoria fix ~30 nm south. Anchor the chooser on the user
        // instead and this named gate is nowhere in the list.
        let pick = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Galiano & Valdes Islands")).firstMatch
        XCTAssert(pick.appears(within: 5),
                  "the chooser is ranked from the wrong position — it offered no Galiano-area station")
        pick.tap()

        // Picking swaps the favorite in place and opens the station.
        goBack(app)
        XCTAssert(app.staticTexts["Favorites"].appears(within: 5),
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
            app.launchArguments = testArguments(["-seedGate", "-resetFavorites"])
            app.launch()
        }

        let title = app.staticTexts["North Galiano"].firstMatch
        XCTAssert(title.appears(within: 10))
        scrollTo(title, in: app)
        listContainer(app).cells.containing(.staticText, identifier: title.label).firstMatch.swipeLeft()
        let remove = app.buttons["Remove"].firstMatch
        XCTAssert(remove.appears(within: 5), "no swipe action on the removed-station row")
        // bounded retap (see pickSearchResult); once the tap lands the button is gone
        let row = app.staticTexts["North Galiano"].firstMatch
        for _ in 0..<3 {
            if remove.exists, remove.isHittable { remove.tap() }
            if row.disappears(within: 5) { break }
        }
        XCTAssertFalse(row.exists, "the removed favorite came back")
        XCTAssertFalse(app.staticTexts["Favorites"].exists,
                       "the only favorite is gone — the group should be too")
    }
}
