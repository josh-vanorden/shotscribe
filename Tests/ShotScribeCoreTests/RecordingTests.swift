import XCTest
import AVFoundation
import AppKit
@testable import ShotScribeCore

/// Screen recordings land in the same folder as stills and, until 2026-09-12,
/// ShotScribe walked past them. Now they are captures too: recognised by name,
/// read from a couple of frames, named by the same titler.
final class RecordingTests: XCTestCase {

    // MARK: The name and the list

    func testARecordingIsACaptureAndAMovie() {
        let mov = URL(fileURLWithPath: "/tmp/Screen Recording 2026-09-12 at 3.41.07 PM.mov")
        XCTAssertTrue(Capture.isCapture(mov))
        XCTAssertTrue(Capture.isMovie(mov))
        XCTAssertFalse(Capture.isMovie(URL(fileURLWithPath: "/tmp/shot.png")))
        XCTAssertFalse(Capture.isCapture(URL(fileURLWithPath: "/tmp/notes.txt")))
    }

    /// macOS writes no capture xattr on a recording (checked on a real one,
    /// 2026-09-12), so the English prefix has to carry it on its own.
    func testARecordingsDefaultNameIsRaw() throws {
        XCTAssertTrue(Naming.looksLikeDefaultCaptureName("Screen Recording 2026-09-12 at 3.41.07\u{202F}PM.mov"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Screen Recording 2026-09-12 at 3.41.07 PM.mov")
        try Data([0]).write(to: url)
        XCTAssertTrue(Naming.isRawCapture(at: url), "no xattr, and still raw")
        XCTAssertFalse(Naming.isRawCapture(at: dir.appendingPathComponent("2026-09-12 1541 Deploy Run.mov")))
    }

    // MARK: Frames and the text in them

    /// A real two-second recording with a sentence on every frame, written the
    /// way any QuickTime file is, so the frame grab and the OCR are exercised
    /// on the thing itself rather than a stand-in.
    private func recording(saying text: String) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString).mov")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let width = 640, height = 360

        let frame = NSImage(size: NSSize(width: width, height: height))
        frame.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        (text as NSString).draw(at: NSPoint(x: 40, y: 150), withAttributes: [
            .font: NSFont.systemFont(ofSize: 44, weight: .bold), .foregroundColor: NSColor.black])
        frame.unlockFocus()
        let cg = try XCTUnwrap(frame.cgImage(forProposedRect: nil, context: nil, hints: nil))

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        XCTAssertTrue(writer.startWriting(), "\(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)
        for i in 0..<5 {   // five frames, half a second apart: two seconds of it
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32ARGB, nil, &buffer)
            let pb = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pb, [])
            let ctx = try XCTUnwrap(CGContext(
                data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(pb, [])
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            XCTAssertTrue(adaptor.append(pb, withPresentationTime: CMTime(value: Int64(i) * 300, timescale: 600)))
        }
        input.markAsFinished()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in writer.finishWriting { c.resume() } }
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
        return url
    }

    func testFramesComeOutOfARecording() async throws {
        let url = try await recording(saying: "Deploy Dashboard")
        let stills = Frames.stills(of: url)
        XCTAssertEqual(stills.count, 2, "a beat in, and the middle")
        XCTAssertEqual(stills.first?.width, 640)
    }

    func testARecordingIsReadLikeAStill() async throws {
        let url = try await recording(saying: "Deploy Dashboard")
        let text = OCR.recognizeText(atPath: url.path)
        XCTAssertTrue(text.contains("Deploy"), "got \"\(text)\"")
        let (size, lines) = OCR.recognizeLayout(atPath: url.path)
        XCTAssertEqual(size.width, 640)
        XCTAssertTrue(lines.contains { $0.text.contains("Dashboard") }, "got \(lines.map(\.text))")
    }

    func testARecordingGetsANameFromItsFrames() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let made = try await recording(saying: "Deploy Dashboard")
        let raw = dir.appendingPathComponent("Screen Recording 2026-09-12 at 3.41.07 PM.mov")
        try FileManager.default.moveItem(at: made, to: raw)

        let outcome = try await Renamer(titler: KeywordTitler()).rename(fileAt: raw, dryRun: true)
        guard case .wouldRename(_, let to) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(to.pathExtension, "mov", "the extension rides along")
        XCTAssertTrue(to.lastPathComponent.contains("Deploy") || to.lastPathComponent.contains("Dashboard"),
                      "named from the frames: \(to.lastPathComponent)")
    }
}
