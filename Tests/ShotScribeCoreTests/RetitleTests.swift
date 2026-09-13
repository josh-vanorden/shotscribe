import XCTest
@testable import ShotScribeCore

/// The title edited in the landing zone: the stamp stays as spelled, only the
/// words change, and a person's words are kept whole.
final class RetitleTests: XCTestCase {

    func testTheStampStaysAndOnlyTheWordsChange() {
        XCTAssertEqual(Naming.retitled("2026-09-11 2244 Screenshots Name Folder", to: "Name Template Pane"),
                       "2026-09-11 2244 Name Template Pane")
        XCTAssertEqual(Naming.retitled("2026-09-11_2244_old_title", to: "New Words", style: .snake),
                       "2026-09-11_2244_new_words", "the template's joining style applies")
        XCTAssertEqual(Naming.retitled("2026-09-11 2244 Old", to: "Six words of title are kept whole"),
                       "2026-09-11 2244 Six words of title are kept whole", "no word cap on a title a person typed")
    }

    func testANameWithoutAStampIsTheTitle() {
        XCTAssertEqual(Naming.retitled("Untitled", to: "Billing Console"), "Billing Console")
    }

    func testAnEmptyOrIllegalTitleIsCleanedOrRefused() {
        XCTAssertNil(Naming.retitled("2026-09-11 2244 Old", to: "   "))
        XCTAssertEqual(Naming.retitled("2026-09-11 2244 Old", to: "a/b:c"), "2026-09-11 2244 a b c")
    }
}
