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
        XCTAssert(app.staticTexts["MY LOCATION"].appears(within: 10))
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
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 5))
        let near = app.staticTexts["NEAR ME"].firstMatch
        XCTAssert(near.appears(within: 5))
        let recentsLabel = app.staticTexts["RECENTS"].firstMatch
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
    }

    // Location denied — the amber card sits in the My Location slot, above
    // Near Me ranked from the fallback.
    func testM41DeniedSlot() throws {
        let app = launch("-seedGate", "-resetRecents", "-locDenied")
        XCTAssert(app.staticTexts["Location unavailable"].appears(within: 5))
        XCTAssert(app.staticTexts["Go to Settings"].exists)
        XCTAssertFalse(app.staticTexts["MY LOCATION"].exists)
        XCTAssert(app.staticTexts["NEAR ME"].exists)
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
        XCTAssert(app.staticTexts["See stations near you"].appears(within: 5))
        XCTAssert(app.staticTexts["Use My Location"].exists)
        XCTAssertFalse(app.staticTexts["Location unavailable"].exists)
        XCTAssert(app.staticTexts["NEAR ME"].exists)
        save(app, "m41-location-ask.png")
    }

    func testM41AuthorizedLocationKeepsItsSlotWhileWaitingForAFix() throws {
        let app = launch("-seedGate", "-resetRecents", "-locAuthorizedNoFix")
        XCTAssert(app.staticTexts["MY LOCATION"].appears(within: 5))
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
        XCTAssert(star.appears(within: 5), "favorite star missing from the waiting detail")
        star.tap()
        XCTAssert(app.buttons["Remove favorite"].appears(within: 5),
                  "star did not flip to favorited on the waiting detail")

        // Back to the list: the favorite must RESOLVE — a Favorites group
        // with the gate in it, not a phantom id and no group at all.
        app.buttons["detail-back"].firstMatch.tap()
        // iPhone closes search with the push; the iPad sidebar keeps it open.
        if app.buttons["Close search"].firstMatch.exists { closeSearch(app) }
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 5))
        XCTAssert(app.staticTexts["FAVORITES"].appears(within: 5),
                  "favoriting a pending CHS gate produced no Favorites group — the star wrote an id the list cannot resolve")
        let row = app.staticTexts["Dodd Narrows"].firstMatch
        XCTAssert(row.exists, "the favorited pending gate is missing from the Favorites group")

        // Leave the simulator as found: swipe-unfavorite the row so later
        // tests that assume a clean favorites store aren't ambushed.
        row.swipeLeft()
        XCTAssert(app.buttons["Unfavorite"].appears(within: 5))
        app.buttons["Unfavorite"].firstMatch.tap()
        _ = app.staticTexts["FAVORITES"].disappears(within: 10)
        XCTAssertFalse(app.staticTexts["FAVORITES"].exists,
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
        app.buttons["detail-back"].firstMatch.tap()
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
        app.buttons["detail-back"].firstMatch.tap()
        // iPhone closes search with the push; the iPad sidebar keeps it open.
        if app.buttons["Close search"].firstMatch.exists { closeSearch(app) }
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 5))
        XCTAssert(app.staticTexts["FAVORITES"].appears(within: 5),
                  "favoriting an online gate produced no Favorites group — the star wrote an id the list cannot resolve")
        let row = app.staticTexts["Sechelt Rapids"].firstMatch
        XCTAssert(row.exists, "the favorited online gate is missing from the Favorites group")

        // Leave the simulator as found.
        row.swipeLeft()
        XCTAssert(app.buttons["Unfavorite"].appears(within: 5))
        app.buttons["Unfavorite"].firstMatch.tap()
        _ = app.staticTexts["FAVORITES"].disappears(within: 10)
        XCTAssertFalse(app.staticTexts["FAVORITES"].exists,
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
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 5))
        XCTAssert(app.staticTexts["FAVORITES"].appears(within: 5))
        XCTAssert(app.staticTexts["Friday Harbor"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["RECENTS"].exists,
                       "a favorited station must not also render under Recents")

        // Visit a second station so Recents renders too — all four groups.
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass State Park"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 5))
        XCTAssert(app.staticTexts["MY LOCATION"].appears(within: 5))
        XCTAssert(app.staticTexts["FAVORITES"].exists)
        XCTAssert(app.staticTexts["NEAR ME"].exists)

        // Swipe open the Recents row: red destructive Remove. Recents is the
        // last group, so scroll to the ROW — and to the row rather than the
        // group label, because the swipe has to land on the row itself and not
        // on the FAB pinned over the bottom of the list (see `scrollTo`).
        let parkRow = app.staticTexts["Deception Pass State Park"].firstMatch
        scrollTo(parkRow, in: app)
        parkRow.swipeLeft()
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
        fridayRow.swipeLeft()
        XCTAssert(app.buttons["Unfavorite"].appears(within: 5),
                  "trailing swipe did not reveal the favorites remove action")
        app.buttons["Unfavorite"].firstMatch.tap()
        _ = app.staticTexts["FAVORITES"].disappears(within: 10)
        XCTAssertFalse(app.staticTexts["FAVORITES"].exists,
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
        app.buttons["Settings"].tap()
        let kmh = app.buttons["km/h"]
        XCTAssert(kmh.appears(within: 5), "speed-unit switch missing from Settings")
        kmh.tap()
        app.buttons["Done"].tap()
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 5))
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'km/h'")).firstMatch.appears(within: 5),
                  "current detail readout did not follow the km/h setting")
        // Leave the store on knots for the other tests. No launch argument
        // resets the unit — it is plain persisted app state — so the way back
        // is the same Settings round trip that set it.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 5))
        app.buttons["Settings"].tap()
        let kn = app.buttons["Knots"]
        XCTAssert(kn.appears(within: 5))
        kn.tap()
        app.buttons["Done"].tap()
    }

    // MARK: - Station identity presentation

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
        XCTAssert(app.staticTexts["NEAR ME"].appears(within: 10))

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
        XCTAssert(chooserButton.appears(within: 5),
                  "no matching-station affordance on a collided name")
        // Three since #268: the NOAA subordinate "2.6 nm SSE" (PCT1411) joined
        // the two harmonic stations.
        XCTAssert(app.staticTexts["3 matching stations"].firstMatch.exists)
        chooserButton.tap()

        // The chooser: both stations, each with what it measures and how far.
        XCTAssert(app.otherElements["station-chooser"].appears(within: 5)
                  || app.staticTexts["3.0 nm NE"].firstMatch.appears(within: 5),
                  "the chooser sheet did not open")
        XCTAssert(app.staticTexts["6.6 nm SSE"].firstMatch.appears(within: 5),
                  "the chooser must offer the station the list collapsed")
        XCTAssert(app.staticTexts["CURRENT · NOAA"].firstMatch.exists,  // MonoLabel uppercases
                  "a chooser row must say what it measures and whose data it is")

        // Picking the collapsed one opens it — it is not lost, just quiet.
        app.staticTexts["6.6 nm SSE"].firstMatch.tap()
        XCTAssert(app.staticTexts["Discovery Island"].firstMatch.appears(within: 8))
        XCTAssert(app.otherElements["detail-header"].appears(within: 8),
                  "the chooser pick did not open a station detail")

        // Recents keeps the station actually opened: the chooser pick is an
        // explicit choice, not the distance ranking. Collapse it into the
        // nearest namesake's id and Recents silently shows and reopens "3.0 nm
        // NE" instead of the "6.6 nm SSE" station tapped. Same disambiguating
        // field the chooser assertions above key on (each station's region is
        // literally its bearing string), so a bare text match is unambiguous.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 5))
        let recentsLabel = app.staticTexts["RECENTS"].firstMatch
        scrollTo(recentsLabel, in: app)
        let recentPick = app.staticTexts["6.6 nm SSE"].firstMatch
        scrollTo(recentPick, in: app)
        XCTAssert(recentPick.exists,
                  "Recents must keep the chooser-picked station, not collapse it into the nearest namesake")
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

        XCTAssert(app.staticTexts["FAVORITES"].appears(within: 10),
                  "the section header went with the station it could not render")
        // The TITLE, not the presence of an amber card: the name is the one
        // thing only the tombstone file can supply, so it is the assertion.
        let title = app.staticTexts["North Galiano"].firstMatch
        XCTAssert(title.appears(within: 5),
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
        XCTAssert(sheet.appears(within: 5), "the replacement chooser did not open")
        save(app, "issue91-replacement-chooser.png")

        // THE assertion for #91's anchoring: every offer is a station near
        // where North Galiano WAS (Chemainus, ~1-4 nm) rather than near the
        // simulated Victoria fix ~30 nm south. Anchor the chooser on the user
        // instead and this named gate is nowhere in the list.
        let pick = app.staticTexts["Galiano & Valdes Islands"].firstMatch
        XCTAssert(pick.appears(within: 5),
                  "the chooser is ranked from the wrong position — it offered no Galiano-area station")
        pick.tap()

        // Picking swaps the favorite in place and opens the station.
        app.buttons["detail-back"].firstMatch.tap()
        XCTAssert(app.staticTexts["Slackwater"].appears(within: 5))
        XCTAssert(app.staticTexts["FAVORITES"].appears(within: 5),
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
        XCTAssert(title.appears(within: 10))
        scrollTo(title, in: app)
        title.swipeLeft()
        let remove = app.buttons["Remove"].firstMatch
        XCTAssert(remove.appears(within: 5), "no swipe action on the removed-station row")
        // bounded retap (see pickSearchResult); once the tap lands the button is gone
        let row = app.staticTexts["North Galiano"].firstMatch
        for _ in 0..<3 {
            if remove.exists, remove.isHittable { remove.tap() }
            if row.disappears(within: 5) { break }
        }
        XCTAssertFalse(row.exists, "the removed favorite came back")
        XCTAssertFalse(app.staticTexts["FAVORITES"].exists,
                       "the only favorite is gone — the group should be too")
    }
}
