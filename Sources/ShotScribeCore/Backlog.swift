import Foundation

/// **The backlog: captures that landed while nothing was watching.**
///
/// ShotScribe names what arrives while it runs. Everything that arrived before
/// it was installed, or while it was quit, or during a rename it was quit in
/// the middle of, sits in the folder under its raw macOS name forever — 93 of
/// them on the operator's own Mac on 2026-09-16, going back to early August.
///
/// This finds them and describes what each would be called. It never renames
/// anything by itself: the operator reads the list and confirms it, the same
/// shape as `Cleanup` — a plan, then an apply.
public enum Backlog {
    /// Raw captures in `folder`, oldest first — the order they were taken in,
    /// which is the order a person reading the list expects.
    ///
    /// Flat, like the watcher and the index: a subfolder is somewhere the
    /// operator put things on purpose.
    public static func pending(in folder: URL, fileManager: FileManager = .default) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]
        guard let items = try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .filter(Capture.isCapture)
            .filter { Naming.isRawCapture(at: $0) }
            .sorted { taken($0) < taken($1) }
    }

    /// One capture, read and titled, with the name it would get.
    public struct Proposal: Identifiable, Equatable, Sendable {
        public let url: URL
        public let label: String
        public let tags: [String]
        /// The filename as it stands today, with no other rename considered.
        /// Two proposals can arrive at the same name; the apply suffixes the
        /// second one, as a live rename would.
        public let name: String
        public var id: String { url.path }

        public init(url: URL, label: String, tags: [String], name: String) {
            self.url = url; self.label = label; self.tags = tags; self.name = name
        }
    }

    /// Read one capture and say what it would be called. Nothing moves.
    ///
    /// The titler runs here, once, and its answer is carried in the proposal —
    /// so applying the list does not ask the model a second time.
    public static func propose(_ url: URL, renamer: Renamer, titler: Titler,
                               vocabulary: [String]) async -> Proposal? {
        let lines = OCR.recognizeLines(atPath: url.path)
        let labelling = (try? await titler.labelling(
            forOCRText: OCR.text(of: Chrome.body(of: lines)), vocabulary: vocabulary))
            ?? Labelling(title: "Screenshot")
        let label = LabelCleaner.clean(labelling.title)
        let tags = Tagging.accepted(labelling.tags, vocabulary: vocabulary)
        guard let outcome = try? await renamer.rename(
                fileAt: url, label: label, app: Chrome.app(in: lines), tags: tags, dryRun: true),
              case .wouldRename(_, let target) = outcome else { return nil }
        return Proposal(url: url, label: label, tags: tags, name: target.lastPathComponent)
    }

    private static func taken(_ url: URL) -> Date {
        let v = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return v?.creationDate ?? v?.contentModificationDate ?? .distantPast
    }
}
