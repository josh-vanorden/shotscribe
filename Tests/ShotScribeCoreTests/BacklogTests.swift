import XCTest
import AppKit
@testable import ShotScribeCore

/// The backlog: raw captures that landed while nothing was watching. The rules
/// that matter are about what it must *not* touch — a file the operator named,
/// a file that is not a capture, a folder they made — and that proposing a
/// name moves nothing.
final class BacklogTests: XCTestCase {
    private var dir: URL!
    /// Kept apart from `dir` (the captures folder) so a test asserting on
    /// `dir`'s exact contents is never tripped up by `InFlight`'s own file.
    private var inflightDir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("backlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        inflightDir = FileManager.default.temporaryDirectory.appendingPathComponent("backlog-inflight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: inflightDir, withIntermediateDirectories: true)
        InFlight.storeOverride = inflightDir.appendingPathComponent("inflight.json")
    }

    override func tearDownWithError() throws {
        InFlight.storeOverride = nil
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: inflightDir)
    }

    /// A real PNG with words on it, drawn at 2x like a capture, dated as asked.
    @discardableResult
    private func capture(_ name: String, saying text: String = "Quarterly Revenue Dashboard",
                         taken: Date) throws -> URL {
        let size = NSSize(width: 900, height: 500)
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 1000,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(at: NSPoint(x: 60, y: 240),
            withAttributes: [.font: NSFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let url = dir.appendingPathComponent(name)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        try FileManager.default.setAttributes([.creationDate: taken, .modificationDate: taken],
                                              ofItemAtPath: url.path)
        return url
    }

    private func day(_ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: d, hour: 11, minute: 40))!
    }

    func testOnlyRawCapturesAreInTheBacklogOldestFirst() throws {
        try capture("Screenshot 2026-08-09 at 11.40.00 AM.png", taken: day(9))
        try capture("Screenshot 2026-08-06 at 11.40.00 AM.png", taken: day(6))
        try capture("2026-08-07 1140 Already Named.png", taken: day(7))      // ShotScribe's own output
        try capture("my diagram.png", taken: day(8))                         // the operator named it
        try Data("not an image".utf8).write(to: dir.appendingPathComponent("Screenshot notes.txt"))
        let sub = dir.appendingPathComponent("Screenshot 2026-08-10 at 11.40.00 AM")   // a folder, not a file
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let pending = Backlog.pending(in: dir).map(\.lastPathComponent)
        XCTAssertEqual(pending, ["Screenshot 2026-08-06 at 11.40.00 AM.png",
                                 "Screenshot 2026-08-09 at 11.40.00 AM.png"],
                       "raw captures only, in the order they were taken")
    }

    func testAnEmptyFolderHasNoBacklog() {
        XCTAssertEqual(Backlog.pending(in: dir), [])
    }

    func testAFolderThatDoesNotExistHasNoBacklog() {
        XCTAssertEqual(Backlog.pending(in: dir.appendingPathComponent("gone")), [])
    }

    /// Reading a capture and naming it must leave the file exactly where it was.
    func testProposingANameMovesNothing() async throws {
        let raw = try capture("Screenshot 2026-08-06 at 11.40.00 AM.png", taken: day(6))
        let proposal = await Backlog.propose(raw, renamer: Renamer(titler: KeywordTitler()),
                                             titler: KeywordTitler(), vocabulary: [])
        let p = try XCTUnwrap(proposal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path), "still under its raw name")
        XCTAssertEqual(p.url, raw)
        XCTAssertTrue(p.name.hasPrefix("2026-08-06 1140 "),
                      "named for the day it was taken, not today: \(p.name)")
        XCTAssertFalse(p.name.hasPrefix("Screenshot"), "and no longer a raw name")
    }

    /// The proposal carries the titler's answer, so applying it does not ask the
    /// model again — and applying it produces the name that was shown.
    func testApplyingAProposalGivesTheNameThatWasShown() async throws {
        let raw = try capture("Screenshot 2026-08-06 at 11.40.00 AM.png", taken: day(6))
        let renamer = Renamer(titler: KeywordTitler())
        let proposal = await Backlog.propose(raw, renamer: renamer,
                                             titler: KeywordTitler(), vocabulary: [])
        let p = try XCTUnwrap(proposal)
        let outcome = try await renamer.rename(fileAt: raw, label: p.label, tags: p.tags)
        guard case .renamed(_, let to) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(to.lastPathComponent, p.name)
    }

    /// A file the operator named is never proposed, even if handed in directly.
    func testANamedFileIsNeverProposed() async throws {
        let named = try capture("my diagram.png", taken: day(6))
        let p = await Backlog.propose(named, renamer: Renamer(titler: KeywordTitler()),
                                      titler: KeywordTitler(), vocabulary: [])
        XCTAssertNil(p)
        XCTAssertTrue(FileManager.default.fileExists(atPath: named.path))
    }

    // MARK: - Retrying interrupted renames (p1b)

    /// Acceptance 1: a capture `InFlight` remembers as mid-rename — the trail
    /// `Renamer.rename` leaves when the app quits while the titler is still
    /// thinking (p1a) — is retried before the ordinary sweep, and ends up
    /// renamed exactly as a direct `Renamer.rename` call would leave it.
    func testACaptureWithAnInFlightRecordIsRetriedAndRenamed() async throws {
        let raw = try capture("Screenshot 2026-08-06 at 11.40.00 AM.png", taken: day(6))
        InFlight.begin(raw)   // the record a crash mid-rename would leave behind

        let outcomes = await Backlog.retryInFlight(in: dir, renamer: Renamer(titler: KeywordTitler()))

        guard case .renamed(let from, let to) = outcomes.first else {
            return XCTFail("expected the retry to rename the capture, got \(outcomes)")
        }
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(from, raw)
        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path), "no longer under its raw name")
        XCTAssertTrue(FileManager.default.fileExists(atPath: to.path), "renamed, not just moved aside")
        XCTAssertTrue(InFlight.records().isEmpty, "the record is cleared once the retry resolves it")
    }

    /// Acceptance 2, the subtle one: a record can outlive the rename it
    /// describes. The app can crash *after* `Renamer.rename` already moved
    /// the file to its new name but *before* the record naming the old path
    /// was cleared — so a record can point at a path with nothing left there,
    /// for a capture that is already correctly named elsewhere. "Already
    /// renamed" is read straight off disk (nothing exists at the recorded
    /// path any more), and that must resolve and clear the record, never
    /// rename the real file a second time.
    func testACaptureThatWasAlreadyRenamedIsNotRenamedTwice() async throws {
        let raw = try capture("Screenshot 2026-08-06 at 11.40.00 AM.png", taken: day(6))
        let renamer = Renamer(titler: KeywordTitler())
        let outcome = try await renamer.rename(fileAt: raw)
        guard case .renamed(_, let renamed) = outcome else {
            return XCTFail("setup: expected the capture to rename cleanly, got \(outcome)")
        }
        XCTAssertTrue(InFlight.records().isEmpty, "setup: a completed rename already clears its own record")

        // Simulate the crash: a record still names the original raw path,
        // even though the rename it was tracking already succeeded and the
        // file has since moved on to `renamed`.
        InFlight.begin(raw)

        let outcomes = await Backlog.retryInFlight(in: dir, renamer: renamer)

        XCTAssertTrue(outcomes.isEmpty, "nothing to retry — the file the record names is gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path), "the already-renamed file is untouched")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [renamed.lastPathComponent],
                       "still exactly the one file, under its one name — never renamed twice")
        XCTAssertTrue(InFlight.records().isEmpty, "the stale record is cleared, not left to accumulate")
    }
}
