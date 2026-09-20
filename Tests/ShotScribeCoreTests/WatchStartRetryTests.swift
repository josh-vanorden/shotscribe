import XCTest
import AppKit
@testable import ShotScribeCore
@testable import ShotScribeUI

/// `Backlog.retryInFlight` (p1b) already retries a capture `InFlight` (p1a)
/// remembers as interrupted mid-rename, but nothing called it, so a capture
/// orphaned by a quit sat under its raw name until someone ran the backlog by
/// hand. This is the wiring (p3a): `ShotScribeModel`'s private
/// `startWatcher()` fires the retry the moment the watch arms, on both doors
/// into watching: a launch with the toggle already on, and turning it on
/// mid-session. So the next time ShotScribe watches is also the next time it
/// finishes what a dead process started.
///
/// Goes through `ShotScribeModel` end to end rather than calling
/// `retryInFlight` directly (`BacklogTests` already covers `Backlog`'s own
/// contract): the point of this file is that *starting the watch* is what
/// triggers it, with no manual backlog run in between.
@MainActor
final class WatchStartRetryTests: XCTestCase {
    private var dir: URL!
    private var inflightDir: URL!
    /// One fixed name, on purpose. `ShotScribeModel.defaults` is a
    /// `static let`, evaluated once per process and cached forever, so a
    /// fresh suite object per test would not stop it pointing at whichever
    /// one happened to be live the first time any test in this file
    /// constructed a model. A `UserDefaults(suiteName:)` for the same name
    /// always reads and writes the same domain regardless of which instance
    /// touches it, so the fix is one name, wiped clean in `setUp`.
    private let suiteName = "shotscribe-tests-watchstartretry"
    private var suite: UserDefaults!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-retry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        inflightDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-retry-inflight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: inflightDir, withIntermediateDirectories: true)
        InFlight.storeOverride = inflightDir.appendingPathComponent("inflight.json")
        ShotIndex.storeOverride = inflightDir.appendingPathComponent("index.json")
        Log.urlOverride = inflightDir.appendingPathComponent("ShotScribe.log")
        suite = UserDefaults(suiteName: suiteName)
        suite.removePersistentDomain(forName: suiteName)
        ShotScribeDefaults.suiteOverride = suite
        // A real ShotScribe.app running on this machine (menu bar or the
        // standalone app) must not make these tests fail on
        // `otherInstanceRunning`; that question is orthogonal to what this
        // file checks.
        ShotScribeModel.otherInstanceRunningOverride = false
    }

    override func tearDownWithError() throws {
        suite.removePersistentDomain(forName: suiteName)
        ShotScribeDefaults.suiteOverride = nil
        InFlight.storeOverride = nil
        ShotIndex.storeOverride = nil
        Log.urlOverride = nil
        ShotScribeModel.otherInstanceRunningOverride = nil
        ShotScribeModel.titlerOverride = nil
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: inflightDir)
    }

    /// A real PNG with words on it, under a raw macOS capture name (the same
    /// fixture shape `InFlightTests` and `BacklogTests` use), so the retry
    /// actually attempts it rather than skipping it as user-named.
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

    /// Polls rather than sleeping a fixed span: the retry does real OCR, and
    /// how long that takes is not this test's business to guess at.
    private func waitUntilGone(_ url: URL, timeout: TimeInterval = 20) async {
        let deadline = Date().addingTimeInterval(timeout)
        while FileManager.default.fileExists(atPath: url.path), Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    // MARK: - Acceptance 1 & 2: both doors into watching retry the capture

    /// The launch door: watching is already on (the shipped default) by the
    /// time `ShotScribeModel.init()` arms the watcher, so the retry has to
    /// fire from inside `init()` itself, with no separate call the operator
    /// has to know to make.
    func testLaunchingWithWatchingAlreadyOnRetriesAnInterruptedCapture() async throws {
        let raw = try capture()
        InFlight.begin(raw)   // the record a crash mid-rename would leave behind
        suite.set(dir.path, forKey: ShotScribeModel.folderKey)
        suite.set(true, forKey: ShotScribeModel.watchingKey)

        let model = ShotScribeModel()
        XCTAssertEqual(model.folder.standardizedFileURL, dir.standardizedFileURL,
                       "precondition: watching the scratch folder")
        XCTAssertTrue(model.watching, "precondition: launched with watching already on")

        await waitUntilGone(raw)
        // Give the watcher's own debounce (0.5s) and landing delay (1.5s)
        // time to play out too, in case the renamed output gets reported
        // back to it. The watcher reports ShotScribe's own output for every
        // ordinary capture (see `rename(_:)`'s comment); the point here is
        // that nothing further happens even then.
        try await Task.sleep(nanoseconds: 2_500_000_000)

        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path),
                       "the interrupted capture should have been retried and renamed once the watch armed")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(remaining.count, 1, "exactly the one capture, under its new name: \(remaining)")
        XCTAssertNil(model.lastError)
    }

    /// The toggle door: watching starts off, the operator flips it on
    /// mid-session, and that has to arm the retry exactly the same way the
    /// launch door does.
    func testTogglingWatchingOnMidSessionRetriesAnInterruptedCapture() async throws {
        let raw = try capture()
        InFlight.begin(raw)
        suite.set(dir.path, forKey: ShotScribeModel.folderKey)
        suite.set(false, forKey: ShotScribeModel.watchingKey)

        let model = ShotScribeModel()
        XCTAssertEqual(model.folder.standardizedFileURL, dir.standardizedFileURL,
                       "precondition: pointed at the scratch folder")
        XCTAssertFalse(model.watching, "precondition: starts with watching off")
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path),
                      "precondition: still under its raw name while watching is off")

        model.watching = true   // the toggle, mid-session

        await waitUntilGone(raw)
        try await Task.sleep(nanoseconds: 2_500_000_000)

        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path),
                       "the interrupted capture should have been retried and renamed once watching was switched on")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(remaining.count, 1, "exactly the one capture, under its new name: \(remaining)")
        XCTAssertNil(model.lastError)
    }

    // MARK: - Acceptance 3: no regression, and never renamed twice

    /// Nothing to retry: the ordinary case, every time watching starts on a
    /// folder with no crash behind it. Starting the watch must not error, and
    /// must not touch anything already sitting in the folder.
    func testAFolderWithNoInFlightRecordsIsUnaffected() async throws {
        try capture("my diagram.png")   // an ordinary, already-named file, never touched
        suite.set(dir.path, forKey: ShotScribeModel.folderKey)
        suite.set(true, forKey: ShotScribeModel.watchingKey)
        XCTAssertTrue(InFlight.records().isEmpty, "precondition: nothing in flight")

        let model = ShotScribeModel()

        // No event to poll for. Give the retry's Task a beat to run (or, as
        // expected here, find nothing to do) before checking nothing moved.
        try await Task.sleep(nanoseconds: 1_500_000_000)

        XCTAssertNil(model.lastError)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["my diagram.png"],
                       "an ordinary file, with no in-flight record, is left exactly alone")
    }

    /// The subtle case `BacklogTests` already proves at the `Backlog` layer:
    /// a record can outlive the rename it describes (the app can crash
    /// *after* the move but *before* `InFlight.end` lands on disk). Wired
    /// through `startWatcher()`, that must still resolve to "already renamed,
    /// leave it" rather than a second rename.
    func testAnAlreadyRenamedCaptureIsNotRenamedTwiceWhenWatchingStarts() async throws {
        let raw = try capture()
        let renamer = Renamer(titler: KeywordTitler())
        let outcome = try await renamer.rename(fileAt: raw)
        guard case .renamed(_, let renamed) = outcome else {
            return XCTFail("setup: expected the capture to rename cleanly, got \(outcome)")
        }
        // Simulate the crash: a record still names the original raw path,
        // even though the rename it was tracking already succeeded and the
        // file has since moved on to `renamed`.
        InFlight.begin(raw)
        suite.set(dir.path, forKey: ShotScribeModel.folderKey)
        suite.set(true, forKey: ShotScribeModel.watchingKey)

        let model = ShotScribeModel()

        // Long enough to cover a real retry attempt (there should be none)
        // plus the watcher's own debounce and landing delay.
        try await Task.sleep(nanoseconds: 3_000_000_000)

        XCTAssertNil(model.lastError)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [renamed.lastPathComponent],
                       "still exactly the one file, under its one name, never renamed twice")
        XCTAssertTrue(InFlight.records().isEmpty, "the stale record is cleared, not left to accumulate")
    }

    // MARK: - Acceptance: the retry goes through the configured titler (p4a)

    /// Returns a fixed title regardless of what it is asked to read — proof of
    /// *which* titler named the retried capture, the way `InFlightTests`'
    /// `WitnessTitler` proves durability. The fixture's OCR text ("Quarterly
    /// Revenue Dashboard") is exactly what `KeywordTitler` would pick from it,
    /// so a result carrying this title instead is only explained by the
    /// configured titler having been asked.
    private struct StubTitler: Titler {
        let fixedTitle: String
        func title(forOCRText text: String) async throws -> String { fixedTitle }
    }

    /// Stands in for a titler that is signed out, offline, or otherwise
    /// unavailable — proof that a retry survives that rather than leaving the
    /// capture raw.
    private struct FailingTitler: Titler {
        struct Failure: Error {}
        func title(forOCRText text: String) async throws -> String { throw Failure() }
    }

    /// Criterion 1. `ShotScribeModel.titlerOverride` stands in for
    /// `ShotScribeDefaults.aiProvider()` — a real provider can't be pointed at
    /// a stub without actually shelling out — the same kind of seam
    /// `otherInstanceRunningOverride` cuts for the same reason.
    ///
    /// Before the fix, `retryInterrupted()` built its `Renamer` with a
    /// hardcoded `KeywordTitler()`, so this failed: the file landed named
    /// "Quarterly Revenue Dashboard" (`KeywordTitler`'s own read of the
    /// fixture), never seeing `titlerOverride` at all.
    func testRetryAtWatchStartUsesTheConfiguredTitlerNotTheOfflineFallback() async throws {
        let raw = try capture()
        InFlight.begin(raw)
        suite.set(dir.path, forKey: ShotScribeModel.folderKey)
        suite.set(true, forKey: ShotScribeModel.watchingKey)
        ShotScribeModel.titlerOverride = StubTitler(fixedTitle: "Board Meeting Notes")

        let model = ShotScribeModel()
        XCTAssertTrue(model.watching, "precondition: launched with watching already on")

        await waitUntilGone(raw)
        try await Task.sleep(nanoseconds: 2_500_000_000)

        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path),
                       "the interrupted capture should have been retried")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(remaining.count, 1, "exactly the one capture, under its new name: \(remaining)")
        XCTAssertTrue(remaining.first?.contains("Board Meeting Notes") ?? false,
                     "the retried capture should carry the configured titler's title, " +
                     "not KeywordTitler's own read of the fixture: \(remaining)")
        XCTAssertNil(model.lastError)
    }

    /// Criterion 2. The configured titler throws on every call; the retry must
    /// still rename the capture rather than leave it sitting under its raw
    /// name. `Renamer.rename` already falls back to a plain "Screenshot"
    /// label when the titler it is handed fails — this proves that fallback
    /// still holds when that titler is the operator's configured one, reached
    /// through the retry path rather than a label passed in directly.
    func testRetryAtWatchStartStillRenamesWhenTheConfiguredTitlerFails() async throws {
        let raw = try capture()
        InFlight.begin(raw)
        suite.set(dir.path, forKey: ShotScribeModel.folderKey)
        suite.set(true, forKey: ShotScribeModel.watchingKey)
        ShotScribeModel.titlerOverride = FailingTitler()

        let model = ShotScribeModel()
        XCTAssertTrue(model.watching, "precondition: launched with watching already on")

        await waitUntilGone(raw)
        try await Task.sleep(nanoseconds: 2_500_000_000)

        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path),
                       "a titler failure must not leave the interrupted capture sitting under its raw name")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(remaining.count, 1, "still renamed, under Renamer's own fallback label: \(remaining)")
    }
}
