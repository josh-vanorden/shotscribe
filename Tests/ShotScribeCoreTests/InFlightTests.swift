import XCTest
import AppKit
@testable import ShotScribeCore

/// The durable record `Renamer.rename` leaves while a rename is in progress,
/// so a capture interrupted mid-rename — the app quits while the titler is
/// still thinking — isn't lost with no memory anything was attempted.
///
/// The interruption itself is simulated rather than actually killing a
/// process: `WitnessTitler` sits where the titler normally would, right in
/// the slow step a real crash would land inside, and snapshots what
/// `InFlight` shows *on disk* at that instant — decoded straight from bytes,
/// never through `InFlight`'s own reader, so the snapshot proves durability
/// rather than assuming it.
final class InFlightTests: XCTestCase {
    private var dir: URL!
    private var storeURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("inflight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("inflight.json")
        InFlight.storeOverride = storeURL
    }

    override func tearDownWithError() throws {
        InFlight.storeOverride = nil
        try? FileManager.default.removeItem(at: dir)
    }

    /// A real PNG with words on it, under a raw macOS capture name — the same
    /// fixture shape `BacklogTests` uses — so `Renamer.rename` actually
    /// attempts it rather than skipping it as user-named.
    @discardableResult
    private func capture(_ name: String = "Screenshot 2026-08-11 at 3.41.07 PM.png") throws -> URL {
        let size = NSSize(width: 400, height: 200)
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 400,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        ("Quarterly Revenue Dashboard" as NSString).draw(at: NSPoint(x: 20, y: 80),
            withAttributes: [.font: NSFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let url = dir.appendingPathComponent(name)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    /// What the witness saw the instant the titler was called: the record,
    /// decoded fresh off disk — not something `InFlight` merely reported from
    /// memory, since a hand-rolled decode is the only way to be sure.
    private actor Witness {
        private(set) var record: InFlight.Record?

        /// Reads `storeURL` fresh off disk with a brand-new decoder — never
        /// through `InFlight`'s own call — so a hit here proves the bytes are
        /// really there, the way a restarted process would have to find them,
        /// not that this process merely remembers writing them.
        func capture(path: String, storeURL: URL) {
            guard let data = try? Data(contentsOf: storeURL) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            record = (try? decoder.decode(InFlight.Store.self, from: data))?.records[path]
        }
    }

    /// A titler that watches for the one moment that matters — mid-flight,
    /// after `Renamer.rename` has committed to the attempt but before it has
    /// moved anything — the exact window a real interruption would land in.
    private struct WitnessTitler: Titler {
        let witness: Witness
        let path: String
        let storeURL: URL
        func title(forOCRText text: String) async throws -> String { "Screenshot" }
        func labelling(forOCRText text: String, vocabulary: [String]) async throws -> Labelling {
            await witness.capture(path: path, storeURL: storeURL)
            return Labelling(title: "Quarterly Revenue Dashboard")
        }
    }

    // MARK: - Acceptance criterion 1

    /// A rename interrupted before completion leaves a record naming that
    /// capture, readable after a process restart.
    func testAnInterruptedRenameLeavesARecordNamingTheCapture() async throws {
        let raw = try capture()
        let witness = Witness()
        let renamer = Renamer(titler: WitnessTitler(witness: witness, path: raw.path, storeURL: storeURL))
        let before = Date()

        _ = try await renamer.rename(fileAt: raw)

        // Decoded by `Witness` from a brand-new read of `storeURL`, with no
        // access to `InFlight`'s own in-memory state (there is none) — the
        // stand-in for a fresh process reading what a dead one wrote.
        let seen = await witness.record
        let record = try XCTUnwrap(seen, "no record existed while the titler was still working — " +
                                   "an interruption right there would have lost the capture")
        XCTAssertEqual(record.path, raw.path, "the record must name the capture that was interrupted")
        XCTAssertGreaterThanOrEqual(record.startedAt, before.addingTimeInterval(-1))
    }

    // MARK: - Acceptance criterion 2

    /// A rename that completes leaves no record. Checked against the same
    /// mid-flight witness as above first, so this test fails the way
    /// criterion 1's does when nothing is wired up, rather than passing by
    /// accident because nothing was ever written to begin with.
    func testACompletedRenameLeavesNoRecord() async throws {
        let raw = try capture()
        let witness = Witness()
        let renamer = Renamer(titler: WitnessTitler(witness: witness, path: raw.path, storeURL: storeURL))

        let outcome = try await renamer.rename(fileAt: raw)

        guard case .renamed(let from, let to) = outcome else {
            return XCTFail("expected a completed rename, got \(outcome)")
        }
        XCTAssertEqual(from, raw)
        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path), "the raw name is gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: to.path))

        let seen = await witness.record
        XCTAssertNotNil(seen, "precondition: a record must have existed mid-rename for its clearing to mean anything")

        XCTAssertTrue(InFlight.records().isEmpty, "a completed rename must leave no record behind")
    }

    // MARK: - Direct contract, for `Backlog` (p1b) as a reader

    /// `Backlog.pending` lists raw captures oldest first; `InFlight.records`
    /// promises the same order, so p1b can read the two the same way.
    /// Timestamps are written straight into the store rather than raced
    /// against the wall clock, since a same-second ISO-8601 round trip would
    /// otherwise make the ordering nondeterministic.
    func testRecordsAreOldestFirst() throws {
        var store = InFlight.Store()
        store.records["/b.png"] = InFlight.Record(path: "/b.png", startedAt: Date(timeIntervalSince1970: 50))
        store.records["/a.png"] = InFlight.Record(path: "/a.png", startedAt: Date(timeIntervalSince1970: 100))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(store).write(to: storeURL)

        XCTAssertEqual(InFlight.records().map(\.path), ["/b.png", "/a.png"])
    }

    /// Same boundary `ShotIndex` holds itself to (`HardeningTests`): this is
    /// bookkeeping about the operator's own screen, not something another
    /// account on the machine should be able to read.
    func testTheStoreIsReadableByItsOwnerOnly() throws {
        InFlight.begin(dir.appendingPathComponent("Screenshot 2026-08-11 at 3.41.07 PM.png"))
        let file = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        let folder = try FileManager.default.attributesOfItem(atPath: storeURL.deletingLastPathComponent().path)
        XCTAssertEqual((file[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o600)
        XCTAssertEqual((folder[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o700)
    }
}
