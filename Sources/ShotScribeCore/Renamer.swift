import Foundation

/// The outcome of a rename attempt — explicit so the CLI (and later the MCP
/// server) can report exactly what happened.
public enum RenameOutcome: Sendable, Equatable {
    case renamed(from: URL, to: URL)
    case wouldRename(from: URL, to: URL)   // dry run
    case skippedNotRawCapture(URL)         // user-named file — left alone
    case skippedNoLabel(URL)               // nothing usable to name it
    case fileMissing(URL)
}

/// Orchestrates one screenshot: OCR the file, ask the `Titler` for a label,
/// and rename it `<date> <time> <Label>.ext`. Only macOS raw captures are
/// renamed unless `force` is set.
public struct Renamer: Sendable {
    public let titler: Titler
    /// How the new name is spelled. The doors load the operator's stored one
    /// (`ShotScribeDefaults.nameTemplate()`); the default reproduces the format
    /// ShotScribe has always used.
    public let template: NameTemplate
    /// The closed list a tag must come from. Empty — the default — means this
    /// renamer files nothing, which is how it behaved before tags existed.
    public let vocabulary: [String]

    public init(titler: Titler, template: NameTemplate = .default, vocabulary: [String] = []) {
        self.titler = titler
        self.template = template
        self.vocabulary = vocabulary
    }

    private var fileManager: FileManager { .default }

    /// OCR + title only — the `label` command. Never touches the file.
    public func label(fileAt url: URL) async -> String {
        await labelling(fileAt: url).title
    }

    /// Told when the titler fails. The shot still gets a name — the offline
    /// titler's — but a door can say what went wrong instead of letting a
    /// signed-out or blocked assistant look like a blunt titler. (Until 1.6 a
    /// failure silently became "Screenshot".)
    public var onTitlerError: (@Sendable (Error) -> Void)?

    /// OCR + title + the filing this renamer would give it. Touches nothing.
    public func labelling(fileAt url: URL) async -> Labelling {
        let ocr = OCR.text(of: Chrome.body(of: OCR.recognizeLines(atPath: url.path)))
        do {
            let proposed = try await titler.labelling(forOCRText: ocr, vocabulary: vocabulary)
            if !proposed.title.isEmpty { return proposed }
        } catch {
            onTitlerError?(error)
            if let offline = try? await KeywordTitler().labelling(forOCRText: ocr, vocabulary: vocabulary),
               !offline.title.isEmpty { return offline }
        }
        return Labelling(title: "Screenshot")
    }

    /// Rename `url` in place. `force` renames even files the user named
    /// themselves; `dryRun` computes the target without moving anything.
    ///
    /// `label` short-circuits the OCR→titler pipeline: when the caller already
    /// has a title (the MCP case — the calling model IS the intelligence, so
    /// asking our own titler would be a wasteful nested LLM call), we clean it
    /// and use it directly.
    @discardableResult
    public func rename(fileAt url: URL, label explicitLabel: String? = nil,
                       app explicitApp: String? = nil,
                       tags explicitTags: [String] = [],
                       force: Bool = false, dryRun: Bool = false) async throws -> RenameOutcome {
        guard fileManager.fileExists(atPath: url.path) else { return .fileMissing(url) }

        guard force || Naming.isRawCapture(at: url) else { return .skippedNotRawCapture(url) }

        let label: String
        var app = explicitApp
        var tags = Tagging.accepted(explicitTags, vocabulary: vocabulary.isEmpty
                                    ? Tagging.defaultVocabulary : vocabulary)
        if let explicitLabel, !explicitLabel.trimmingCharacters(in: .whitespaces).isEmpty {
            label = LabelCleaner.clean(explicitLabel)
        } else {
            let lines = OCR.recognizeLines(atPath: url.path)
            let labelling = (try? await titler.labelling(forOCRText: OCR.text(of: Chrome.body(of: lines)), vocabulary: vocabulary))
                ?? Labelling(title: "Screenshot")
            label = LabelCleaner.clean(labelling.title)
            if tags.isEmpty { tags = labelling.tags }
            if app == nil { app = Chrome.app(in: lines) }
        }
        // A caller that brought its own title skipped the read; do it only when
        // the template actually spells the app.
        if app == nil, template.layout.contains("{app}") {
            app = Chrome.app(in: OCR.recognizeLines(atPath: url.path))
        }

        guard let desired = Naming.filename(label: label, app: app, capturedAt: capturedAt(of: url),
                                            ext: url.pathExtension, template: template) else {
            return .skippedNoLabel(url)
        }

        let dir = url.deletingLastPathComponent()
        let final = Naming.uniqueName(desired) { candidate in
            fileManager.fileExists(atPath: dir.appendingPathComponent(candidate).path)
        }
        let target = dir.appendingPathComponent(final)
        guard target.path != url.path else { return .skippedNoLabel(url) }

        if dryRun { return .wouldRename(from: url, to: target) }
        try fileManager.moveItem(at: url, to: target)
        // After the move, and never fatal: a Finder tag is a nicety, a rename is
        // the job. Tags the user put on by hand are kept.
        if !tags.isEmpty { Tagging.add(tags, to: target) }
        return .renamed(from: url, to: target)
    }

    // MARK: Undo

    /// Where an undo would put `url` back: its original name, suffixed only if
    /// something else has taken that name meanwhile.
    public static func restoredURL(for url: URL, original: String) -> URL {
        let dir = url.deletingLastPathComponent()
        let name = Naming.uniqueName(original) {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
        return dir.appendingPathComponent(name)
    }

    /// The undo itself — a plain move. Kept apart from `restoredURL` so a
    /// caller can announce the target to a watcher *before* the file appears
    /// under a raw name it would otherwise pounce on.
    public static func restore(fileAt url: URL, to target: URL) throws {
        try FileManager.default.moveItem(at: url, to: target)
    }

    /// Best-effort capture time: file creation date, then modification date,
    /// then now.
    private func capturedAt(of url: URL) -> Date {
        let vals = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return vals?.creationDate ?? vals?.contentModificationDate ?? Date()
    }
}
