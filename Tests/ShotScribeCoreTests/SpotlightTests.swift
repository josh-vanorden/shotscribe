import XCTest
@testable import ShotScribeCore

/// The words of a shot as Spotlight keywords: distilled, written as metadata
/// the file carries, off unless switched on.
final class SpotlightTests: XCTestCase {
    private let domain = "com.joshvanorden.shotscribe.tests.spotlight"
    private var suite: UserDefaults { UserDefaults(suiteName: domain)! }
    private var dir: URL!

    override func setUp() {
        super.setUp()
        suite.removePersistentDomain(forName: domain)
        ShotScribeDefaults.suiteOverride = suite
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("spotlight-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        ShotScribeDefaults.suiteOverride = nil
        suite.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testTheListIsTitleThenTagsThenDistinctSignificantWords() {
        let words = Spotlight.keywords(
            title: "Company Org Chart", tags: ["diagram", "browser"],
            text: "Matt Blumberg Chief Executive Officer · the Chief Operating Officer and a Director of Accounting, 2026 chart")
        XCTAssertEqual(Array(words.prefix(5)), ["company", "org", "chart", "diagram", "browser"], "title and tags lead")
        XCTAssertTrue(words.contains("accounting") && words.contains("officer"))
        XCTAssertFalse(words.contains("the") || words.contains("and") || words.contains("of"), "stopwords and two-letter words are out")
        XCTAssertEqual(words.filter { $0 == "chief" }.count, 1, "each word once")
        XCTAssertFalse(words.contains("2026"), "a bare number says nothing")
    }

    func testTheListIsCapped() {
        let text = (1...200).map { "word\($0)" }.joined(separator: " ")
        XCTAssertEqual(Spotlight.keywords(title: "", tags: [], text: text, limit: 25).count, 25)
    }

    func testKeywordsAreWrittenAsMetadataTheFileCarriesAndComeOffAgain() throws {
        let url = dir.appendingPathComponent("shot.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        XCTAssertEqual(Spotlight.read(url), [])
        XCTAssertTrue(Spotlight.write(["org chart", "accounting"], to: url))
        XCTAssertEqual(Spotlight.read(url), ["org chart", "accounting"])
        // What Spotlight reads: a binary plist under the metadata attribute.
        let raw = try XCTUnwrap(Xattr.read(Spotlight.attribute, at: url.path))
        XCTAssertEqual(try PropertyListSerialization.propertyList(from: raw, format: nil) as? [String], ["org chart", "accounting"])
        Spotlight.remove(from: url)
        XCTAssertEqual(Spotlight.read(url), [])
        XCTAssertFalse(Spotlight.write([], to: url), "nothing to write is not written")
    }

    /// Off by default — the words travel with the file — and a rename writes
    /// them only when the switch is on.
    func testARenameWritesKeywordsOnlyWhenSwitchedOn() async throws {
        XCTAssertFalse(ShotScribeDefaults.spotlightKeywords())
        let renamer = Renamer(titler: KeywordTitler(), template: .default, vocabulary: ["docs"])
        for on in [false, true] {
            ShotScribeDefaults.setSpotlightKeywords(on)
            let raw = dir.appendingPathComponent("Screenshot 2026-09-22 at 9.30.\(on ? 17 : 16) AM.png")
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: raw)
            let outcome = try await renamer.rename(fileAt: raw, label: "Account Settings", tags: ["docs"],
                                                   text: "Account settings for the billing team")
            guard case .renamed(_, let target) = outcome else { return XCTFail("\(outcome)") }
            let words = Spotlight.read(target)
            if on {
                XCTAssertEqual(Array(words.prefix(3)), ["account", "settings", "docs"], "title, then the tag, then the text: \(words)")
                XCTAssertTrue(words.contains("billing"))
            } else {
                XCTAssertEqual(words, [], "off: the file carries nothing")
            }
        }
    }
}
