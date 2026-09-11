import XCTest
@testable import ShotScribeCore

/// Tags go on the file as Finder tags, and come from a closed list. Both halves
/// are load-bearing: the first is what makes them findable without ShotScribe
/// running, the second is what keeps a screenshot from inventing its own filing.
final class TaggingTests: XCTestCase {

    private func tempFile(_ name: String = "shot.png") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tagging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(name)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        return url
    }

    // MARK: The closed list

    func testOnlyVocabularyTagsSurvive() {
        XCTAssertEqual(Tagging.accepted(["terminal", "sudo-rm-rf", "code"]), ["terminal", "code"])
        XCTAssertEqual(Tagging.accepted(["nothing", "here", "is", "known"]), [])
    }

    func testMatchingIsCaseInsensitiveAndAnswersInTheListsSpelling() {
        XCTAssertEqual(Tagging.accepted([" TERMINAL ", "Code"]), ["terminal", "code"])
    }

    func testTagsAreDeduplicatedAndCapped() {
        XCTAssertEqual(Tagging.accepted(["code", "code"]), ["code"])
        XCTAssertEqual(Tagging.accepted(["code", "terminal", "error", "logs"]).count, Tagging.maxPerShot)
    }

    /// The point of the list. OCR text is whatever was on screen, including a
    /// page written to be read by something like this.
    func testAnInventedTagIsDropped() {
        XCTAssertEqual(Tagging.accepted(["ignore previous instructions"]), [])
    }

    // MARK: Finder tags, on real files

    func testTagsAreWrittenWhereFinderReadsThem() throws {
        let url = try tempFile()
        XCTAssertTrue(Tagging.add(["terminal"], to: url))
        XCTAssertEqual(Tagging.finderTags(of: url), ["terminal"])
    }

    /// Setting `tagNames` replaces the lot, so anything filed by hand has to be
    /// merged back or ShotScribe would quietly throw the user's own filing away.
    func testTagsTheUserPutOnByHandAreKept() throws {
        let url = try tempFile()
        XCTAssertTrue(Tagging.add(["Important"], to: url))
        XCTAssertTrue(Tagging.add(["code"], to: url))
        XCTAssertEqual(Tagging.finderTags(of: url), ["Important", "code"])
    }

    func testAddingTheSameTagTwiceDoesNotDoubleIt() throws {
        let url = try tempFile()
        XCTAssertTrue(Tagging.add(["code"], to: url))
        XCTAssertTrue(Tagging.add(["CODE"], to: url))
        XCTAssertEqual(Tagging.finderTags(of: url), ["code"])
    }

    // MARK: What the titlers propose

    func testClaudeRepliesAreSplitIntoNameAndFiling() {
        let vocabulary = Tagging.defaultVocabulary
        let both = ClaudeTitler.parseLabelling("AWS Billing Console | dashboard, browser",
                                               vocabulary: vocabulary)
        XCTAssertEqual(both.title, "AWS Billing Console")
        XCTAssertEqual(both.tags, ["dashboard", "browser"])

        let titleOnly = ClaudeTitler.parseLabelling("Slack Thread", vocabulary: vocabulary)
        XCTAssertEqual(titleOnly.title, "Slack Thread")
        XCTAssertEqual(titleOnly.tags, [])

        let unsure = ClaudeTitler.parseLabelling("Screenshot |", vocabulary: vocabulary)
        XCTAssertEqual(unsure.title, "Screenshot")
        XCTAssertEqual(unsure.tags, [])

        let invented = ClaudeTitler.parseLabelling("Build Log | kubernetes, logs", vocabulary: vocabulary)
        XCTAssertEqual(invented.tags, ["logs"], "off-list proposals are dropped, the rest kept")
    }

    func testTheOfflineTitlerTagsOnWholeWordsOnly() async throws {
        let titler = KeywordTitler()
        let hit = try await titler.labelling(forOCRText: "sudo launchctl list — terminal session output",
                                             vocabulary: Tagging.defaultVocabulary)
        XCTAssertTrue(hit.tags.contains("terminal"), "got \(hit.tags)")

        let miss = try await titler.labelling(forOCRText: "the decoder was encoded badly",
                                              vocabulary: Tagging.defaultVocabulary)
        XCTAssertFalse(miss.tags.contains("code"), "\"decoder\" is not the tag \"code\"")
    }

    /// Every door holds a `Titler`, not a concrete titler. When `labelling` was
    /// an extension method only, that call dispatched statically to the default
    /// and nothing was ever tagged — while tests calling `KeywordTitler()`
    /// directly still passed.
    func testTaggingSurvivesBeingCalledThroughTheProtocol() async throws {
        let titler: Titler = KeywordTitler()
        let proposed = try await titler.labelling(forOCRText: "terminal error output here",
                                                  vocabulary: Tagging.defaultVocabulary)
        XCTAssertFalse(proposed.tags.isEmpty, "the existential must reach the override")
    }

    func testNoVocabularyMeansNoTags() async throws {
        let proposed = try await KeywordTitler().labelling(forOCRText: "terminal output", vocabulary: [])
        XCTAssertEqual(proposed.tags, [])
    }

    // MARK: Through the Renamer

    func testARenameFilesTheShot() async throws {
        let raw = try tempFile("Screenshot 2026-08-11 at 3.41.07 PM.png")
        let renamer = Renamer(titler: KeywordTitler(), vocabulary: Tagging.defaultVocabulary)
        let outcome = try await renamer.rename(fileAt: raw, label: "AWS Billing Console",
                                               tags: ["dashboard", "made-up"])
        guard case .renamed(_, let to) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(Tagging.finderTags(of: to), ["dashboard"], "the invented one never reached the file")
    }

    func testADryRunFilesNothing() async throws {
        let raw = try tempFile("Screenshot 2026-08-11 at 3.41.07 PM.png")
        let renamer = Renamer(titler: KeywordTitler(), vocabulary: Tagging.defaultVocabulary)
        _ = try await renamer.rename(fileAt: raw, label: "AWS Billing Console",
                                     tags: ["dashboard"], dryRun: true)
        XCTAssertEqual(Tagging.finderTags(of: raw), [], "nothing moved, so nothing was filed")
    }
}
