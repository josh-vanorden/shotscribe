import XCTest
@testable import ShotScribeCore

/// Titles judged against the names that were kept. No fixture set: a folder
/// of renamed captures is the set, and the names are the answers.
final class EvalsTests: XCTestCase {

    private func aCase(_ title: String, tags: [String] = []) -> Evals.Case {
        Evals.Case(url: URL(fileURLWithPath: "/tmp/2026-08-11 1541 \(title).png"),
                   expectedTitle: title, expectedTags: tags)
    }

    func testTheSameTitleIsExactWhateverItsCaseOrJoining() {
        let s = Evals.score(Labelling(title: "aws-billing-console"), against: aCase("AWS Billing Console"))
        XCTAssertTrue(s.exact)
        XCTAssertEqual(s.recall, 1)
    }

    func testRecallIsTheShareOfExpectedWordsThatCameBack() {
        let partial = Evals.score(Labelling(title: "AWS Billing"), against: aCase("AWS Billing Console"))
        XCTAssertFalse(partial.exact)
        XCTAssertEqual(partial.recall, 2.0 / 3.0, accuracy: 0.001)
        let longer = Evals.score(Labelling(title: "AWS Billing Console Page"), against: aCase("AWS Billing Console"))
        XCTAssertFalse(longer.exact, "extra words are not the same title")
        XCTAssertEqual(longer.recall, 1, "but nothing expected was missed")
        let miss = Evals.score(Labelling(title: "Screenshot"), against: aCase("AWS Billing Console"))
        XCTAssertEqual(miss.recall, 0)
    }

    func testTagsScorePrecisionAndRecallSeparately() {
        let s = Evals.score(Labelling(title: "x", tags: ["dashboard", "code"]),
                            against: aCase("x", tags: ["dashboard", "browser"]))
        XCTAssertEqual(try XCTUnwrap(s.tagPrecision), 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.tagRecall), 0.5, accuracy: 0.001)
        let nothing = Evals.score(Labelling(title: "x"), against: aCase("x"))
        XCTAssertNil(nothing.tagPrecision, "nothing given, nothing to be precise about")
        XCTAssertNil(nothing.tagRecall, "nothing expected, nothing to recall")
    }

    func testTheSummaryAveragesWhatWasJudged() {
        let scores = [
            Evals.score(Labelling(title: "AWS Billing Console"), against: aCase("AWS Billing Console")),
            Evals.score(Labelling(title: "Slack"), against: aCase("Slack Thread")),
        ]
        let sum = Evals.summarize(scores)
        XCTAssertEqual(sum.count, 2)
        XCTAssertEqual(sum.exactRate, 0.5, accuracy: 0.001)
        XCTAssertEqual(sum.meanRecall, 0.75, accuracy: 0.001)
        XCTAssertNil(sum.tagPrecision)
    }

    /// The folder is the set: named captures become cases with the stamp
    /// stripped and the file's tags attached; a raw capture is not a case.
    func testAFolderOfNamedCapturesIsTheEvalSet() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("evals-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let named = dir.appendingPathComponent("2026-08-11 1541 AWS Billing Console.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: named)
        Tagging.add(["dashboard"], to: named)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: dir.appendingPathComponent("Screenshot 2026-08-11 at 3.41.07 PM.png"))
        try Data([0]).write(to: dir.appendingPathComponent("notes.txt"))

        let cases = Evals.cases(in: dir)
        XCTAssertEqual(cases.count, 1, "got \(cases.map(\.url.lastPathComponent))")
        XCTAssertEqual(cases.first?.expectedTitle, "AWS Billing Console")
        XCTAssertEqual(cases.first?.expectedTags, ["dashboard"])
    }
}
