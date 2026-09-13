import XCTest
@testable import ShotScribeCore

final class KeepingTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_780_000_000)

    private func shot(_ name: String, minutes: Double, text: String = "", path: String? = nil) -> IndexedShot {
        IndexedShot(path: path ?? "/tmp/\(name).png", name: name,
                    captured: base.addingTimeInterval(minutes * 60), indexed: base, size: 1, text: text)
    }

    // MARK: Sessions

    func testConsecutiveCapturesWithinTheGapFoldIntoOneSession() {
        let shots = [shot("a", minutes: 0), shot("b", minutes: 2), shot("c", minutes: 4),
                     shot("d", minutes: 30), shot("e", minutes: 31)]
        let sessions = Sessions.collapse(shots, gapMinutes: 3)
        XCTAssertEqual(sessions.map(\.count), [3, 2])
        XCTAssertTrue(sessions[0].isBurst)
    }

    func testGapZeroFoldsNothing() {
        let shots = [shot("a", minutes: 0), shot("b", minutes: 1)]
        XCTAssertEqual(Sessions.collapse(shots, gapMinutes: 0).count, 2)
    }

    /// The gap is between *consecutive* shots, so a long burst stays one
    /// session even when its ends are far apart.
    func testTheGapIsBetweenNeighboursNotEnds() {
        let shots = (0..<10).map { shot("s\($0)", minutes: Double($0) * 2) }
        XCTAssertEqual(Sessions.collapse(shots, gapMinutes: 3).count, 1)
    }

    func testSessionsFollowTheInputDirection() {
        let asc = [shot("a", minutes: 0), shot("b", minutes: 1), shot("c", minutes: 60)]
        let newestFirst = Sessions.collapse(asc.reversed(), gapMinutes: 3)
        XCTAssertEqual(newestFirst.first?.shots.map(\.name), ["c"])
        XCTAssertEqual(newestFirst.last?.shots.map(\.name), ["a", "b"], "shots inside a session are chronological")
    }

    func testSessionTitleIsTheMostCommonStemWithTheDateStripped() {
        let shots = [shot("2026-08-11 1541 AWS Billing", minutes: 0),
                     shot("2026-08-11 1542 Slack Thread", minutes: 1),
                     shot("2026-08-11 1543 AWS Billing (2)", minutes: 2),
                     shot("2026-08-11 1544 AWS Billing", minutes: 3)]
        XCTAssertEqual(Sessions.collapse(shots, gapMinutes: 3).first?.title, "AWS Billing")
        XCTAssertEqual(Sessions.stem(of: "Quarterly Review"), "Quarterly Review", "no date prefix, name untouched")
    }

    /// A session title has to survive the operator's `NameTemplate`: the stamp
    /// comes off wherever it sits and however it is spelled.
    func testStemStripsTheStampUnderAnyTemplate() {
        XCTAssertEqual(Sessions.stem(of: "2026-08-11 1541 AWS Billing Console"), "AWS Billing Console")
        XCTAssertEqual(Sessions.stem(of: "20260811 1541 AWS Billing Console"), "AWS Billing Console")
        XCTAssertEqual(Sessions.stem(of: "2026-08-11_1541_aws-billing-console"), "aws-billing-console")
        XCTAssertEqual(Sessions.stem(of: "aws-billing-console 2026-08-11 1541"), "aws-billing-console")
        XCTAssertEqual(Sessions.stem(of: "2026-08-11 3.41 PM AWS Billing"), "AWS Billing")
        XCTAssertEqual(Sessions.stem(of: "2026-08-11 1541"), "2026-08-11 1541", "all stamp, nothing to strip to")
    }

    // MARK: Clean-up plan

    private let text = String(repeating: "error NXDOMAIN for host i-0a3f in eu-west-1 ", count: 3)

    func testDuplicatesKeepTheEarliestAndFlagTheRest() {
        let shots = [shot("late", minutes: 10, text: text), shot("first", minutes: 0, text: text),
                     shot("other", minutes: 5, text: "something else entirely, long enough to count too")]
        let plan = Cleanup.plan(shots, policy: KeepPolicy(flagDuplicates: true))
        XCTAssertEqual(plan.moves.map(\.shot.name), ["late"])
        XCTAssertEqual(plan.moves.first?.reason, .duplicate(of: "first"))
        XCTAssertEqual(plan.duplicates, 1)
    }

    func testWhitespaceAndCaseDoNotBreakADuplicate() {
        let a = shot("a", minutes: 0, text: text)
        let b = shot("b", minutes: 1, text: text.uppercased().replacingOccurrences(of: " ", with: "\n  "))
        XCTAssertEqual(Cleanup.plan([a, b], policy: KeepPolicy()).moves.count, 1)
    }

    /// Unknown is not none: an empty or thin OCR must never make two shots
    /// duplicates of each other.
    func testThinTextIsNeverADuplicate() {
        let shots = [shot("a", minutes: 0, text: ""), shot("b", minutes: 1, text: ""),
                     shot("c", minutes: 2, text: "ok"), shot("d", minutes: 3, text: "ok")]
        XCTAssertTrue(Cleanup.plan(shots, policy: KeepPolicy()).isEmpty)
    }

    func testOlderThanFlagsByAge() {
        let now = base.addingTimeInterval(100 * 86_400)
        let shots = [shot("old", minutes: 0), shot("new", minutes: 99 * 24 * 60)]
        let plan = Cleanup.plan(shots, policy: KeepPolicy(flagDuplicates: false, olderThanDays: 90), now: now)
        XCTAssertEqual(plan.moves.map(\.shot.name), ["old"])
        XCTAssertEqual(plan.stale, 1)
    }

    func testAShotIsFlaggedOnceAndDuplicateWins() {
        let now = base.addingTimeInterval(100 * 86_400)
        let shots = [shot("first", minutes: 0, text: text), shot("dup", minutes: 1, text: text)]
        let plan = Cleanup.plan(shots, policy: KeepPolicy(olderThanDays: 30), now: now)
        XCTAssertEqual(plan.moves.count, 2)
        XCTAssertEqual(plan.moves.first { $0.shot.name == "dup" }?.reason, .duplicate(of: "first"))
        XCTAssertEqual(plan.moves.first { $0.shot.name == "first" }?.reason, .olderThan(days: 30))
    }

    func testDefaultPolicyNeverAgesOut() {
        XCTAssertNil(KeepPolicy.default.olderThanDays)
        XCTAssertEqual(KeepPolicy.default.destination, .trash)
    }

    func testPolicyRoundTripsThroughJSON() throws {
        let p = KeepPolicy(sessionGapMinutes: 5, flagDuplicates: false, olderThanDays: 180,
                           destination: .archive(path: "/tmp/Archive"))
        let back = try JSONDecoder().decode(KeepPolicy.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        XCTAssertEqual(back.destination.label, "Archive")
    }

    // MARK: Applying, and undo — real files in a temp folder

    private func tempFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotscribe-keep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func useScratchIndex() throws {
        ShotIndex.storeOverride = try tempFolder().appendingPathComponent("index.json")
        addTeardownBlock { ShotIndex.storeOverride = nil }
    }

    func testArchiveMovesFilesIntoTheFolderWithUniqueNamesAndForgetsThem() throws {
        try useScratchIndex()
        let dir = try tempFolder()
        let archive = dir.appendingPathComponent("Archive")
        let a = dir.appendingPathComponent("one.png"), b = dir.appendingPathComponent("two.png")
        try Data("a".utf8).write(to: a); try Data("b".utf8).write(to: b)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data("taken".utf8).write(to: archive.appendingPathComponent("one.png"))   // collision
        var store = ShotIndex.Store()
        for u in [a, b] { store.shots[u.path] = shot(u.lastPathComponent, minutes: 0, path: u.path) }
        ShotIndex.save(store)

        let plan = Cleanup.Plan(moves: [.init(shot: store.shots[a.path]!, reason: .olderThan(days: 1)),
                                        .init(shot: store.shots[b.path]!, reason: .olderThan(days: 1))],
                                destination: .archive(path: archive.path))
        let out = Cleanup.apply(plan)

        XCTAssertEqual(out.moved.count, 2); XCTAssertTrue(out.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.appendingPathComponent("one (2).png").path),
                      "the taken name gets a suffix rather than overwriting")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.appendingPathComponent("two.png").path))
        XCTAssertTrue(ShotIndex.load().shots.isEmpty, "moved shots leave the index")
    }

    /// The Keep tab's third choice: gone outright. The user picks it; the
    /// default stays the Trash.
    func testTheDeleteDestinationRemovesTheFileOutright() throws {
        try useScratchIndex()
        let dir = try tempFolder()
        let a = dir.appendingPathComponent("gone.png")
        try Data("a".utf8).write(to: a)
        var store = ShotIndex.Store()
        store.shots[a.path] = shot("gone", minutes: 0, path: a.path)
        ShotIndex.save(store)
        XCTAssertEqual(KeepPolicy.default.destination, .trash, "never outright by default")

        let out = Cleanup.apply(Cleanup.Plan(moves: [.init(shot: store.shots[a.path]!, reason: .olderThan(days: 1))],
                                             destination: .delete))
        XCTAssertEqual(out.moved, [a.path]); XCTAssertTrue(out.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(ShotIndex.load().shots.isEmpty)
        XCTAssertEqual(KeepPolicy.Destination.delete.label, "nowhere — deleted for good")
        let round = try JSONDecoder().decode(KeepPolicy.self, from: JSONEncoder().encode(
            KeepPolicy(destination: .delete)))
        XCTAssertEqual(round.destination, .delete, "the choice survives the settings round trip")
    }

    func testAFailedMoveIsReportedAndStaysIndexed() throws {
        try useScratchIndex()
        let ghost = shot("ghost", minutes: 0, path: "/nonexistent/ghost.png")
        ShotIndex.save({ var s = ShotIndex.Store(); s.shots[ghost.path] = ghost; return s }())
        let out = Cleanup.apply(Cleanup.Plan(moves: [.init(shot: ghost, reason: .olderThan(days: 1))],
                                             destination: .archive(path: "/tmp/never")))
        XCTAssertTrue(out.moved.isEmpty)
        XCTAssertEqual(out.failures.count, 1)
        XCTAssertEqual(ShotIndex.load().shots.count, 1)
    }

    func testUndoPutsTheOriginalNameBack() async throws {
        let dir = try tempFolder()
        let raw = dir.appendingPathComponent("Screenshot 2026-08-11 at 3.41.07 PM.png")
        try Data("png".utf8).write(to: raw)
        let outcome = try await Renamer(titler: KeywordTitler()).rename(fileAt: raw, label: "Test Shot")
        guard case .renamed(_, let renamed) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path))

        let target = Renamer.restoredURL(for: renamed, original: raw.lastPathComponent)
        XCTAssertEqual(target, raw, "the original name is free, so it comes straight back")
        try Renamer.restore(fileAt: renamed, to: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testUndoSuffixesWhenTheOriginalNameIsTakenMeanwhile() throws {
        let dir = try tempFolder()
        let renamed = dir.appendingPathComponent("2026-08-11 1541 Test.png")
        try Data("x".utf8).write(to: renamed)
        try Data("y".utf8).write(to: dir.appendingPathComponent("Screenshot A.png"))
        let target = Renamer.restoredURL(for: renamed, original: "Screenshot A.png")
        XCTAssertEqual(target.lastPathComponent, "Screenshot A (2).png")
    }

    func testTheIndexKeepsTheOriginalNameAcrossAResweep() throws {
        try useScratchIndex()
        let dir = try tempFolder()
        let file = dir.appendingPathComponent("2026-08-11 1541 Test.png")
        try Data("png".utf8).write(to: file)
        ShotIndex.record(file, original: "Screenshot 2026-08-11 at 3.41.07 PM.png")
        // The index keys by what the filesystem calls the file — under a temp
        // folder that is `/private/var/…`, not the `/var/…` this test typed.
        let key = ShotIndex.canonicalPath(file)
        XCTAssertEqual(ShotIndex.load().shots[key]?.original, "Screenshot 2026-08-11 at 3.41.07 PM.png")

        try Data("png-but-bigger".utf8).write(to: file)     // size changed → re-read on sweep
        ShotIndex.reindex(folder: dir)
        XCTAssertEqual(ShotIndex.load().shots.count, 1, "one entry, not a canonical twin")
        XCTAssertEqual(ShotIndex.load().shots[key]?.original, "Screenshot 2026-08-11 at 3.41.07 PM.png",
                       "a re-read of the text must not drop the way back")
    }
}
