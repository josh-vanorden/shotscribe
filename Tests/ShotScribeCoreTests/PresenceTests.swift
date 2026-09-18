import XCTest
@testable import ShotScribeCore

final class PresenceTests: XCTestCase {
    private let domain = "com.joshvanorden.shotscribe.tests.presence"
    private var suite: UserDefaults { UserDefaults(suiteName: domain)! }

    override func setUp() { super.setUp(); suite.removePersistentDomain(forName: domain); ShotScribeDefaults.suiteOverride = suite }
    override func tearDown() {
        ShotScribeDefaults.suiteOverride = nil
        suite.removePersistentDomain(forName: domain)
        super.tearDown()
    }

    /// The migration: an install from before the setting existed has stored
    /// nothing, and must come up exactly as it always did — in both places.
    func testAnInstallThatStoredNothingIsInBothPlaces() {
        XCTAssertNil(suite.object(forKey: ShotScribeDefaults.showInDockKey))
        XCTAssertEqual(ShotScribeDefaults.presence(), .both)
    }

    /// One key stored, the other never written: the missing one is still on.
    func testAHalfStoredSettingKeepsTheOtherOn() {
        suite.set(false, forKey: ShotScribeDefaults.showInDockKey)
        let p = ShotScribeDefaults.presence()
        XCTAssertFalse(p.dock)
        XCTAssertTrue(p.menuBar)
    }

    func testAChoiceIsKept() {
        ShotScribeDefaults.setPresence(Presence.both.setting(.dock, false))
        XCTAssertEqual(ShotScribeDefaults.presence(), Presence(dock: false, menuBar: true))
        ShotScribeDefaults.setPresence(Presence.both.setting(.menuBar, false))
        XCTAssertEqual(ShotScribeDefaults.presence(), Presence(dock: true, menuBar: false))
    }

    /// Never neither: the last one on cannot be switched off, whichever it is.
    func testTheLastOneOnCannotBeTurnedOff() {
        let trayOnly = Presence.both.setting(.dock, false)
        XCTAssertFalse(trayOnly.canTurnOff(.menuBar))
        XCTAssertEqual(trayOnly.setting(.menuBar, false), trayOnly, "refused, not half-applied")
        let dockOnly = Presence.both.setting(.menuBar, false)
        XCTAssertFalse(dockOnly.canTurnOff(.dock))
        XCTAssertEqual(dockOnly.setting(.dock, false), dockOnly)
        XCTAssertTrue(Presence.both.canTurnOff(.dock))
        XCTAssertTrue(Presence.both.canTurnOff(.menuBar))
        XCTAssertFalse(trayOnly.canTurnOff(.dock), "what is already off is not there to turn off")
        XCTAssertEqual(trayOnly.setting(.dock, true), .both, "and turning one back on is always allowed")
    }

    /// Defaults edited by hand into the impossible state read as the default.
    func testBothOffInStorageReadsAsBothOn() {
        suite.set(false, forKey: ShotScribeDefaults.showInDockKey)
        suite.set(false, forKey: ShotScribeDefaults.showInMenuBarKey)
        XCTAssertEqual(ShotScribeDefaults.presence(), .both)
        XCTAssertEqual(Presence(dock: false, menuBar: false), .both)
    }
}
