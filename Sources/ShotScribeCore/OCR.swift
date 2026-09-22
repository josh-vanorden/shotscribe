import AppKit
import Vision

/// On-device OCR for screenshot labeling. Uses the Vision framework (free,
/// private, no network) to pull the visible text out of a screenshot; that
/// text is what gets summarized into a 2–3 word label. Text-heavy shots
/// (code, consoles, dashboards) OCR well; image-only shots return little and
/// fall back to a generic label upstream.
public enum OCR {
    /// Recognize text in the image at `path`. Runs synchronously — call it off
    /// the main thread. Returns up to `maxChars` of joined text ("" on failure
    /// or an image with no text).
    public static func recognizeText(atPath path: String, maxChars: Int = 900) -> String {
        text(of: recognizeLines(atPath: path), maxChars: maxChars)
    }

    /// Every frame, read at the accurate level with positions kept. One Vision
    /// call serves both the title and `Chrome.app`, which reads the menu bar or
    /// title bar off it.
    ///
    /// **Accurate, always.** Until 2026-09-22 this was a `.fast` pass, with an
    /// accurate re-read only for a big picture that came back sparse. Twice in
    /// one day that was the bug: a wide org chart with five-pixel names read as
    /// 75 characters of noise, and then five small captures of slides — 280
    /// pixels wide, titles in plain sight — read as 0 to 36 characters and sat
    /// under the size gate that decided which pictures deserved the re-read.
    /// Measured on those files, the accurate pass costs 40–200 ms whatever the
    /// size, and the titler it feeds takes seconds. A heuristic that saves a
    /// tenth of a second and names a shot "Screenshot" is not a saving.
    public static func recognizeLines(atPath path: String) -> [TextLine] {
        frames(atPath: path).flatMap { recognize(enlarged($0)) }
    }

    /// A picture whose longer side is under this many pixels is read at twice
    /// its size. Vision reads by pixel height, not by meaning: a 292-pixel
    /// capture of a slide read 171 characters of the wrong alphabet at its own
    /// size and 797 clean ones doubled (2026-09-22). Doubling a bigger picture
    /// changed nothing but the time, so it is not done.
    static let doubledBelow = 1000

    /// The picture as Vision should see it: small ones doubled, the rest as is.
    static func enlarged(_ cg: CGImage) -> CGImage {
        guard max(cg.width, cg.height) < doubledBelow else { return cg }
        let w = cg.width * 2, h = cg.height * 2
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? cg
    }

    /// One accurate pass, no language correction — labels, IDs and code are
    /// not words. Boxes come back normalised, so a doubled picture reports the
    /// same positions as the original.
    private static func recognize(_ cg: CGImage) -> [TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { obs -> TextLine? in
            guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return TextLine(text: text, box: obs.boundingBox)
        }
    }

    /// What the titlers read: the lines joined, trimmed, capped.
    public static func text(of lines: [TextLine], maxChars: Int = 900) -> String {
        let joined = lines.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(joined.prefix(maxChars))
    }

    /// What to read: a still is one frame, a screen recording is a couple.
    /// Empty when the file is neither, or cannot be opened.
    public static func frames(atPath path: String) -> [CGImage] {
        let url = URL(fileURLWithPath: path)
        if Capture.isMovie(url) { return Frames.stills(of: url) }
        guard let image = NSImage(contentsOfFile: path),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        return [cg]
    }

    /// One recognised line and where it sits. The box is what Vision reports:
    /// normalised 0–1, origin bottom-left. Enough to say "this is the title, up
    /// top", "these four are a row", "that column is a sidebar" — the structure
    /// of a screen, read off it on-device, without the pixels going anywhere.
    public struct TextLine: Sendable, Equatable {
        public var text: String
        public var box: CGRect

        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }

        /// The same box the way a person or a page reads it: top-left origin,
        /// in percent of the image.
        public var top: Double { (1 - box.maxY) * 100 }
        public var left: Double { box.minX * 100 }
        public var width: Double { box.width * 100 }
        public var height: Double { box.height * 100 }
    }

    /// The text of a screenshot with its layout, in reading order — top to
    /// bottom, then left to right. The size is the picture's own, and the
    /// boxes are in percent of it, so a small picture read doubled still
    /// reports where things are on the file.
    public static func recognizeLayout(atPath path: String, maxLines: Int = 200) -> (size: CGSize, lines: [TextLine]) {
        // For a recording, the middle frame: the layout of the point of it.
        guard let cg = frames(atPath: path).last else { return (.zero, []) }
        let size = CGSize(width: cg.width, height: cg.height)
        let lines = recognize(enlarged(cg))
        // Same row when the vertical centres are within half a line of each
        // other; then left to right within the row.
        let ordered = lines.sorted { a, b in
            let tolerance = min(a.box.height, b.box.height) / 2
            if abs(a.box.midY - b.box.midY) > tolerance { return a.box.midY > b.box.midY }
            return a.box.minX < b.box.minX
        }
        return (size, Array(ordered.prefix(maxLines)))
    }
}
