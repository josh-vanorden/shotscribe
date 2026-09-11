import XCTest
@testable import ShotScribeCore

final class NamingTests: XCTestCase {
    func testOnlyDefaultCaptureNamesLookRaw() {
        XCTAssertTrue(Naming.looksLikeDefaultCaptureName("Screenshot 2026-08-11 at 3.41.07 PM.png"))
        XCTAssertTrue(Naming.looksLikeDefaultCaptureName("Screen Shot 2019-01-02 at 1.00.00 PM.png"))
        XCTAssertFalse(Naming.looksLikeDefaultCaptureName("Quarterly Review.png"))
        XCTAssertFalse(Naming.looksLikeDefaultCaptureName("IMG_2043.png"))
    }

    func testSanitizeStripsIllegalCharsAndCollapsesSpace() {
        XCTAssertEqual(Naming.sanitize("AWS/Billing:  Console"), "AWS Billing Console")
        XCTAssertEqual(Naming.sanitize("  padded  "), "padded")
    }

    func testSanitizeCapsAtSixtyChars() {
        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(Naming.sanitize(long).count, 60)
    }

    func testFilenameIsDateFirstAndSortable() {
        // 2026-08-11 15:41 local — build the date explicitly (no Date.now).
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 11; comps.hour = 15; comps.minute = 41
        let date = Calendar.current.date(from: comps)!
        let name = Naming.filename(label: "AWS Billing Console", capturedAt: date, ext: "png")
        XCTAssertEqual(name, "2026-08-11 1541 AWS Billing Console.png")
    }

    func testFilenameNilWhenLabelEmpty() {
        XCTAssertNil(Naming.filename(label: "   ", capturedAt: Date(timeIntervalSince1970: 0), ext: "png"))
    }

    func testUniqueNameSuffixesOnCollision() {
        let existing: Set<String> = ["shot.png", "shot (2).png"]
        let unique = Naming.uniqueName("shot.png") { existing.contains($0) }
        XCTAssertEqual(unique, "shot (3).png")
    }

    func testUniqueNameLeavesFreeNameAlone() {
        let unique = Naming.uniqueName("fresh.png") { _ in false }
        XCTAssertEqual(unique, "fresh.png")
    }
}

final class LabelCleanerTests: XCTestCase {
    func testFirstLineOnly() {
        XCTAssertEqual(LabelCleaner.clean("Terminal Output\nignored second line"), "Terminal Output")
    }

    func testDropsEchoedPrefixAndQuotes() {
        XCTAssertEqual(LabelCleaner.clean("Label: \"Slack Thread\""), "Slack Thread")
    }

    func testCapsAtThreeWords() {
        XCTAssertEqual(LabelCleaner.clean("One Two Three Four Five"), "One Two Three")
    }

    func testEmptyBecomesScreenshot() {
        XCTAssertEqual(LabelCleaner.clean("   "), "Screenshot")
        XCTAssertEqual(LabelCleaner.clean("\"\""), "Screenshot")
    }
}

final class KeywordTitlerTests: XCTestCase {
    func testPicksSalientWordsAndSkipsStopwords() async throws {
        let titler = KeywordTitler()
        let ocr = "AWS Billing Console — the billing dashboard for your AWS account billing"
        let title = try await titler.title(forOCRText: ocr)
        // "billing" is most frequent; stopwords ("the", "for", "your") dropped.
        XCTAssertTrue(title.lowercased().contains("billing"), "got: \(title)")
        XCTAssertLessThanOrEqual(title.split(separator: " ").count, 3)
    }

    func testTinyTextIsGenericScreenshot() async throws {
        let title = try await KeywordTitler().title(forOCRText: "ok")
        XCTAssertEqual(title, "Screenshot")
    }
}
