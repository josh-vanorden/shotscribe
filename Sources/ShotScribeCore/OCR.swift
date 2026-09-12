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
        var lines: [String] = []
        for cg in frames(atPath: path) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast        // a label doesn't need .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            guard (try? handler.perform([request])) != nil else { continue }
            lines += (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
        let joined = lines.joined(separator: " ")
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
    /// bottom, then left to right. Accurate recognition, since the point is to
    /// rebuild what the shot shows; a title does not need this, a layout does.
    public static func recognizeLayout(atPath path: String, maxLines: Int = 200) -> (size: CGSize, lines: [TextLine]) {
        // For a recording, the middle frame: the layout of the point of it.
        guard let cg = frames(atPath: path).last else { return (.zero, []) }
        let size = CGSize(width: cg.width, height: cg.height)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false   // labels, IDs and code are not words
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil else { return (size, []) }
        let lines = (request.results ?? []).compactMap { obs -> TextLine? in
            guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return TextLine(text: text, box: obs.boundingBox)
        }
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
