import XCTest
import Darwin
@testable import ShotScribeCore

/// Which files still wear the name macOS gave them. Before 2026-09-11 only the
/// English prefix counted, so on a German or French Mac ShotScribe renamed
/// nothing at all.
final class CaptureDetectionTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-detection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A file in the temp folder, optionally stamped the way macOS stamps a capture.
    private func file(_ name: String, flagged: Bool) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        if flagged {
            let plist = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
            let rc = plist.withUnsafeBytes {
                setxattr(url.path, Naming.captureFlag, $0.baseAddress, plist.count, 0, 0)
            }
            XCTAssertEqual(rc, 0, "setxattr failed: \(errno)")
        }
        return url
    }

    // MARK: The name's shape, in any language

    func testDefaultNamesInOtherLanguagesHaveTheShape() {
        let names = [
            "Screenshot 2026-08-06 at 3.16.12\u{202F}PM.png",   // real, with macOS's narrow no-break space
            "Screenshot 2026-08-11 at 3.41.07 PM (2).png",
            "Bildschirmfoto 2026-08-11 um 15.41.07.png",
            "Capture d’écran 2026-08-11 à 15.41.07.png",
            "Captura de pantalla 2026-08-11 a las 3.41.07 p. m.png",
            "スクリーンショット 2026-08-11 15.41.07.png",
            "截屏2026-08-11 下午3.41.07.png",
            "스크린샷 2026-08-11 오후 3.41.07.png",
            "Снимок экрана 2026-08-11 в 15.41.07.png",
            "Shot 2026-08-11 at 3.41.07 PM.png",                 // custom `screencapture name`
        ]
        for name in names {
            XCTAssertTrue(Naming.hasDefaultCaptureShape(name), name)
        }
    }

    func testShotScribesOwnAndUserChosenNamesDoNotHaveTheShape() {
        let names = [
            "2026-08-11 1541 AWS Billing Console.png",
            "2026-08-11 1541 Release 1.23.45.png",               // a label with a dotted version
            "Quarterly Review.png",
            "IMG_2043.png",
            "Invoice 2026-08-11 notes 1.2.3.png",
            "Bildschirmfoto 2026-08-11 um 15.41.07 for Anna.png",
            "Bildschirmfoto 2026-08-11 um 15.41.07 Anna.png",
        ]
        for name in names {
            XCTAssertFalse(Naming.hasDefaultCaptureShape(name), name)
        }
    }

    // MARK: The rule, on real files

    func testALocalizedCaptureIsRawOnlyWithTheFlag() throws {
        XCTAssertTrue(Naming.isRawCapture(at: try file("Bildschirmfoto 2026-08-11 um 15.41.07.png", flagged: true)))
        XCTAssertFalse(Naming.isRawCapture(at: try file("Capture d’écran 2026-08-11 à 15.41.07.png", flagged: false)),
                       "a shape match alone is not enough")
    }

    /// The flag survives renames, so it cannot be the test on its own: every
    /// capture the user renamed still carries it.
    func testACaptureTheUserRenamedIsNeverRaw() throws {
        XCTAssertFalse(Naming.isRawCapture(at: try file("Quarterly Review.png", flagged: true)))
    }

    /// …and so does every shot ShotScribe already named. Treating those as
    /// raw would have the watcher rename its own output.
    func testAShotScribeNameIsNeverRawAgain() throws {
        XCTAssertFalse(Naming.isRawCapture(at: try file("2026-08-11 1541 AWS Billing Console.png", flagged: true)))
        XCTAssertFalse(Naming.isRawCapture(at: try file("2026-08-11 1541 Release 1.23.45.png", flagged: true)))
    }

    /// Unchanged behaviour: the English prefix needs no flag, so a capture
    /// that lost its attributes in a copy still gets renamed.
    func testTheEnglishPrefixStillNeedsNoFlag() throws {
        XCTAssertTrue(Naming.isRawCapture(at: try file("Screenshot 2026-08-11 at 3.41.07 PM.png", flagged: false)))
    }

    func testAPlainFileIsNotFlagged() throws {
        XCTAssertFalse(Naming.isFlaggedAsCapture(try file("anything.png", flagged: false)))
    }

    // MARK: Through the Renamer

    func testTheRenamerRenamesALocalizedCapture() async throws {
        let renamer = Renamer(titler: KeywordTitler())
        let raw = try file("Bildschirmfoto 2026-08-11 um 15.41.07.png", flagged: true)
        let outcome = try await renamer.rename(fileAt: raw, label: "Billing Console", dryRun: true)
        guard case .wouldRename(_, let to) = outcome else {
            return XCTFail("expected a rename, got \(outcome)")
        }
        XCTAssertTrue(to.lastPathComponent.hasSuffix(" Billing Console.png"), to.lastPathComponent)

        let unflagged = try file("Capture d’écran 2026-08-11 à 15.41.07.png", flagged: false)
        let skipped = try await renamer.rename(fileAt: unflagged, label: "Billing Console", dryRun: true)
        XCTAssertEqual(skipped, .skippedNotRawCapture(unflagged))
    }
}
