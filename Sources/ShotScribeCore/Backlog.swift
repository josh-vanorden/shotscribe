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
            .sorted { (Capture.takenAt($0) ?? .distantPast) < (Capture.takenAt($1) ?? .distantPast) }
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

    // MARK: - Retrying interrupted renames

    /// Every capture `InFlight` still remembers as mid-rename in `folder`,
    /// resolved *before* `pending` runs. These are the ones a user already
    /// watched fail once; they are retried first rather than folded into the
    /// ordinary sweep, which only ever sees a raw name and has no memory that
    /// this one was already attempted.
    ///
    /// **What "already renamed" means.** A record can outlive the rename it
    /// describes: the app can crash *after* `Renamer.rename` has moved the
    /// file to its new name but *before* the `InFlight.end` that follows it
    /// lands on disk. A restarted process has exactly two observable facts
    /// about a record, both read straight off the filesystem rather than
    /// inferred from anything remembered in memory: whether a file still
    /// exists at the path the record names, and — if one does — whether it is
    /// still shaped like an untouched capture (`Naming.isRawCapture`). Either
    /// a missing file (moved to its new name, or removed some other way) or a
    /// present-but-no-longer-raw one means the rename this record was tracking
    /// is already resolved, one way or another. There is nothing safe left to
    /// do with either, so the record is cleared rather than retried — the
    /// alternative would rename whatever now happens to sit at that path, or
    /// would just "retry" a rename that already happened.
    ///
    /// **A record that genuinely cannot be retried does not accumulate
    /// either.** `Renamer.rename` itself clears the record (via `defer`) on
    /// every outcome once it actually attempts one — renamed, or turned away
    /// for lacking a usable label — so a capture that is stuck for good is
    /// cleared here the one time it is looked at, and simply reappears in the
    /// ordinary raw-capture backlog next, rather than being "retried" forever
    /// as an in-flight record that can never resolve.
    @discardableResult
    public static func retryInFlight(in folder: URL, renamer: Renamer) async -> [RenameOutcome] {
        let folder = folder.standardizedFileURL
        var outcomes: [RenameOutcome] = []
        for record in InFlight.records() {
            let url = URL(fileURLWithPath: record.path)
            guard url.deletingLastPathComponent().standardizedFileURL.path == folder.path else { continue }
            guard FileManager.default.fileExists(atPath: url.path), Naming.isRawCapture(at: url) else {
                InFlight.end(url)   // resolved already (renamed away, or gone) — nothing to retry
                continue
            }
            if let outcome = try? await renamer.rename(fileAt: url) {
                outcomes.append(outcome)
            }
        }
        return outcomes
    }
}
