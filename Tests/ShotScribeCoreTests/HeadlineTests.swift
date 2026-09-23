import XCTest
@testable import ShotScribeCore

/// The offline titler with the positions in hand: the headline is the title
/// when the picture has one, the keywords when it does not.
final class HeadlineTests: XCTestCase {

    /// A line as Vision reports it, from where it sits on the page: `top` and
    /// `height` in percent of the picture, top-left origin.
    private func line(_ text: String, top: Double, height: Double, left: Double = 5, width: Double = 40) -> OCR.TextLine {
        let h = height / 100, maxY = 1 - top / 100
        return OCR.TextLine(text: text, box: CGRect(x: left / 100, y: maxY - h, width: width / 100, height: h))
    }

    /// The shape of the numbered slides that were all titled from their keywords.
    private var slide: [OCR.TextLine] {
        [line("1", top: 4, height: 8, left: 4, width: 6),
         line("Harness Engineering", top: 5, height: 6, left: 12),
         line("Giving your agent a full, safe and observable stack.", top: 13, height: 2.4, left: 12, width: 60),
         line("User / App", top: 30, height: 1.6), line("Prompt, request or task", top: 33, height: 1.4),
         line("Agent", top: 30, height: 1.8, left: 40), line("Plans, calls tools, takes action", top: 33, height: 1.4, left: 40),
         line("Tools & Integrations", top: 30, height: 1.6, left: 70), line("APIs, databases, web, internal tools", top: 33, height: 1.4, left: 70),
         line("Retry & fallback logic", top: 70, height: 1.8), line("Handle failures and try alternative tools or approaches.", top: 73, height: 1.4, width: 50)]
    }

    func testTheBiggestTypeUpTopIsTheTitle() async throws {
        XCTAssertEqual(KeywordTitler.headline(in: slide), "Harness Engineering")
        let got = try await KeywordTitler().labelling(for: slide, vocabulary: [])
        XCTAssertEqual(got.title, "Harness Engineering")
    }

    func testABareNumberIsNotAHeadline() {
        // The slide's "1" is the tallest box on the page and not a title.
        XCTAssertNotEqual(KeywordTitler.headline(in: slide), "1")
    }

    func testOneSizeOfTextHasNoHeadline() async throws {
        let terminal = (0..<8).map { i in
            line("deploy step \(i) finished with warnings for service gateway", top: 5 + Double(i) * 4, height: 1.6, width: 70)
        }
        XCTAssertNil(KeywordTitler.headline(in: terminal))
        let got = try await KeywordTitler().labelling(for: terminal, vocabulary: [])
        XCTAssertNotEqual(got.title, LabelCleaner.generic, "the keywords still name it")
        XCTAssertTrue(got.title.localizedCaseInsensitiveContains("deploy") || got.title.localizedCaseInsensitiveContains("gateway"), got.title)
    }

    func testAHeadlineReadAsTwoBoxesIsJoinedLeftToRight() {
        let lines = [line("9", top: 4, height: 8, left: 4, width: 6),
                     line("Design", top: 5, height: 6, left: 48, width: 14),
                     line("Human-in-the-Loop", top: 5, height: 6, left: 12, width: 34),
                     line("Better decisions with human oversight.", top: 13, height: 2.4, left: 12, width: 50),
                     line("When to keep a human", top: 60, height: 1.8), line("Types of human oversight", top: 60, height: 1.8, left: 50)]
        XCTAssertEqual(KeywordTitler.headline(in: lines), "Human-in-the-Loop Design")
    }

    func testAHeadlineTooFarDownIsNotOne() {
        var lines = slide
        lines[1] = line("Harness Engineering", top: 75, height: 6, left: 12)
        XCTAssertNil(KeywordTitler.headline(in: lines))
    }

    func testAnAllCapsHeadlineIsTitleCasedAndAcronymsKept() {
        XCTAssertEqual(KeywordTitler.titleCased("SUSPICIOUS LOGIN ALERT"), "Suspicious Login Alert")
        XCTAssertEqual(KeywordTitler.titleCased("MDM CERT SWAP"), "MDM Cert Swap")
        XCTAssertEqual(KeywordTitler.titleCased("Observability & Tracing"), "Observability Tracing")
        XCTAssertEqual(KeywordTitler.titleCased("4 Tool Design"), "Tool Design", "a slide's number is the deck's")
        XCTAssertEqual(KeywordTitler.titleCased("Roadmap 2026"), "Roadmap 2026")
    }

    /// The lines-aware method is a protocol requirement, so the override is
    /// reached through the existential every door holds — an extension-only
    /// method would dispatch to the text default and the headline would
    /// never be read (the same trap as `labelling(forOCRText:)`, 2026-09-11).
    func testTheOverrideIsReachedThroughTheExistential() async throws {
        let titler: Titler = KeywordTitler()
        let got = try await titler.labelling(for: slide, vocabulary: ["diagram", "docs"])
        XCTAssertEqual(got.title, "Harness Engineering")
    }

    /// A slide's title up top is not a menu bar and not a title bar: the
    /// chrome stripper leaves it for the headline rule. This slide's title was
    /// read as the app "Human-in-the-Loop Design" and stripped (2026-09-23).
    func testAHeadingUpTopIsNotChrome() {
        let lines = [line("Human-in-the-Loop Design", top: 4.6, height: 5.1, left: 19.5, width: 77),
                     line("Better decisions with human oversight.", top: 10.3, height: 3.3, left: 19.9, width: 62.8),
                     line("When to keep a human", top: 72.6, height: 1.9, left: 14.9, width: 25.9),
                     line("Types of human oversight", top: 72.9, height: 1.9, left: 62.4, width: 30.1)]
        XCTAssertNil(Chrome.app(in: lines))
        XCTAssertEqual(Chrome.body(of: lines).count, lines.count)
        XCTAssertEqual(KeywordTitler.headline(in: Chrome.body(of: lines)), "Human-in-the-Loop Design")
        // A real menu bar still reads: the app's name starts at the left edge.
        let menu = [line("Terminal Shell Edit View Window Help", top: 1, height: 2.5, left: 2, width: 40),
                    line("deploy finished with warnings", top: 40, height: 4, left: 5, width: 50)]
        XCTAssertEqual(Chrome.app(in: menu), "Terminal")
        XCTAssertEqual(Chrome.body(of: menu).count, 1)
    }

    func testAnAmpersandIsTheWordAnd() {
        XCTAssertEqual(LabelCleaner.clean("Guardrails & Permissions"), "Guardrails and Permissions")
        XCTAssertEqual(LabelCleaner.clean("Guardrails And Permissions"), "Guardrails And Permissions")
        XCTAssertEqual(LabelCleaner.clean("Observability&Tracing"), "Observability and Tracing")
    }

    // MARK: - The prompt that keeps the model's answers the same

    func testThePromptTellsTheModelToUseTheScreensOwnWords() {
        for prompt in [TitlerPrompt.system, TitlerPrompt.system(taggedFrom: ["docs", "chat"])] {
            XCTAssertTrue(prompt.contains("words the screen uses for itself"), prompt)
            XCTAssertTrue(prompt.contains("Same screen, same label"), prompt)
            XCTAssertTrue(prompt.contains("max 3"), prompt)
        }
        XCTAssertTrue(TitlerPrompt.system(taggedFrom: ["docs", "chat"]).contains("docs, chat"))
    }
}
