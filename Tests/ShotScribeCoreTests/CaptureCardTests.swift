import XCTest
import AppKit
@testable import ShotScribeCore
@testable import ShotScribeUI

/// The card that slides up after a capture: how it tells a name the shot
/// earned from the generic word, that the tile hands over the file on disk
/// and only once there is a name to hand over, and that only a raw capture
/// ever puts a card up.
@MainActor
final class CaptureCardTests: XCTestCase {
    private var dir: URL!
    private var stateDir: URL!
    /// The same name `WatchStartRetryTests` uses, on purpose: `ShotScribeModel.defaults`
    /// is a `static let`, bound to whichever suite is live the first time any
    /// test constructs a model and kept for the process. A second name would
    /// leave every model test after this file reading a suite nobody writes
    /// to — and watching the real Screenshots folder (2026-09-23).
    private let suiteName = "shotscribe-tests-watchstartretry"
    private var suite: UserDefaults!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("card-\(UUID().uuidString)")
        stateDir = FileManager.default.temporaryDirectory.appendingPathComponent("card-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        InFlight.storeOverride = stateDir.appendingPathComponent("inflight.json")
        ShotIndex.storeOverride = stateDir.appendingPathComponent("index.json")
        Log.urlOverride = stateDir.appendingPathComponent("ShotScribe.log")
        suite = UserDefaults(suiteName: suiteName)
        suite.removePersistentDomain(forName: suiteName)
        ShotScribeDefaults.suiteOverride = suite
        ShotScribeModel.otherInstanceRunningOverride = false
        suite.set(dir.path, forKey: ShotScribeModel.folderKey)
        suite.set(false, forKey: ShotScribeModel.watchingKey)
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
        try? FileManager.default.removeItem(at: stateDir)
    }

    /// A real PNG with words on it, under a raw macOS capture name.
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

    private struct FixedTitler: Titler {
        let answer: String
        func title(forOCRText text: String) async throws -> String { answer }
    }

    private struct FailingTitler: Titler {
        struct Down: Error {}
        func title(forOCRText text: String) async throws -> String { throw Down() }
    }

    // MARK: - The generic word

    func testTheGenericWordIsTheOneEveryTitlerFallsBackTo() async throws {
        XCTAssertEqual(LabelCleaner.clean(""), LabelCleaner.generic)
        XCTAssertEqual(LabelCleaner.clean("  \"\"  "), LabelCleaner.generic)
        let offline = try await KeywordTitler().title(forOCRText: "")
        XCTAssertEqual(offline, LabelCleaner.generic)
    }

    func testANameTheShotEarnedIsNotGeneric() async throws {
        let raw = try capture()
        ShotScribeModel.titlerOverride = FixedTitler(answer: "AWS Billing Console")
        let model = ShotScribeModel()
        await model.rename(raw)
        let named = try XCTUnwrap(model.justNamed)
        XCTAssertTrue(named.to.hasSuffix("AWS Billing Console.png"), named.to)
        XCTAssertFalse(named.generic)
        XCTAssertNil(model.lastError)
    }

    func testTheGenericWordIsFlaggedForTheCard() async throws {
        let raw = try capture()
        ShotScribeModel.titlerOverride = FixedTitler(answer: LabelCleaner.generic)
        let model = ShotScribeModel()
        await model.rename(raw)
        let named = try XCTUnwrap(model.justNamed)
        XCTAssertTrue(named.to.hasSuffix("\(LabelCleaner.generic).png"), named.to)
        XCTAssertTrue(named.generic, "the card must be able to set the generic word apart")
    }

    /// A titler that is down still gets the shot a name — the offline one,
    /// from the words already read — and the card is told it is a real name.
    /// The error stays visible; it was not the name's fault.
    func testATitlerThatFailsGetsTheOfflineNameAndKeepsTheError() async throws {
        let raw = try capture()
        ShotScribeModel.titlerOverride = FailingTitler()
        let model = ShotScribeModel()
        await model.rename(raw)
        let named = try XCTUnwrap(model.justNamed)
        XCTAssertTrue(named.to.localizedCaseInsensitiveContains("Revenue")
                      || named.to.localizedCaseInsensitiveContains("Quarterly"), named.to)
        XCTAssertFalse(named.generic, "an offline title read off the picture is a real name")
        XCTAssertNotNil(model.lastError, "the titler failing is still reported")
    }

    // MARK: - The tile as a drag source

    /// What lands on the pasteboard is the file, as a file URL — what Finder,
    /// a browser's upload field, Slack and Jira all read — not the pixels.
    func testTheTileHandsOverTheFileOnDisk() throws {
        let file = try capture("2026-08-11 1541 AWS Billing Console.png")
        let tile = DragTileView()
        tile.url = file
        let board = NSPasteboard(name: NSPasteboard.Name("shotscribe-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        XCTAssertTrue(board.writeObjects([tile.pasteboardItem()]))
        XCTAssertTrue(board.types?.contains(.fileURL) == true, "\(board.types ?? [])")
        let read = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(read?.first?.standardizedFileURL, file.standardizedFileURL)
        XCTAssertNil(board.data(forType: .png), "the picture travels as the file, not as pixels")
    }

    /// Draggable before the name lands — naming takes seconds and a drag
    /// that had to wait fired the click instead — and the drop reads the file
    /// as it is *then*: picked up raw, delivered renamed.
    func testADragPickedUpWhileNamingDeliversTheRenamedFile() throws {
        let raw = try capture()
        let tile = DragTileView()
        tile.url = raw
        let board = NSPasteboard(name: NSPasteboard.Name("shotscribe-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        XCTAssertTrue(board.writeObjects([tile.pasteboardItem()]), "picked up while still naming")

        let renamed = dir.appendingPathComponent("2026-08-11 1541 AWS Billing Console.png")
        try FileManager.default.moveItem(at: raw, to: renamed)
        tile.url = renamed   // the name lands mid-drag

        let read = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(read?.first?.standardizedFileURL, renamed.standardizedFileURL,
                       "the drop reads the file's name at that moment, not at pick-up")
    }

    func testAPressBecomesADragOnlyOnceItHasMoved() {
        XCTAssertFalse(DragTileView.isDrag(from: NSPoint(x: 10, y: 10), to: NSPoint(x: 12, y: 11)))
        XCTAssertTrue(DragTileView.isDrag(from: NSPoint(x: 10, y: 10), to: NSPoint(x: 15, y: 10)))
    }

    /// The card's picture is the state's own and survives the rename: the
    /// path changes, the pixels do not.
    func testTheCardKeepsItsPictureThroughTheRename() {
        let state = CaptureCardState(url: URL(fileURLWithPath: "/tmp/Screenshot 2026-08-11 at 3.41.07 PM.png"),
                                     from: "Screenshot 2026-08-11 at 3.41.07 PM.png")
        state.image = NSImage(size: NSSize(width: 4, height: 4))
        XCTAssertFalse(state.named)
        state.url = URL(fileURLWithPath: "/tmp/2026-08-11 1541 AWS Billing Console.png")
        state.to = "2026-08-11 1541 AWS Billing Console.png"
        XCTAssertTrue(state.named)
        XCTAssertNotNil(state.image)
        XCTAssertEqual(state.title, "2026-08-11 1541 AWS Billing Console")
    }

    // MARK: - Only a raw capture puts a card up

    /// The watcher reports ShotScribe's own output too — the renamed file
    /// lands in the same folder — and announcing that once put up a second
    /// card saying "Naming…" that never resolved. A landing is announced for
    /// the raw capture, and for nothing else.
    func testOnlyARawCaptureIsAnnouncedAsLanded() async throws {
        ShotScribeModel.titlerOverride = FixedTitler(answer: "Board Review")
        suite.set(true, forKey: ShotScribeModel.watchingKey)
        let model = ShotScribeModel()
        XCTAssertTrue(model.watching, "precondition: watching the scratch folder")
        try await Task.sleep(nanoseconds: 300_000_000)   // let the watcher arm

        let raw = try capture()
        let deadline = Date().addingTimeInterval(20)
        while model.justNamed == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        let named = try XCTUnwrap(model.justNamed, "the capture should have been named")
        // By name: the raw file is gone by now, and a path that no longer
        // exists cannot have its /var → /private/var link resolved.
        XCTAssertEqual(model.justLanded?.lastPathComponent, raw.lastPathComponent,
                       "the raw capture is what was announced as landed")
        XCTAssertTrue(named.to.hasSuffix("Board Review.png"), named.to)

        // The renamed file is reported back to the watcher, debounce and
        // landing delay included. It must not be announced as a landing.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertEqual(model.justLanded?.lastPathComponent, raw.lastPathComponent,
                       "ShotScribe's own output never puts up a card")
    }
}
