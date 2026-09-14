import XCTest
@testable import ShotScribeCore

/// The landing zone's arrangement: the row the operator can reorder, put tiles
/// away from, and read a tally off. The rules that matter are the forgiving
/// ones — what a settings file from another version does to the row, and what
/// happens when someone tries to hide the last way back in.
final class LandingZoneTests: XCTestCase {
    private let domain = "com.joshvanorden.shotscribe.tests.landingzone"
    private var suite: UserDefaults { UserDefaults(suiteName: domain)! }

    override func setUp() {
        super.setUp()
        ShotScribeDefaults.suiteOverride = suite
    }

    override func tearDown() {
        ShotScribeDefaults.suiteOverride = nil
        suite.removePersistentDomain(forName: domain)
        super.tearDown()
    }

    func testTheShippedRowIsTheDefaultOne() {
        let zone = LandingZone()
        XCTAssertEqual(zone.order, LandingZone.shipped)
        XCTAssertEqual(zone.visible, LandingZone.shipped, "nothing is put away to begin with")
        XCTAssertEqual(zone.order.first, .reveal, "Reveal leads, as it always has")
    }

    /// A stored order written by another version must not empty the row or
    /// silently drop a tile this build has.
    func testAStoredOrderIsReconciledWithWhatThisBuildKnows() {
        let stored = ["rebuild", "somethingFromLater", "reveal", "reveal"]
        let order = LandingZone.resolve(order: stored)
        XCTAssertEqual(order.prefix(2).map(\.rawValue), ["rebuild", "reveal"],
                       "what is known keeps the stored order; the unknown name is ignored")
        XCTAssertEqual(Set(order), Set(LandingZone.shipped), "every tile this build has is in the row")
        XCTAssertEqual(order.count, LandingZone.shipped.count, "and each exactly once")
    }

    func testAnEmptyStoredOrderIsTheShippedRow() {
        XCTAssertEqual(LandingZone.resolve(order: []), LandingZone.shipped)
    }

    func testATileKeepsItsPlaceWhileItIsPutAway() {
        var zone = LandingZone()
        XCTAssertTrue(zone.setHidden(.share, true))
        XCTAssertFalse(zone.visible.contains(.share))
        XCTAssertEqual(zone.order, LandingZone.shipped, "the order is untouched — hidden is a set beside it")
        zone.setHidden(.share, false)
        XCTAssertEqual(zone.visible, LandingZone.shipped, "back where it was, not at the end")
    }

    /// Right-clicking the row is how arranging is reached, so the row must
    /// never be emptied.
    func testTheLastVisibleTileCannotBePutAway() {
        var zone = LandingZone()
        for tile in LandingZone.shipped.dropLast() { XCTAssertTrue(zone.setHidden(tile, true)) }
        XCTAssertEqual(zone.visible.count, 1)
        XCTAssertFalse(zone.setHidden(zone.visible[0], true), "the last one is refused")
        XCTAssertEqual(zone.visible.count, 1)
    }

    func testASetThatHidesEverythingIsIgnored() {
        let zone = LandingZone(hidden: Set(LandingZone.Tile.allCases))
        XCTAssertEqual(zone.visible, LandingZone.shipped, "a row with nothing in it is not a row")
    }

    func testDraggingRightLandsAfterTheNeighbourAndLeftLandsInItsPlace() {
        var zone = LandingZone()
        zone.move(.reveal, onto: .rebuild)
        XCTAssertEqual(zone.order.map(\.rawValue),
                       ["markUp", "share", "sendTo", "rebuild", "reveal", "editTitle", "fileAs"])
        zone.move(.fileAs, onto: .markUp)
        XCTAssertEqual(zone.order.first, .fileAs, "dragged left, it takes the slot it was dropped on")
        XCTAssertEqual(zone.order.map(\.rawValue),
                       ["fileAs", "markUp", "share", "sendTo", "rebuild", "reveal", "editTitle"])
    }

    func testMovingATileOntoItselfChangesNothing() {
        var zone = LandingZone()
        zone.move(.share, onto: .share)
        XCTAssertEqual(zone.order, LandingZone.shipped)
    }

    func testTheTallyCountsEveryUse() {
        var zone = LandingZone()
        XCTAssertEqual(zone.uses(of: .reveal), 0)
        zone.note(.reveal); zone.note(.reveal); zone.note(.rebuild)
        XCTAssertEqual(zone.uses(of: .reveal), 2)
        XCTAssertEqual(zone.uses(of: .rebuild), 1)
        XCTAssertEqual(zone.uses(of: .share), 0, "a tile never used says so")
    }

    /// The arrangement is the setting; the tally is evidence about it, and
    /// evidence is not what a reset is for.
    func testResetRestoresTheRowAndKeepsTheCounts() {
        var zone = LandingZone()
        zone.move(.rebuild, onto: .reveal)
        zone.setHidden(.editTitle, true)
        zone.note(.rebuild)
        zone.reset()
        XCTAssertEqual(zone.order, LandingZone.shipped)
        XCTAssertTrue(zone.hidden.isEmpty)
        XCTAssertEqual(zone.uses(of: .rebuild), 1, "the counts survive a reset")
    }

    func testTheArrangementSurvivesARelaunch() {
        var zone = LandingZone()
        zone.move(.sendTo, onto: .reveal)
        zone.setHidden(.editTitle, true)
        zone.note(.sendTo); zone.note(.sendTo); zone.note(.sendTo)
        ShotScribeDefaults.setLandingZone(zone)

        let read = ShotScribeDefaults.landingZone()
        XCTAssertEqual(read.order, zone.order)
        XCTAssertEqual(read.hidden, [.editTitle])
        XCTAssertEqual(read.uses(of: .sendTo), 3)
        XCTAssertEqual(read, zone)
    }

    func testNothingStoredReadsBackAsTheShippedRow() {
        let read = ShotScribeDefaults.landingZone()
        XCTAssertEqual(read.order, LandingZone.shipped)
        XCTAssertTrue(read.hidden.isEmpty)
        XCTAssertEqual(read.uses(of: .reveal), 0)
    }

    /// Junk in the domain — a hand-edited plist, or another version's spelling
    /// — costs a tile's place at worst, never the row.
    func testJunkInTheStoredValuesDoesNotEmptyTheRow() {
        suite.set(["nonsense", "alsoNonsense"], forKey: ShotScribeDefaults.tileOrderKey)
        suite.set(["nope"], forKey: ShotScribeDefaults.tilesHiddenKey)
        suite.set(["reveal": 4, "gone": 9], forKey: ShotScribeDefaults.tileUsesKey)
        let read = ShotScribeDefaults.landingZone()
        XCTAssertEqual(read.order, LandingZone.shipped)
        XCTAssertTrue(read.hidden.isEmpty)
        XCTAssertEqual(read.uses(of: .reveal), 4, "the counts it could read still count")
    }
}
