import XCTest
@testable import ShotScribeCore

final class AppearanceTests: XCTestCase {
    private let domain = "com.joshvanorden.shotscribe.tests.appearance"
    private var suite: UserDefaults { UserDefaults(suiteName: domain)! }

    override func setUp() { super.setUp(); ShotScribeDefaults.suiteOverride = suite }
    override func tearDown() {
        ShotScribeDefaults.suiteOverride = nil
        suite.removePersistentDomain(forName: domain)
        super.tearDown()
    }

    /// The Mac's choice until told otherwise; a flip is kept; nonsense is the Mac's choice again.
    func testTheAppearanceFollowsTheMacUntilFlipped() {
        XCTAssertEqual(ShotScribeDefaults.appearance(), .system)
        ShotScribeDefaults.setAppearance(.dark)
        XCTAssertEqual(ShotScribeDefaults.appearance(), .dark)
        ShotScribeDefaults.setAppearance(.system)
        XCTAssertNil(suite.string(forKey: ShotScribeDefaults.appearanceKey), "following the Mac leaves nothing behind")
        suite.set("sepia", forKey: ShotScribeDefaults.appearanceKey)
        XCTAssertEqual(ShotScribeDefaults.appearance(), .system)
    }
}
