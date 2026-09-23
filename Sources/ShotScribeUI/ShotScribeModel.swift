import Foundation
import SwiftUI
import AppKit
import ServiceManagement
import ShotScribeCore

/// One rename the app performed — shown in the panel's history.
/// A capture the watcher has just named, announced once so something can show
/// it. Distinct from `RenameEvent`, which is the persisted history: this is the
/// live "it happened, now" signal, and it carries the file so a card can put
/// the picture on screen.
public struct NamedCapture: Equatable {
    public let url: URL
    public let from: String
    public let to: String
    public let at: Date
    /// The name is the generic word — nothing was read off the picture, or
    /// what was read made no title — rather than one the shot earned.
    public let generic: Bool

    public init(url: URL, from: String, to: String, at: Date, generic: Bool = false) {
        self.url = url; self.from = from; self.to = to; self.at = at; self.generic = generic
    }
}

public struct RenameEvent: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var date: Date
    public var from: String
    public var to: String
}

/// ShotScribe's state: the watch toggle (wraps `FolderWatcher`), the titler
/// preference, and a small persisted history of renames.
///
/// Lives in `ShotScribeUI` rather than in the menu bar executable so anything
/// that wants to host ShotScribe's face can — the executable is one consumer,
/// not the owner. Per the repo's doctrine this package knows nothing about who
/// that host might be.
///
/// `ObservableObject` (not `@Observable`) on purpose — keeps the package's
/// macOS 13 floor for open-source reach.
@MainActor
public final class ShotScribeModel: ObservableObject {
    static let watchingKey = "shotscribe.watching"
    static let eventsKey = "shotscribe.events"
    static let keepKey = "shotscribe.keep"
    private static let maxEvents = 20

    /// Auto-rename new captures as they land. ON by default: launching an app
    /// whose one job is renaming screenshots is the opt-in.
    @Published public var watching: Bool {
        didSet {
            Self.defaults.set(watching, forKey: Self.watchingKey)
            watching ? startWatcher() : stopWatcher()
        }
    }

    /// What `~/.config/llm/provider.json` says, if anything. Read at launch for
    /// display; the AI tab offers it as a one-click choice.
    @Published public private(set) var llmPreference = LLMPreference.load()

    /// Non-nil when the machine's choice is one ShotScribe cannot honour.
    public var llmMismatchNote: String? { llmPreference.mismatchNote }

    public func refreshLLMPreference() { llmPreference = LLMPreference.load() }

    /// Who titles a capture — the AI tab's setting, honoured by every door.
    @Published public private(set) var aiProvider: AIProvider = ShotScribeDefaults.aiProvider()

    public func setAIProvider(_ provider: AIProvider) {
        ShotScribeDefaults.setAIProvider(provider)
        aiProvider = provider
        aiTrial = nil
        refreshAIAvailability()
    }

    /// Whether the chosen titler can run here, computed off the main thread:
    /// finding a CLI can mean spawning a login shell, and a shell spawned
    /// inside a view's body stalls the window (and raced the picker's commit).
    @Published public private(set) var aiAvailability: AIProvider.Availability = .ready("Checking…")

    private func refreshAIAvailability() {
        let provider = aiProvider
        Task.detached(priority: .userInitiated) { [weak self] in
            let availability = provider.availability()
            await MainActor.run { [weak self] in
                guard let self, self.aiProvider == provider else { return }
                self.aiAvailability = availability
            }
        }
    }

    /// The popover's one switch: AI titling on or off. Off remembers nothing;
    /// on picks Claude Code when it is installed, else the first CLI that is.
    public var aiTitling: Bool {
        get { aiProvider.kind != .offline }
        set {
            if !newValue { setAIProvider(AIProvider(kind: .offline)); return }
            let first = [AIProvider.Kind.claude, .codex, .ollama, .gemini, .cursor]
                .first { AIProvider(kind: $0).availability().isReady } ?? .claude
            setAIProvider(AIProvider(kind: first))
        }
    }

    /// Whether an endpoint key is in the Keychain. Never the key itself.
    public var endpointKeyStored: Bool { Secrets.store.get(Secrets.endpointKeyAccount) != nil }
    public func setEndpointKey(_ key: String?) {
        Secrets.store.set(key, for: Secrets.endpointKeyAccount)
        objectWillChange.send()
    }

    /// The last "try it" result, for one line under the AI tab's button.
    @Published public private(set) var aiTrial: String?
    @Published public private(set) var aiTrying = false

    /// Title the newest capture with the chosen provider and show the answer,
    /// without renaming anything — the AI tab's proof that the setting works.
    public func tryTitler() {
        guard !aiTrying else { return }
        let folder = self.folder
        let provider = aiProvider
        let vocabulary = taggingEnabled ? self.vocabulary : []
        aiTrying = true
        aiTrial = "Reading the newest capture…"
        Task { @MainActor [weak self] in
            defer { self?.aiTrying = false }
            let newest = ShotIndex.imageFiles(in: folder).max { a, b in
                ((try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)
                    < ((try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)
            }
            guard let newest else { self?.aiTrial = "No capture in \(folder.lastPathComponent) to try on."; return }
            let lines = await Task.detached(priority: .userInitiated) {
                Chrome.body(of: OCR.recognizeLines(atPath: newest.path))
            }.value
            let titler: Titler = provider.makeTitler() ?? KeywordTitler()
            let started = Date()
            do {
                let got = try await titler.labelling(for: lines, vocabulary: vocabulary)
                let secs = String(format: "%.1f s", Date().timeIntervalSince(started))
                let tags = got.tags.isEmpty ? "" : " · " + got.tags.joined(separator: ", ")
                self?.aiTrial = "\(newest.lastPathComponent) → “\(got.title)”\(tags) · \(secs)"
            } catch {
                self?.aiTrial = "Failed: \(error.localizedDescription)"
            }
        }
    }

    @Published public private(set) var events: [RenameEvent] = []
    @Published public private(set) var lastError: String?

    /// Something a window other than the main one wants said in it.
    public func report(_ message: String) { lastError = message }
    /// True while a rename (OCR + titling) is in flight — the panel shows a spinner.
    @Published public private(set) var busy = false

    public let claudeAvailable = ClaudeTitler.isAvailable()
    /// The assistant a shot is handed to, from the provider: Claude Code
    /// unless the titler is itself a chat (Codex, Gemini, Cursor).
    public var assistantName: String { aiProvider.kind.assistant }
    private var watcher: FolderWatcher?

    public static let folderKey = "shotscribe.folder"

    /// Where new captures are expected. Defaults to the macOS screenshot
    /// location; the panel's "Change…" points it anywhere.
    @Published public private(set) var folder: URL = {
        if let path = ShotScribeModel.defaults.string(forKey: ShotScribeModel.folderKey) {
            return URL(fileURLWithPath: path)
        }
        return FolderWatcher.defaultScreenshotDirectory()
    }()

    /// True when the operator picked a custom folder (shows the reset arrow).
    public var usesCustomFolder: Bool {
        Self.defaults.string(forKey: Self.folderKey) != nil
    }

    /// NSOpenPanel → new watch folder, persisted; the watcher re-arms on it.
    public func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Watch This Folder"
        panel.message = "ShotScribe renames new screenshots that land in this folder."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Self.defaults.set(url.path, forKey: Self.folderKey)
        setFolder(url)
    }

    /// Back to the system screenshot location (`com.apple.screencapture`).
    public func useSystemFolder() {
        Self.defaults.removeObject(forKey: Self.folderKey)
        setFolder(FolderWatcher.defaultScreenshotDirectory())
    }

    /// The folders worth one click. Desktop and Documents because that is where
    /// macOS puts captures by default and where people move them; the third is
    /// ShotScribe's own, created on demand so "somewhere tidy" needs no
    /// decision.
    public struct FolderChoice: Identifiable, Sendable {
        public var id: String { url.path }
        public var label: String
        public var url: URL
        public var creates: Bool
    }

    /// Where people actually point screenshots. macOS defaults to Desktop, and
    /// Documents and Downloads are the two places it gets moved to; the last is
    /// ShotScribe's own, created on demand so "somewhere tidy" needs no decision.
    public static var quickFolders: [FolderChoice] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            .init(label: "Desktop", url: home.appendingPathComponent("Desktop"), creates: false),
            .init(label: "Documents", url: home.appendingPathComponent("Documents"), creates: false),
            .init(label: "Downloads", url: home.appendingPathComponent("Downloads"), creates: false),
            .init(label: "Screenshots", url: home.appendingPathComponent("Pictures/Screenshots"), creates: true),
        ]
    }

    /// Point the watcher somewhere, creating the folder if this is the one we
    /// offer to make. Returns false when the folder is not usable, rather than
    /// silently watching nothing.
    @discardableResult
    public func use(_ choice: FolderChoice) -> Bool {
        if choice.creates {
            try? FileManager.default.createDirectory(at: choice.url, withIntermediateDirectories: true)
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: choice.url.path, isDirectory: &isDir), isDir.boolValue else {
            lastError = "\(choice.url.lastPathComponent) is not a folder ShotScribe can watch."
            return false
        }
        setFolder(choice.url)
        return true
    }

    /// Accept a folder dropped on the row. A file is taken as its containing
    /// folder — dropping a screenshot to mean "watch where this lives" is the
    /// obvious reading, and refusing it would be pedantry.
    public func acceptDrop(_ url: URL) {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard exists else { return }
        setFolder(isDir.boolValue ? url : url.deletingLastPathComponent())
    }

    private func setFolder(_ url: URL) {
        folder = url
        Log.write("watch folder → \(url.path)")
        stopWatcher()
        if watching { startWatcher() }
        // A different folder is a different corpus: the index view must follow
        // it, or search silently answers from the old one.
        loadIndex()
        hits = []
        refreshBacklogCount()
        // ...and the new folder's screenshots are almost certainly not in the
        // store at all. `loadIndex()` only READS what has been indexed; without
        // this, pointing at a folder full of existing captures produced an empty
        // browser and a search that found nothing, with no sign anything was
        // wrong. `rebuildIndex` had no caller anywhere in the app.
        rebuildIndex()
    }

    // MARK: - Keeping

    /// What is kept. Persisted beside the folder and the toggles, in
    /// ShotScribe's own defaults. A changed policy drops any open clean-up
    /// preview — it was computed under the old one.
    @Published public var keepPolicy: KeepPolicy = .default {
        didSet {
            if let data = try? JSONEncoder().encode(keepPolicy) {
                Self.defaults.set(data, forKey: Self.keepKey)
            }
            if keepPolicy != oldValue { cleanupPlan = nil }
        }
    }

    // MARK: - Naming

    /// How a rename spells the new name. Read from ShotScribe's own defaults, so
    /// the CLI and the MCP server agree with the app; `.default` reproduces the
    /// format ShotScribe has always used.
    @Published public private(set) var nameTemplate: NameTemplate = ShotScribeDefaults.nameTemplate()

    /// The sample a settings pane shows under the field.
    public var nameTemplateSample: String {
        Naming.sampleFilename(nameTemplate) ?? "—"
    }

    /// Saves a template, or refuses it and says why. A changed template applies
    /// to captures from here on; it never re-spells what is already named.
    @discardableResult
    public func setNameTemplate(_ template: NameTemplate) -> TemplateProblem? {
        if let problem = ShotScribeDefaults.setNameTemplate(template) {
            lastError = problem.why
            return problem
        }
        nameTemplate = template
        lastError = nil
        return nil
    }

    /// The closed list a tag may come from. Stored, so the CLI and the MCP
    /// server file things the same way this app does.
    @Published public private(set) var vocabulary: [String] = ShotScribeDefaults.vocabulary()

    /// Save an edited vocabulary. An empty one goes back to the shipped list —
    /// turning filing off is a different question from having no words for it.
    public func setVocabulary(_ tags: [String]) {
        ShotScribeDefaults.setVocabulary(tags)
        vocabulary = ShotScribeDefaults.vocabulary()
    }

    /// Clear the list in one go, rather than sixteen times.
    public func clearVocabulary() { setVocabulary([]) }

    /// And put the shipped words back.
    public func restoreVocabulary() {
        ShotScribeDefaults.restoreDefaultVocabulary()
        vocabulary = ShotScribeDefaults.vocabulary()
    }

    /// Whether renames file captures at all. Off leaves the vocabulary intact
    /// and stops new renames being tagged; tags already on files stay.
    @Published public private(set) var taggingEnabled: Bool = ShotScribeDefaults.taggingEnabled()

    /// The words of every shot as Spotlight keywords — off by default, since
    /// they travel with the file. Switching on writes them to every indexed
    /// shot from the text the index already holds; switching off takes them
    /// off again, so nothing lingers on a file after the choice changes.
    @Published public private(set) var spotlightKeywords: Bool = ShotScribeDefaults.spotlightKeywords()
    @Published public private(set) var spotlightBusy = false

    public func setSpotlightKeywords(_ on: Bool) {
        ShotScribeDefaults.setSpotlightKeywords(on)
        spotlightKeywords = on
        let shots = indexCache
        spotlightBusy = true
        Task.detached(priority: .utility) { [weak self] in
            var n = 0
            for shot in shots where !Capture.isMovie(shot.url) {
                if on {
                    let words = Spotlight.keywords(title: shot.name, tags: shot.tags ?? [], text: shot.text)
                    if Spotlight.write(words, to: shot.url) { n += 1 }
                } else {
                    Spotlight.remove(from: shot.url); n += 1
                }
            }
            Log.write("spotlight keywords \(on ? "written to" : "removed from") \(n) shot(s)")
            await MainActor.run { self?.spotlightBusy = false }
        }
    }

    public func setTaggingEnabled(_ on: Bool) {
        ShotScribeDefaults.setTaggingEnabled(on)
        taggingEnabled = on
    }

    /// What the app just put on the pasteboard, for one line under the grid
    /// head: the pasteboard is silent, so the surface says what is on it and
    /// where it goes. The agent and the repo live in Claude Code; the app hands
    /// over what it knows and points there.
    public struct HandoffNote: Equatable {
        public let text: String
        public let symbol: String
    }
    @Published public private(set) var handoffNote: HandoffNote?
    private var handoffGeneration = 0

    /// Stage two, as far as the app can take it: the shot as a brief for Claude
    /// Code, to paste inside the project the code should land in.
    public func copyCodeBrief(for shot: IndexedShot) {
        // Counted against Send to: they are one tile now.
        note(.sendTo)
        let path = shot.path
        let generation = show(HandoffNote(text: "Reading the layout…", symbol: "hammer"))
        Task { @MainActor [weak self] in
            let brief = await Task.detached(priority: .userInitiated) { CodeBrief.text(forImageAt: path) }.value
            // A later hand-off (another shot, or Send to Claude) owns the pasteboard.
            guard let self, self.handoffGeneration == generation else { return }
            let agent = self.aiProvider.kind == .claude ? "Claude Code" : "your coding agent"
            self.handOver(brief, saying: HandoffNote(
                text: "Copied. Paste into \(agent) inside the project the code should land in.", symbol: "hammer"))
        }
    }

    /// The shot to the assistant's session. Nothing can push into a running
    /// session, so this is one line on the pasteboard: `/screenshot "<path>"`
    /// for Claude Code (the skill reads this shot rather than the newest), a
    /// plain ask for any other chat. Dragging the tile in is the wordless version.
    public func sendToAssistant(_ shot: IndexedShot) {
        note(.sendTo)
        let kind = aiProvider.kind
        let where_: String
        switch kind {
        case .claude:                       where_ = "a Claude Code session on this Mac; /screenshot reads this shot there. For claude.ai or the Claude app, send the picture instead"
        case .codex, .gemini, .cursor:      where_ = "a \(kind.assistant) session on this Mac. For a chat in a browser, send the picture instead"
        case .ollama:                       where_ = "Ollama’s chat (a vision model can also take the image dragged in)"
        case .offline, .command, .endpoint: where_ = "any assistant’s chat on this Mac"
        }
        handOver(SendToClaude.line(forImageAt: shot.path, kind: kind), saying: HandoffNote(
            text: "Copied. Paste into \(where_).", symbol: "paperplane"))
    }

    /// The shot itself, for a chat that cannot see this Mac — claude.ai, the
    /// Claude app, any web chat. A ⌘V there attaches the picture; the path
    /// never leaves this Mac. A recording has no still to send.
    public func sendPicture(_ shot: IndexedShot) {
        note(.sendTo)
        guard !Capture.isMovie(shot.url) else {
            show(HandoffNote(text: "A recording can’t be pasted as a picture — drag the file into the chat instead.", symbol: "film"))
            return
        }
        guard let item = SendToClaude.picture(forImageAt: shot.url) else {
            show(HandoffNote(text: "Couldn’t read \(shot.url.lastPathComponent) to copy it.", symbol: "exclamationmark.triangle"))
            return
        }
        handOver([item], saying: HandoffNote(
            text: "Copied the picture. Paste into claude.ai, the Claude app, or any chat — it arrives as the image, not a path.",
            symbol: "photo.on.rectangle"))
    }

    private func handOver(_ text: String, saying note: HandoffNote) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        handOver([item], saying: note)
    }

    private func handOver(_ items: [NSPasteboardItem], saying note: HandoffNote) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
        let generation = show(note)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            if self?.handoffGeneration == generation { self?.handoffNote = nil }
        }
    }

    @discardableResult
    private func show(_ note: HandoffNote) -> Int {
        handoffGeneration += 1
        handoffNote = note
        return handoffGeneration
    }

    /// The title, edited in the landing zone. The stamp stays as spelled, only
    /// the words change, and the file moves at once. A shot ShotScribe named
    /// keeps its raw original for undo; one it did not gets its previous name
    /// there, so this is undoable too.
    public func retitle(_ shot: IndexedShot, to title: String) {
        guard let stem = Naming.retitled(shot.name, to: title, style: nameTemplate.titleStyle),
              stem != shot.name else { return }
        let dir = shot.url.deletingLastPathComponent()
        let ext = shot.url.pathExtension
        let name = Naming.uniqueName(ext.isEmpty ? stem : "\(stem).\(ext)") {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
        let target = dir.appendingPathComponent(name)
        watcher?.ignore(target)
        do {
            try Renamer.restore(fileAt: shot.url, to: target)
            Log.write("retitle: \(shot.url.lastPathComponent) → \(name)")
            lastError = nil
            let original = shot.original ?? shot.url.lastPathComponent
            Task.detached(priority: .utility) { [weak self] in
                ShotIndex.forget(shot.path)
                ShotIndex.record(target, original: original)
                await MainActor.run { self?.loadIndex(); self?.runSearch() }
            }
        } catch {
            Log.write("retitle FAILED: \(error)")
            lastError = "Couldn’t rename \(shot.name): \(error.localizedDescription)"
        }
    }

    /// File a shot that is already named — the only way to reach an older
    /// capture, since the vocabulary otherwise only applies at rename time.
    public func tag(_ shot: IndexedShot, with tag: String) {
        note(.fileAs)
        guard Tagging.add(Tagging.accepted([tag], vocabulary: vocabulary), to: shot.url) else {
            lastError = "Couldn't tag \(shot.name)."
            return
        }
        ShotIndex.record(shot.url, original: shot.original)
        loadIndex()
        runSearch()
    }

    /// Takes a tag back off. Filing is a guess, and a guess you cannot undo is
    /// worse than no guess at all.
    public func untag(_ shot: IndexedShot, _ tag: String) {
        guard Tagging.remove([tag], from: shot.url) else {
            lastError = "Couldn't take \(tag) off \(shot.name)."
            return
        }
        ShotIndex.record(shot.url, original: shot.original)
        loadIndex()
        runSearch()
    }

    /// Whether this shot already carries a tag, however it is spelled.
    public func isTagged(_ shot: IndexedShot, _ tag: String) -> Bool {
        (shot.tags ?? []).contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    /// One gesture for both: filing under a tag, and taking it off again.
    public func toggleTag(_ shot: IndexedShot, _ tag: String) {
        isTagged(shot, tag) ? untag(shot, tag) : self.tag(shot, with: tag)
    }

    /// The plan the user is looking at. nil = no preview open.
    @Published public private(set) var cleanupPlan: Cleanup.Plan?
    @Published public private(set) var cleaning = false

    /// What the policy would move — nothing touches disk here. **Scoped to
    /// the watched folder**: the index is global, and a plan over all of it
    /// reached every folder ever watched while the list named only files
    /// (QA, 2026-09-04).
    public func previewCleanup() {
        let root = ((try? folder.resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath ?? folder.path) + "/"
        let here = indexCache.filter { $0.path.hasPrefix(root) }
        cleanupPlan = Cleanup.plan(here, policy: keepPolicy)
    }

    public func cancelCleanup() { cleanupPlan = nil }

    /// Apply the plan the user just looked at. Off the main thread — a hundred
    /// moves to the Trash is not instant.
    public func applyCleanup() {
        guard let plan = cleanupPlan, !plan.isEmpty, !cleaning else { return }
        cleaning = true
        Task.detached(priority: .utility) { [weak self] in
            let outcome = Cleanup.apply(plan)
            await MainActor.run {
                guard let self else { return }
                self.cleaning = false
                self.cleanupPlan = nil
                Log.write("clean-up: \(outcome.moved.count) → \(plan.destination.label), \(outcome.failures.count) failed")
                self.lastError = outcome.failures.isEmpty ? nil
                    : "Couldn’t move \(outcome.failures.count) of \(plan.moves.count): \(outcome.failures.values.first ?? "")"
                self.loadIndex()
                self.runSearch()
            }
        }
    }

    // MARK: - Editing

    /// A request to open the editor. A fresh id each time, so asking twice for
    /// the same shot brings its window forward rather than being deduplicated
    /// away.
    public struct EditRequest: Equatable {
        public let url: URL
        public let id = UUID()
    }

    @Published public private(set) var editRequest: EditRequest?

    /// Open the editor on a file. By path rather than by indexed shot, so the
    /// capture card can open one the index sweep has not caught up with yet.
    /// Images only — a screen recording is not something to draw on.
    public func editFile(_ url: URL) {
        guard !Capture.isMovie(url) else {
            lastError = "\(url.deletingPathExtension().lastPathComponent) is a recording — only images can be edited."
            return
        }
        editRequest = EditRequest(url: url)
    }

    /// Save an edit, keep it editable, and make everything that remembers the
    /// old picture forget it.
    ///
    /// - **Editable later.** `EditStore` keeps the picture under the marks and
    ///   the marks themselves, so reopening brings every annotation back live.
    ///   This replaced parking a copy of the original in the Trash.
    /// - **A redaction is never kept.** It is burned into the kept picture, and
    ///   only annotations stay as objects.
    /// - **The index is re-read**, because it holds the text that was on the
    ///   screen. Pixelating an address while search still finds it would be
    ///   redaction in appearance only.
    public func saveEdit(source: CGImage, marks: [Mark], frame: FrameStyle, crop: CGRect?, scale: CGFloat,
                         watermark: Watermark? = nil, sourceIsOriginal: Bool, to url: URL,
                         done: @escaping (Bool) -> Void) {
        let original = shot(atPath: url.path)?.original
        let redacts = marks.contains { $0.kind.redacts }
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try EditStore.commit(source: source, marks: marks, frame: frame, crop: crop, scale: scale,
                                     watermark: watermark, sourceIsOriginal: sourceIsOriginal, to: url)
                ShotIndex.record(url, original: original)
                Log.write("edited \(url.lastPathComponent): \(marks.count) mark(s)\(redacts ? ", redacted" : "")\(frame.isPlain ? "" : ", framed")\(watermark.map { $0.isEmpty ? "" : ", watermarked" } ?? "")")
                await MainActor.run { self?.afterEdit(url); done(true) }
            } catch {
                await MainActor.run {
                    self?.lastError = "Couldn’t save the edit: \(error.localizedDescription)"
                    done(false)
                }
            }
        }
    }

    /// Put the untouched capture back. Only offered while nothing was ever
    /// redacted — after that there is no untouched capture, on purpose.
    public func revertEdit(_ url: URL, done: @escaping (Bool) -> Void) {
        let original = shot(atPath: url.path)?.original
        Task.detached(priority: .userInitiated) { [weak self] in
            let ok = (try? EditStore.revert(url)) ?? false
            if ok {
                ShotIndex.record(url, original: original)
                Log.write("reverted \(url.lastPathComponent) to the original")
            }
            await MainActor.run {
                if ok { self?.afterEdit(url) }
                else { self?.lastError = "This capture can’t be reverted — part of it was hidden and the original wasn’t kept." }
                done(ok)
            }
        }
    }

    // MARK: The last capture, from the menu bar

    /// The capture taken most recently — what "last capture" means in the menu.
    var newestShot: IndexedShot? { indexCache.max { $0.captured < $1.captured } }

    /// Whether a capture carries a watermark ShotScribe can take off again.
    func hasWatermark(_ shot: IndexedShot) -> Bool {
        !(EditStore.document(for: shot.url)?.watermark?.isEmpty ?? true)
    }

    /// Put a watermark on a capture, or take it off with nil — no editor. The
    /// same ending as any edit: the index re-read, the thumbnail refreshed.
    func setWatermark(_ watermark: Watermark?, on shot: IndexedShot) {
        let url = shot.url, original = shot.original
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                guard try EditStore.setWatermark(watermark, on: url) != nil else { return }
                ShotIndex.record(url, original: original)
                Log.write("\(watermark == nil ? "watermark off" : "watermarked") \(url.lastPathComponent)")
                await MainActor.run { self?.afterEdit(url) }
            } catch {
                await MainActor.run { self?.lastError = "Couldn’t change the watermark: \(error.localizedDescription)" }
            }
        }
    }

    private func afterEdit(_ url: URL) {
        ThumbnailCache.shared.refresh(url.path)
        loadIndex()
        runSearch()
    }

    // MARK: - The backlog

    /// A sweep in progress: every raw capture found, the names read so far, and
    /// the rows the operator has unticked. Nothing on disk changes until
    /// `applyBacklog` — the same promise the clean-up preview makes.
    public struct BacklogRun: Equatable {
        public let pending: [URL]
        /// Keyed by path: three are read at once and they finish in any order,
        /// so the list is rebuilt from `pending` rather than kept in arrival order.
        public var read: [String: Backlog.Proposal] = [:]
        public var excluded: Set<String> = []
        public var reading = true
        public var applying = false
        public var applied = 0

        /// In the order the captures were taken.
        public var proposals: [Backlog.Proposal] { pending.compactMap { read[$0.path] } }
        public var chosen: [Backlog.Proposal] { proposals.filter { !excluded.contains($0.id) } }
    }

    @Published public private(set) var backlog: BacklogRun?
    /// How many raw captures are waiting — what the Folder tab says out loud.
    @Published public private(set) var backlogCount = 0
    private var backlogTask: Task<Void, Never>?

    public func refreshBacklogCount() {
        let folder = self.folder
        Task.detached(priority: .utility) { [weak self] in
            let n = Backlog.pending(in: folder).count
            await MainActor.run { self?.backlogCount = n }
        }
    }

    /// Find every raw capture and start reading names for them.
    ///
    /// **Three at a time.** Titling is a model call of several seconds, and
    /// ninety of them one after another is a quarter of an hour; three
    /// together is a few minutes without flooding the assistant. The list fills
    /// as they finish, and what has been read can be applied before the rest.
    public func startBacklog() {
        guard backlog == nil else { return }
        let pending = Backlog.pending(in: folder)
        backlog = BacklogRun(pending: pending)
        backlogCount = pending.count
        guard !pending.isEmpty else { backlog?.reading = false; return }

        let titler = self.titler
        let vocab = taggingEnabled ? vocabulary : []
        let renamer = Renamer(titler: KeywordTitler(), template: nameTemplate, vocabulary: vocab)
        backlogTask = Task { [weak self] in
            await withTaskGroup(of: Backlog.Proposal?.self) { group in
                var next = 0
                func enqueue() {
                    guard next < pending.count else { return }
                    let url = pending[next]
                    next += 1
                    group.addTask {
                        await Backlog.propose(url, renamer: renamer, titler: titler, vocabulary: vocab)
                    }
                }
                for _ in 0..<min(3, pending.count) { enqueue() }
                while let proposal = await group.next() {
                    if Task.isCancelled { group.cancelAll(); break }
                    if let proposal { self?.backlog?.read[proposal.id] = proposal }
                    enqueue()
                }
            }
            self?.backlog?.reading = false
        }
    }

    /// Stop reading, keep what has been read.
    public func stopBacklogReading() {
        backlogTask?.cancel()
        backlogTask = nil
        backlog?.reading = false
    }

    public func toggleBacklog(_ id: String) {
        guard var run = backlog else { return }
        if run.excluded.contains(id) { run.excluded.remove(id) } else { run.excluded.insert(id) }
        backlog = run
    }

    public func setBacklogAll(_ included: Bool) {
        guard var run = backlog else { return }
        run.excluded = included ? [] : Set(run.read.keys)
        backlog = run
    }

    public func cancelBacklog() {
        backlogTask?.cancel()
        backlogTask = nil
        backlog = nil
    }

    /// Rename every ticked row, using the title that was already read for it.
    ///
    /// The watcher is told about each new name before the file lands, so a
    /// sweep of ninety does not look to it like ninety fresh captures. And the
    /// rename history is left alone — twenty rows of it would be nothing but
    /// this — with one log line instead.
    public func applyBacklog() {
        guard let run = backlog, !run.applying else { return }
        backlogTask?.cancel()
        backlogTask = nil
        let chosen = run.chosen
        guard !chosen.isEmpty else { return }
        backlog?.reading = false
        backlog?.applying = true

        let vocab = taggingEnabled ? vocabulary : []
        let renamer = Renamer(titler: KeywordTitler(), template: nameTemplate, vocabulary: vocab)
        Task { [weak self] in
            var done = 0
            var failed = 0
            for p in chosen {
                if case .wouldRename(_, let target)? = try? await renamer.rename(
                    fileAt: p.url, label: p.label, tags: p.tags, dryRun: true) {
                    self?.watcher?.ignore(target)
                }
                do {
                    if case .renamed(let from, let to) = try await renamer.rename(
                        fileAt: p.url, label: p.label, tags: p.tags) {
                        ShotIndex.forget(from.path)
                        ShotIndex.record(to, original: from.lastPathComponent)
                        done += 1
                        self?.backlog?.applied = done
                    }
                } catch {
                    failed += 1
                }
            }
            Log.write("backlog: named \(done) of \(chosen.count)\(failed > 0 ? ", \(failed) failed" : "")")
            guard let self else { return }
            self.lastError = failed > 0 ? "Couldn’t name \(failed) of \(chosen.count)." : nil
            self.backlog = nil
            self.loadIndex()
            self.runSearch()
            self.refreshBacklogCount()
        }
    }

    /// NSOpenPanel → the archive folder. Picking one also selects archiving.
    public func chooseArchiveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Archive Here"
        panel.message = "Flagged screenshots move into this folder instead of the Trash."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Archiving into the watched folder would "move" a file onto itself
        // with a suffix and re-flag it on every pass.
        guard url.standardizedFileURL != folder.standardizedFileURL else {
            lastError = "The archive folder can't be the folder being watched."
            return
        }
        keepPolicy.destination = .archive(path: url.path)
    }

    // Sessions

    /// Which bursts are opened out, by session id.
    @Published var expandedSessions: Set<String> = []

    /// The tiles, folded into sessions when the policy says so. Flat while
    /// searching (results are ranked, not chronological) and under the name
    /// sorts, where "consecutive" means nothing.
    var sessions: [Session] {
        let chronological = query.trimmingCharacters(in: .whitespaces).isEmpty
            && (sort == .newest || sort == .oldest)
        return Sessions.collapse(visibleShots, gapMinutes: chronological ? keepPolicy.sessionGapMinutes : 0)
    }

    func isExpanded(_ s: Session) -> Bool { expandedSessions.contains(s.id) }

    func toggleExpanded(_ s: Session) {
        if expandedSessions.contains(s.id) { expandedSessions.remove(s.id) }
        else { expandedSessions.insert(s.id) }
    }

    // Undo

    /// A history row can be walked back while the renamed file is still where
    /// the rename left it. A row whose "from" is not a raw capture name is an
    /// undo itself, and is not offered again.
    func canUndo(_ e: RenameEvent) -> Bool {
        // Not while ShotScribe.app is watching this folder: the only watcher
        // an undo can warn is this copy's, and the other app would rename the
        // restored file straight back (QA, 2026-09-04).
        !otherInstanceRunning
            && Naming.looksLikeDefaultCaptureName(e.from)
            && FileManager.default.fileExists(atPath: folder.appendingPathComponent(e.to).path)
    }

    func undo(_ e: RenameEvent) {
        restore(folder.appendingPathComponent(e.to), original: e.from)
    }

    func undo(_ shot: IndexedShot) {
        guard let original = shot.original else { return }
        restore(shot.url, original: original)
    }

    /// Put a capture back under the name it arrived with.
    ///
    /// The watcher is told first: a raw "Screenshot …" name reappearing in the
    /// folder is exactly what it watches for, and without `ignore` it would
    /// rename the file straight back. The move follows in the same turn, well
    /// inside the watcher's half-second debounce.
    private func restore(_ url: URL, original: String) {
        let target = Renamer.restoredURL(for: url, original: original)
        watcher?.ignore(target)
        do {
            try Renamer.restore(fileAt: url, to: target)
            Log.write("undo: \(url.lastPathComponent) → \(target.lastPathComponent)")
            record(from: url.lastPathComponent, to: target.lastPathComponent)
            lastError = nil
            Task.detached(priority: .utility) { [weak self] in
                ShotIndex.forget(url.path)
                ShotIndex.record(target)
                await MainActor.run { self?.loadIndex(); self?.runSearch() }
            }
        } catch {
            Log.write("undo FAILED: \(error)")
            lastError = "Couldn’t restore the original name: \(error.localizedDescription)"
        }
    }

    // MARK: - Launch at login

    /// SMAppService only works from a real .app bundle; from `swift run` the
    /// register call throws and the error surfaces in the panel.
    public var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    public func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = "Launch at login: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }

    public init() {
        defer { refreshAIAvailability(); refreshBacklogCount() }
        let ud = Self.defaults
        watching = ud.object(forKey: Self.watchingKey) == nil
            ? true : ud.bool(forKey: Self.watchingKey)
        if let data = ud.data(forKey: Self.eventsKey),
           let saved = try? JSONDecoder().decode([RenameEvent].self, from: data) {
            events = saved
        }
        // "tiles" and "deck" are what 1.6.2 and this morning's build stored;
        // both become the carousel rather than dropping the operator back to
        // the default by way of a value that no longer decodes.
        if let raw = ud.string(forKey: "shotView") {
            shotView = ShotView(rawValue: raw) ?? (raw == "list" ? .list : .carousel)
        }
        if let raw = ud.string(forKey: "shotSort"), let v = ShotSort(rawValue: raw) {
            sort = v
        }
        if let data = ud.data(forKey: Self.keepKey),
           let saved = try? JSONDecoder().decode(KeepPolicy.self, from: data) {
            keepPolicy = saved
        }
        loadIndex()
        refreshOtherInstance()
        observeOtherInstances()
        if watching { startWatcher() }
        // Sweep on launch. Captures land while this app is closed — dropped in
        // by hand, synced, or taken with the watcher off — and the watcher only
        // ever sees what arrives while it is running. Cheap after the first
        // pass: `reindex` skips any file whose size is unchanged, so the steady
        // state is a directory listing plus a stat per file, and only genuinely
        // new images are read for text.
        rebuildIndex()
    }

    // MARK: - Not stepping on another copy of ourselves

    /// True when ShotScribe.app is running in some *other* process — i.e. this
    /// model is hosted somewhere else (a shell that mounts the surface) while
    /// the standalone app is also alive.
    ///
    /// Two live `FolderWatcher`s on one folder both fire on the same new
    /// capture and both try to rename it; one wins, the other errors on a file
    /// that no longer exists, and which is which is a coin flip. So the hosted
    /// copy stands down rather than racing.
    @Published public private(set) var otherInstanceRunning = false

    /// Tests point this at `false` so a real ShotScribe.app that happens to be
    /// running on the machine the suite executes on can't make a watcher test
    /// fail for a reason that has nothing to do with what it is checking. The
    /// same seam `InFlight.storeOverride` and `ShotIndex.storeOverride` cut,
    /// for the same reason (`WatchStartRetryTests`, 2026-09-20).
    static var otherInstanceRunningOverride: Bool?

    /// Tests point this at a stub so a retried capture's titler can be proven
    /// without a real AI provider — `ShotScribeDefaults.aiProvider()` names a
    /// closed set of real providers (Claude, Codex, Ollama…), none of which a
    /// test can safely point at a witness. Same seam, same reason, as
    /// `otherInstanceRunningOverride` (`WatchStartRetryTests`, 2026-09-20).
    static var titlerOverride: Titler?

    private static let appBundleID = "com.joshvanorden.shotscribe"
    private var runningAppsObservation: NSKeyValueObservation?

    /// ShotScribe's settings belong to ShotScribe, not to whatever process
    /// happens to be hosting it.
    ///
    /// Inside ShotScribe.app this is just `.standard`. Anywhere else it is the
    /// same preferences domain reached by name, so a hosted copy sees the
    /// folder you actually chose and the history you actually have. Without
    /// this, a host with its own bundle id starts blank — and starts renaming
    /// files in a folder you never pointed it at.
    ///
    /// (Reached via `suiteName` only from outside; Apple warns against naming
    /// your own bundle id as a suite from within it, which the branch avoids.)
    ///
    /// One implementation, in the engine, because the CLI and the MCP server
    /// have to resolve the same domain to read the same name template.
    static let defaults: UserDefaults = ShotScribeDefaults.suite

    private func refreshOtherInstance() {
        if let override = Self.otherInstanceRunningOverride {
            otherInstanceRunning = override
            return
        }
        let me = Bundle.main.bundleIdentifier
        otherInstanceRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Self.appBundleID && $0.bundleIdentifier != me
        }
    }

    /// Re-check when apps come and go, so quitting ShotScribe.app hands the
    /// folder back without needing a restart here.
    ///
    /// KVO on `runningApplications` rather than the workspace's
    /// didLaunch/didTerminate notifications: ShotScribe.app is `LSUIElement`,
    /// and those notifications did not arrive for it. `runningApplications` is
    /// documented KVO-compliant and does see accessory apps.
    private func observeOtherInstances() {
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                let was = self.otherInstanceRunning
                self.refreshOtherInstance()
                guard was != self.otherInstanceRunning else { return }
                if self.otherInstanceRunning {
                    self.stopWatcher()
                } else if self.watching {
                    self.lastError = nil
                    self.startWatcher()
                }
            }
        }
    }

    // MARK: - Watching

    private func startWatcher() {
        guard watcher == nil else { return }
        guard !otherInstanceRunning else {
            lastError = "ShotScribe.app is already watching this folder — quit it to rename from here."
            return
        }
        let w = FolderWatcher(directory: folder) { url in
            // A capture can land before macOS finishes writing it (the floating
            // thumbnail lingers) — give the file a beat before reading.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                // Announced here, not after the rename: the titler is a model
                // call and takes seconds, and a card that arrives ten seconds
                // after the screenshot has missed the moment it is about.
                //
                // Only for a capture that is actually going to be renamed. The
                // watcher reports ShotScribe's *own* output too — the renamed
                // file lands in the same folder — and announcing that put up a
                // second card saying "Naming…" that never resolved, because
                // the rename it was waiting for returns `skippedNotRawCapture`
                // (2026-09-15).
                if Naming.isRawCapture(at: url) { self?.justLanded = url }
                await self?.rename(url)
            }
        }
        if w.start() {
            watcher = w
            retryInterrupted()
        } else {
            lastError = "Can't watch \(folder.path)"
            watching = false
        }
    }

    /// A capture the app was still renaming when it last quit is left sitting
    /// under its raw name, and the watcher just armed can never pick it up on
    /// its own: `FolderWatcher.start()` seeds `seen` from everything already in
    /// the folder, so a raw name that was there before watching started looks
    /// exactly like one nobody has touched yet. `Backlog.retryInFlight` (p1b)
    /// is what finishes it, given the chance; this is that chance, so a
    /// capture interrupted by a quit does not sit there until someone happens
    /// to run the backlog by hand (the goal card, decision 1).
    ///
    /// Called from `startWatcher()` alone, so both doors into watching go
    /// through it: a launch with the toggle already on, and turning it on
    /// mid-session.
    ///
    /// Fired off, not awaited. `startWatcher()` is synchronous and must return
    /// immediately, but the retry itself (OCR, then a title) takes real time.
    ///
    /// **A retried capture is named by the titler the operator configured**
    /// (2026-09-20). `Backlog.retryInFlight` calls `renamer.rename(fileAt:)`
    /// with no label, so whichever titler the `Renamer` it is handed carries
    /// is the one that names the capture — unlike `rename(_:)` and
    /// `startBacklog()`, which compose OCR and the AI title themselves and
    /// hand the result down as an explicit label, making `Renamer`'s own
    /// titler only their fallback. There is no proposal or progress step here
    /// to compose that label from, so this builds the `Renamer` the way the
    /// CLI's retry already does (`main.swift`): with `titler` — the same
    /// computed property `rename(_:)` reads below, which resolves the AI
    /// tab's configured provider at the moment of use. If that titler throws
    /// or is unavailable, `Renamer.rename` still renames the capture, under
    /// its own plain "Screenshot" fallback — never left raw.
    ///
    /// The renamed output can land back in the watcher's own scan a moment
    /// later, the same thing that already happens for every ordinary capture
    /// (see the comment on `Naming.isRawCapture` above), and that guard is
    /// what already keeps it harmless; nothing here needs to repeat it.
    private func retryInterrupted() {
        let renamer = Renamer(titler: titler, template: nameTemplate,
                              vocabulary: taggingEnabled ? vocabulary : [])
        let watchedFolder = folder
        Task { [weak self] in
            let outcomes = await Backlog.retryInFlight(in: watchedFolder, renamer: renamer)
            guard !outcomes.isEmpty else { return }
            for case .renamed(let from, let to) in outcomes {
                ShotIndex.forget(from.path)
                ShotIndex.record(to, original: from.lastPathComponent)
                Log.write("retried in-flight capture: \(from.lastPathComponent) → \(to.lastPathComponent)")
            }
            self?.loadIndex()
            self?.runSearch()
            self?.refreshBacklogCount()
        }
    }

    private func stopWatcher() {
        watcher?.stop()
        watcher = nil
    }

    // MARK: - Renaming

    private var titler: Titler {
        // The AI tab's choice, read from the stored setting at the moment of
        // use so the CLI and the app agree even mid-session. `titlerOverride`
        // wins when a test has set one.
        Self.titlerOverride ?? ShotScribeDefaults.aiProvider().makeTitler() ?? KeywordTitler()
    }

    public func rename(_ url: URL) async {
        // Before the read, not after it. The watcher reports every file that
        // lands, and that includes the one ShotScribe just renamed — which was
        // being OCR'd and sent to the titler (a model call, seconds each) only
        // for `Renamer` to refuse it as not a raw capture. That was a second
        // model call for every screenshot ever taken: 257 of them in the log
        // by 2026-09-16. Both callers only mean to rename raw captures, and
        // `Renamer` still enforces the rule, so this is a shortcut, not a
        // second source of truth.
        guard Naming.isRawCapture(at: url) else { return }
        busy = true
        defer { busy = false }
        do {
            // Compose OCR → title here (not inside Renamer) so a titler
            // failure is VISIBLE — logged and shown in the panel — instead of
            // silently falling back to the generic label.
            let path = url.path
            let lines = await Task.detached(priority: .utility) {
                Chrome.body(of: OCR.recognizeLines(atPath: path))
            }.value
            let ocr = OCR.text(of: lines)
            Log.write("new capture \(url.lastPathComponent): ocr=\(ocr.count) chars")
            var label: String?
            var tags: [String] = []
            var titled = false
            do {
                let proposed = try await titler.labelling(for: lines,
                                                          vocabulary: taggingEnabled ? vocabulary : [])
                label = proposed.title
                tags = proposed.tags
                titled = true
                Log.write("title: \(label ?? "nil")  tags: \(tags.joined(separator: ", "))")
            } catch {
                Log.write("titler FAILED: \(error)")
                lastError = "Titling failed — used the offline label. (\(error.localizedDescription))"
                // The offline label, from the text already read — here rather
                // than left to `Renamer`, which would read the picture again
                // to get it, and so the card can be told whether the name it
                // is about to show is the generic word.
                if let offline = try? await KeywordTitler().labelling(for: lines,
                                                                       vocabulary: taggingEnabled ? vocabulary : []) {
                    label = offline.title
                    tags = offline.tags
                }
            }
            let generic = LabelCleaner.clean(label ?? "") == LabelCleaner.generic
            let outcome = try await Renamer(titler: KeywordTitler(), template: nameTemplate,
                                            vocabulary: taggingEnabled ? vocabulary : [])
                .rename(fileAt: url, label: label, tags: tags, text: ocr)
            Log.write("outcome: \(outcome)")
            if case .renamed(let from, let to) = outcome {
                record(from: from.lastPathComponent, to: to.lastPathComponent)
                // Announced whether or not anything is listening. The card is
                // the only listener today and it is the app's to start — a
                // library must not put a panel on someone's screen by itself.
                justNamed = NamedCapture(url: to, from: from.lastPathComponent,
                                         to: to.lastPathComponent, at: Date(), generic: generic)
                // Index it now, not at the next sweep: a screenshot you just
                // took is exactly the one you are about to go looking for. The
                // old path is dropped so a rename does not leave a second,
                // stale entry pointing at a file that no longer exists. Then
                // the window reloads: until 2026-09-13 it kept the cache it
                // loaded at launch, so a capture named by the watcher was in
                // the index but not on screen until the next launch.
                Task.detached(priority: .utility) { [weak self] in
                    ShotIndex.forget(from.path)
                    ShotIndex.record(to, original: from.lastPathComponent)
                    await MainActor.run { self?.loadIndex(); self?.runSearch() }
                }
                if titled { lastError = nil }
            }
        } catch {
            Log.write("rename FAILED: \(error)")
            lastError = error.localizedDescription
        }
    }

    /// The panel's "Rename latest now" — newest raw capture still wearing its
    /// default name. nil-safe: does nothing when everything's already tidy.
    public func renameLatest() {
        let candidates = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? [])
            .filter(Capture.isCapture)
            .filter { Naming.isRawCapture(at: $0) }
        let newest = candidates.max {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return a < b
        }
        guard let newest else {
            lastError = "No un-renamed captures in \(folder.lastPathComponent)."
            return
        }
        Task { await rename(newest) }
    }

    // MARK: - Search

    /// How the shots are shown. Two views, because they answer the two
    /// questions worth asking: the carousel answers "which one was it" — a day
    /// at a time, on one line, where recognition beats reading — and the list
    /// answers "what did I just capture", densely, when the name is the thing
    /// being scanned. The adaptive grid stood between them and was cut on
    /// 2026-09-14; the carousel does what it did, larger.
    public enum ShotView: String, CaseIterable, Identifiable, Sendable {
        case carousel, list
        public var id: String { rawValue }
        public var label: String { self == .carousel ? "Carousel" : "List" }
        public var symbol: String { self == .carousel ? "rectangle.stack" : "list.bullet" }
    }

    @Published var shotView: ShotView = .carousel {
        didSet { Self.defaults.set(shotView.rawValue, forKey: "shotView") }
    }

    public enum ShotSort: String, CaseIterable, Identifiable, Sendable {
        case newest, oldest, nameAsc, nameDesc, tag
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .newest:   return "Newest first"
            case .oldest:   return "Oldest first"
            case .nameAsc:  return "Name A–Z"
            case .nameDesc: return "Name Z–A"
            case .tag:      return "By tag"
            }
        }
    }

    @Published var sort: ShotSort = .newest {
        didSet { Self.defaults.set(sort.rawValue, forKey: "shotSort"); loadIndex() }
    }

    // MARK: Selection

    /// Selection is modal on purpose. Checkboxes on every tile all the time turn
    /// a browser into a file manager; you are usually looking, not tidying.
    @Published var selecting = false { didSet { if !selecting { selected.removeAll() } } }

    /// Arranging the landing zone: the row shows its tally and its tiles are
    /// draggable, and none of them fires. A mode, like `selecting` — it lives
    /// here rather than in the view so it survives a redraw and can be driven
    /// from outside for an off-screen render.
    @Published public var arrangingTiles = false
    @Published var selected: Set<String> = []

    func toggleSelected(_ shot: IndexedShot) {
        if selected.contains(shot.path) { selected.remove(shot.path) }
        else { selected.insert(shot.path) }
    }
    func selectAllVisible() { selected = Set(visibleShots.map(\.path)) }

    /// Move the selected shots to the Trash — recoverable by design. A cleanup
    /// tool that deletes outright is one you stop trusting the first time it is
    /// wrong, and it would be wrong about a screenshot you had not looked at yet.
    func trashSelected() {
        trash(selected.map { URL(fileURLWithPath: $0) })
    }

    // MARK: The click

    /// What a single click on a screenshot does. Set from the landing zone:
    /// right-click a tile, "Set as the click action". Reveal in Finder is the
    /// default, as it always was.
    public enum ShotAction: String, CaseIterable, Codable, Sendable {
        case reveal, markUp, sendToAssistant, sendPicture, rebuildAsCode
        public var symbol: String {
            switch self {
            case .reveal:          return "arrow.up.forward.square"
            case .markUp:          return "pencil.tip"
            case .sendToAssistant: return "paperplane"
            case .sendPicture:     return "photo.on.rectangle"
            case .rebuildAsCode:   return "hammer"
            }
        }
    }

    static let defaultActionKey = "shotscribe.defaultAction"
    static let inspectorOpenKey = "shotscribe.inspectorOpen"
    static let captureCardKey = "shotscribe.captureCard"

    /// The last capture the watcher named, for whoever wants to show it.
    @Published public private(set) var justNamed: NamedCapture?

    /// A capture that has just **landed** — announced before the titler runs,
    /// which takes seconds. Anything showing the operator what happened should
    /// appear on this and fill in the name when `justNamed` follows.
    @Published public private(set) var justLanded: URL?

    /// Whether a card slides up when a capture is named. On by default: the
    /// rename is otherwise invisible unless the window happens to be open,
    /// which is the one moment the app has anything to say.
    @Published public var showsCaptureCard: Bool = {
        ShotScribeModel.defaults.object(forKey: ShotScribeModel.captureCardKey) == nil
            ? true : ShotScribeModel.defaults.bool(forKey: ShotScribeModel.captureCardKey)
    }() {
        didSet { Self.defaults.set(showsCaptureCard, forKey: Self.captureCardKey) }
    }

    /// The indexed shot for a path, when the sweep has caught up with it. The
    /// card asks for this so its buttons can be the real landing-zone actions
    /// rather than a second implementation of them.
    public func shot(atPath path: String) -> IndexedShot? {
        indexCache.first { $0.path == path }
    }
    static let greetedKey = "shotscribe.greeted"

    /// The inspector starts **closed**. The window's point is the screenshots,
    /// and opening onto a settings pane says the opposite — settings are what
    /// you visit, not what you arrive at. Remembered after that, so a person
    /// who works with it open keeps it open. `bool(forKey:)` is false when
    /// nothing is stored, which is the wanted default on a first run.
    @Published public var inspectorOpen: Bool = ShotScribeModel.defaults.bool(forKey: ShotScribeModel.inspectorOpenKey) {
        didSet { Self.defaults.set(inspectorOpen, forKey: Self.inspectorOpenKey) }
    }

    /// Whether this Mac has been greeted. False until the welcome is closed,
    /// so the first run says what this is and confirms the one setting that
    /// has to be right — which folder.
    @Published public var greeted: Bool = ShotScribeModel.defaults.bool(forKey: ShotScribeModel.greetedKey) {
        didSet { Self.defaults.set(greeted, forKey: Self.greetedKey) }
    }

    /// Which tiles the landing zone shows, in what order, and the tally of how
    /// often each has been used. Arranged by right-clicking the row itself.
    @Published public var landingZone: LandingZone = ShotScribeDefaults.landingZone() {
        didSet { ShotScribeDefaults.setLandingZone(landingZone) }
    }

    /// The tile's own name, as the row and its menus say it.
    public func name(of tile: LandingZone.Tile) -> String {
        switch tile {
        case .reveal:    return "Reveal in Finder"
        case .markUp:    return "Edit with ShotScribe"
        case .share:     return "Share"
        case .sendTo:    return "Send to \(assistantName)"
        case .editTitle: return "Edit title"
        case .fileAs:    return "Tag"
        }
    }

    /// The click action a tile can become, for the four that are one. Share
    /// unfolds, Edit title types, File as opens a menu — none of the three is
    /// something a plain click could stand for.
    public static func action(for tile: LandingZone.Tile) -> ShotAction? {
        switch tile {
        case .reveal:    return .reveal
        case .markUp:    return .markUp
        case .sendTo:    return .sendToAssistant
        case .share, .editTitle, .fileAs: return nil
        }
    }

    /// Bumped when something asks for the **File** tab — adding a word to the
    /// vocabulary is the one thing a tag menu cannot do for itself, so "+ New
    /// Tag" sends you where the list is edited.
    @Published public private(set) var fileTabRequests = 0
    public func askForFileTab() { fileTabRequests += 1 }

    /// One more use of a tile, counted wherever it was reached.
    public func note(_ tile: LandingZone.Tile) { landingZone.note(tile) }

    @discardableResult
    public func setTileHidden(_ tile: LandingZone.Tile, _ away: Bool) -> Bool {
        landingZone.setHidden(tile, away)
    }

    public func moveTile(_ tile: LandingZone.Tile, onto other: LandingZone.Tile) {
        landingZone.move(tile, onto: other)
    }

    public func resetLandingZone() { landingZone.reset() }

    @Published public var defaultAction: ShotAction = {
        ShotScribeModel.defaults.string(forKey: ShotScribeModel.defaultActionKey).flatMap(ShotAction.init(rawValue:)) ?? .reveal
    }() {
        didSet { Self.defaults.set(defaultAction.rawValue, forKey: Self.defaultActionKey) }
    }

    /// The action's name, with the assistant's.
    public func title(of action: ShotAction) -> String {
        switch action {
        case .reveal:          return "Reveal in Finder"
        // Was "Mark up in Preview". Josh, 2026-09-16: "Preview is MacOS native,
        // serves one purpose, we can do that purpose better" — the stored
        // value stays `markUp`, so a click default set before keeps working
        // and now lands in ShotScribe's own editor.
        case .markUp:          return "Edit with ShotScribe"
        // Two destinations, named by what they can see: a local session takes
        // a path; a chat in the cloud takes the picture (2026-09-22).
        case .sendToAssistant: return aiProvider.kind == .claude ? "Send to Claude Code" : "Send to \(assistantName)"
        case .sendPicture:     return "Send the picture to a chat"
        case .rebuildAsCode:   return "Rebuild as code"
        }
    }

    public func perform(_ action: ShotAction, on shot: IndexedShot) {
        switch action {
        case .reveal:          reveal(shot)
        case .markUp:          markUp(shot)
        case .sendToAssistant: sendToAssistant(shot)
        case .sendPicture:     sendPicture(shot)
        case .rebuildAsCode:   copyCodeBrief(for: shot)
        }
    }

    /// What a click does when nothing else (selection) claims it.
    public func click(_ shot: IndexedShot) {
        selecting ? toggleSelected(shot) : perform(defaultAction, on: shot)
    }

    /// The Keep tab's choice: a discarded capture goes to the Trash (Finder's
    /// Put Back undoes it) or is deleted outright. The bins and clean-up obey
    /// the same setting; an archive folder counts as the Trash for a single
    /// shot, since filing one shot away is not what a bin means.
    public var deletesForGood: Bool { keepPolicy.destination == .delete }

    func trash(_ shot: IndexedShot) { trash([shot.url]) }

    /// A whole day at once. One call rather than a loop, so the Keep tab's
    /// choice is applied once and the index is reloaded once — a loop over
    /// `trash(_:)` would sweep the folder for every shot in the day.
    func trash(_ shots: [IndexedShot]) { trash(shots.map(\.url)) }

    private func trash(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if deletesForGood {
            var failure: String?
            // "For good" includes the editable copy ShotScribe kept. A capture
            // moved to the Trash keeps it, so Put Back still leaves it editable.
            for u in urls { EditStore.remove(for: u) }
            for u in urls {
                do { try FileManager.default.removeItem(at: u) } catch { failure = error.localizedDescription }
            }
            Log.write("deleted for good: \(urls.count) file(s)")
            lastError = failure.map { "Couldn't delete: \($0)" }
            for u in urls { ShotIndex.forget(u.path) }
            selected.removeAll(); selecting = false
            loadIndex(); runSearch()
            return
        }
        NSWorkspace.shared.recycle(urls) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.lastError = "Couldn't move to Trash: \(error.localizedDescription)" }
                // Drop them from the index either way: anything that did move is
                // gone, and a reindex will restore anything that did not.
                for u in urls { ShotIndex.forget(u.path) }
                self.selected.removeAll()
                self.selecting = false
                self.loadIndex()
                self.runSearch()
            }
        }
    }

    @Published var query: String = ""
    @Published private(set) var hits: [SearchHit] = []
    @Published private(set) var indexing = false
    @Published private(set) var indexProgress: (Int, Int)?

    /// The index is the only durable record of what a screenshot SAID. The
    /// rename history is capped and holds filenames, so search reads the index
    /// and the index reads the folder.
    var indexedCount: Int { indexCache.count }

    /// The index, held in memory. Every keystroke reloading a 173KB file from
    /// disk is the kind of thing that feels fine at 125 screenshots and terrible
    /// at 2,000.
    @Published private(set) var indexCache: [IndexedShot] = []

    func loadIndex() {
        indexCache = Self.sorted(Array(ShotIndex.load().shots.values), by: sort)
    }

    static func sorted(_ shots: [IndexedShot], by sort: ShotSort) -> [IndexedShot] {
        switch sort {
        case .newest:   return shots.sorted { $0.captured > $1.captured }
        case .oldest:   return shots.sorted { $0.captured < $1.captured }
        case .nameAsc:  return shots.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDesc: return shots.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .tag:
            // First tag A–Z, newest first within one; the untagged last.
            return shots.sorted { a, b in
                let ta = a.tags?.first?.lowercased() ?? "\u{10FFFF}", tb = b.tags?.first?.lowercased() ?? "\u{10FFFF}"
                return ta != tb ? ta < tb : a.captured > b.captured
            }
        }
    }

    // MARK: Tags as a filter

    /// The tags being isolated; every shot shown carries all of them.
    @Published var tagFilter: Set<String> = []

    public struct TagCount: Identifiable, Equatable {
        public var id: String { tag }
        public let tag: String
        public let count: Int
    }

    /// Every tag in use across the corpus, most used first — the filing
    /// system's own table of contents.
    var tagCounts: [TagCount] {
        var counts: [String: Int] = [:]
        for shot in indexCache { for t in Set((shot.tags ?? []).map { $0.lowercased() }) { counts[t, default: 0] += 1 } }
        return counts.map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    func toggleTag(_ tag: String) {
        let t = tag.lowercased()
        if tagFilter.contains(t) { tagFilter.remove(t) } else { tagFilter.insert(t) }
    }

    func clearTagFilter() { tagFilter.removeAll() }

    /// What the views show: search hits when searching, the whole corpus
    /// otherwise. The index doubles as the browser — it is the only thing that
    /// knows every shot, since the rename history is capped.
    var visibleShots: [IndexedShot] {
        let base: [IndexedShot] = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? indexCache
            // Search results are ranked by relevance; re-sorting them by date
            // would throw away the ranking that made them results.
            : (sort == .newest ? hits.map(\.shot) : Self.sorted(hits.map(\.shot), by: sort))
        guard !tagFilter.isEmpty else { return base }
        return base.filter { shot in
            let have = Set((shot.tags ?? []).map { $0.lowercased() })
            return tagFilter.allSatisfy { have.contains($0) }
        }
    }

    /// Show everything filed the same way: isolate the tag. Until 2026-09-13
    /// this ran a text search for the word, which also matched body text and
    /// could not be combined; the strip above the grid is the same filter with
    /// every tag in use on it.
    func filter(tag: String) {
        tagFilter = [tag.lowercased()]
    }

    func snippet(for shot: IndexedShot) -> String? {
        hits.first { $0.shot.path == shot.path }?.snippet
    }

    func runSearch() {
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { hits = []; return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let found = ShotIndex.search(q)
            await MainActor.run { self?.hits = found }
        }
    }

    /// Read every screenshot in the watched folder into the index. Runs off the
    /// main thread — accurate OCR over a few hundred files is seconds, not
    /// milliseconds.
    /// Sweep the watch folder into the search index.
    ///
    /// **This existed for weeks with no caller.** The browser therefore only
    /// ever contained screenshots this app had itself renamed — every
    /// pre-existing capture in a chosen folder was invisible to search, and
    /// nothing said so. Called now on launch, on a folder change, and by hand.
    ///
    /// `force` re-reads text for files already indexed; without it the sweep
    /// skips anything whose size has not changed.
    func rebuildIndex(force: Bool = false) {
        guard !indexing else { return }
        indexing = true
        let folder = self.folder
        Task.detached(priority: .utility) { [weak self] in
            ShotIndex.reindex(folder: folder, force: force) { i, n in
                Task { @MainActor in self?.indexProgress = (i, n) }
            }
            await MainActor.run {
                self?.indexing = false
                self?.indexProgress = nil
                self?.loadIndex()
                self?.runSearch()
            }
        }
    }

    /// The shot in Preview, for the pencil: macOS's own markup, one click from
    /// the landing zone. Josh's habit (2026-09-13) — annotate before sending.
    /// **Edit the Image** — ShotScribe's own editor.
    func markUp(_ shot: IndexedShot) {
        note(.markUp)
        editFile(shot.url)
    }

    /// Preview, for anything the editor does not do. Nested under Edit the
    /// Image rather than standing beside it.
    func openInPreview(_ shot: IndexedShot) { openInPreview(shot.url) }

    public func openInPreview(_ url: URL) {
        let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
        NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Task { @MainActor [weak self] in self?.lastError = "Couldn’t open in Preview: \(error.localizedDescription)" } }
        }
    }

    func reveal(_ shot: IndexedShot) {
        note(.reveal)
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
    }
    func reveal(_ hit: SearchHit) { reveal(hit.shot) }

    private func record(from: String, to: String) {
        events.insert(RenameEvent(date: Date(), from: from, to: to), at: 0)
        if events.count > Self.maxEvents { events.removeLast(events.count - Self.maxEvents) }
        if let data = try? JSONEncoder().encode(events) {
            Self.defaults.set(data, forKey: Self.eventsKey)
        }
    }
}
