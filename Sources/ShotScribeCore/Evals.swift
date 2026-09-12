import Foundation

/// How good are the titles? Measured against the names the operator already
/// kept. A folder of renamed captures is an eval set with no fixtures to
/// maintain: every accepted filename is a judged answer, and the Finder tags
/// on the file are the judged filing.
///
/// The shape — a fixed set, a score, runs compared — is borrowed from
/// abi/screenshot-to-code's `Evaluation.md`. The twist is that the ratings
/// already exist, on disk, in the names nobody changed.
public enum Evals {

    public struct Case: Equatable, Sendable {
        public var url: URL
        public var expectedTitle: String
        public var expectedTags: [String]

        public init(url: URL, expectedTitle: String, expectedTags: [String]) {
            self.url = url
            self.expectedTitle = expectedTitle
            self.expectedTags = expectedTags
        }
    }

    public struct Score: Equatable, Sendable {
        public var file: String
        public var expected: String
        public var actual: String
        /// The same title, case and punctuation aside.
        public var exact: Bool
        /// Share of the expected title's words that appear in the actual one:
        /// "AWS Billing" against "AWS Billing Console" is 1.0, the reverse 0.67.
        public var recall: Double
        /// Of the tags given, how many were expected; of the tags expected, how
        /// many were given. nil when there was nothing to judge on that side.
        public var tagPrecision: Double?
        public var tagRecall: Double?
    }

    public struct Summary: Equatable, Sendable {
        public var count: Int
        public var exactRate: Double
        public var meanRecall: Double
        public var tagPrecision: Double?
        public var tagRecall: Double?
    }

    /// Every already-named capture in `folder`: the stem, less the template's
    /// stamp, is the expected title; the Finder tags are the expected tags. Raw
    /// captures are skipped — nobody has judged those yet.
    public static func cases(in folder: URL) -> [Case] {
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? [])
            .filter(Capture.isCapture)
            .filter { !Naming.isRawCapture(at: $0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return urls.compactMap { url in
            let title = Sessions.stem(of: url.deletingPathExtension().lastPathComponent)
            // A user's own name with no stamp is a judged answer too.
            guard !title.isEmpty else { return nil }
            return Case(url: url, expectedTitle: title, expectedTags: Tagging.finderTags(of: url))
        }
    }

    public static func score(_ actual: Labelling, against c: Case) -> Score {
        let want = words(c.expectedTitle), got = words(actual.title)
        let hit = want.filter { got.contains($0) }.count
        let recall = want.isEmpty ? 0 : Double(hit) / Double(want.count)
        let wantTags = Set(c.expectedTags.map { $0.lowercased() })
        let gotTags = Set(actual.tags.map { $0.lowercased() })
        let both = wantTags.intersection(gotTags).count
        return Score(
            file: c.url.lastPathComponent,
            expected: c.expectedTitle,
            actual: actual.title,
            exact: want == got && !want.isEmpty,
            recall: recall,
            tagPrecision: gotTags.isEmpty ? nil : Double(both) / Double(gotTags.count),
            tagRecall: wantTags.isEmpty ? nil : Double(both) / Double(wantTags.count))
    }

    public static func summarize(_ scores: [Score]) -> Summary {
        guard !scores.isEmpty else { return Summary(count: 0, exactRate: 0, meanRecall: 0, tagPrecision: nil, tagRecall: nil) }
        let n = Double(scores.count)
        let precisions = scores.compactMap(\.tagPrecision), recalls = scores.compactMap(\.tagRecall)
        return Summary(
            count: scores.count,
            exactRate: Double(scores.filter(\.exact).count) / n,
            meanRecall: scores.map(\.recall).reduce(0, +) / n,
            tagPrecision: precisions.isEmpty ? nil : precisions.reduce(0, +) / Double(precisions.count),
            tagRecall: recalls.isEmpty ? nil : recalls.reduce(0, +) / Double(recalls.count))
    }

    /// Lower-case words, letters and digits only, in order. "AWS Billing
    /// Console" and "aws-billing-console" are the same answer.
    static func words(_ s: String) -> [String] {
        s.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
