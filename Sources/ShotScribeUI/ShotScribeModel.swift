import Foundation
import SwiftUI
import AppKit
import ServiceManagement
import ShotScribeCore

/// One rename the app performed — shown in the panel's history.
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
    static let useClaudeKey = "shotscribe.useClaude"
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

    /// Title via the local `claude` CLI (sharper labels) vs the offline
    /// keyword titler. Only meaningful when `claudeAvailable`.
    /// What `~/.config/llm/provider.json` says, if anything. Read at launch for
    /// display; the titler re-reads at the moment of use.
    @Published public private(set) var llmPreference = LLMPreference.load()

    /// Non-nil when the machine's choice is one ShotScribe cannot honour.
    public var llmMismatchNote: String? { llmPreference.mismatchNote }

    public func refreshLLMPreference() { llmPreference = LLMPreference.load() }

    @Published public var useClaude: Bool {
        didSet { Self.defaults.set(useClaude, forKey: Self.useClaudeKey) }
    }

    @Published public private(set) var events: [RenameEvent] = []
    @Published public private(set) var lastError: String?
    /// True while a rename (OCR + titling) is in flight — the panel shows a spinner.
    @Published public private(set) var busy = false

    public let claudeAvailable = ClaudeTitler.isAvailable()
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

    /// Whether renames file captures at all. Off leaves the vocabulary intact
    /// and stops new renames being tagged; tags already on files stay.
    @Published public private(set) var taggingEnabled: Bool = ShotScribeDefaults.taggingEnabled()

    public func setTaggingEnabled(_ on: Bool) {
        ShotScribeDefaults.setTaggingEnabled(on)
        taggingEnabled = on
    }

    /// File a shot that is already named — the only way to reach an older
    /// capture, since the vocabulary otherwise only applies at rename time.
    public func tag(_ shot: IndexedShot, with tag: String) {
        guard Tagging.add(Tagging.accepted([tag], vocabulary: vocabulary), to: shot.url) else {
            lastError = "Couldn't tag \(shot.name)."
            return
        }
        ShotIndex.record(shot.url, original: shot.original)
        loadIndex()
        runSearch()
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
        let ud = Self.defaults
        watching = ud.object(forKey: Self.watchingKey) == nil
            ? true : ud.bool(forKey: Self.watchingKey)
        useClaude = ud.object(forKey: Self.useClaudeKey) == nil
            ? true : ud.bool(forKey: Self.useClaudeKey)
        if let data = ud.data(forKey: Self.eventsKey),
           let saved = try? JSONDecoder().decode([RenameEvent].self, from: data) {
            events = saved
        }
        if let raw = ud.string(forKey: "shotView"), let v = ShotView(rawValue: raw) {
            shotView = v
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
                await self?.rename(url)
            }
        }
        if w.start() {
            watcher = w
        } else {
            lastError = "Can't watch \(folder.path)"
            watching = false
        }
    }

    private func stopWatcher() {
        watcher?.stop()
        watcher = nil
    }

    // MARK: - Renaming

    private var titler: Titler {
        // The machine's provider choice gates this, not just ShotScribe's own
        // toggle. Read fresh each time rather than cached at launch: whatever
        // offers the picker may rewrite the file while ShotScribe is running.
        (useClaude && claudeAvailable && LLMPreference.load().provider.usableHere)
            ? ClaudeTitler() : KeywordTitler()
    }

    public func rename(_ url: URL) async {
        busy = true
        defer { busy = false }
        do {
            // Compose OCR → title here (not inside Renamer) so a titler
            // failure is VISIBLE — logged and shown in the panel — instead of
            // silently falling back to the generic label.
            let path = url.path
            let ocr = await Task.detached(priority: .utility) {
                OCR.recognizeText(atPath: path)
            }.value
            Log.write("new capture \(url.lastPathComponent): ocr=\(ocr.count) chars")
            var label: String?
            var tags: [String] = []
            do {
                let proposed = try await titler.labelling(forOCRText: ocr,
                                                          vocabulary: taggingEnabled ? vocabulary : [])
                label = proposed.title
                tags = proposed.tags
                Log.write("title: \(label ?? "nil")  tags: \(tags.joined(separator: ", "))")
            } catch {
                Log.write("titler FAILED: \(error)")
                lastError = "Titling failed — used the offline label. (\(error.localizedDescription))"
            }
            // label == nil → Renamer falls back to its own titler (offline).
            let outcome = try await Renamer(titler: KeywordTitler(), template: nameTemplate,
                                            vocabulary: taggingEnabled ? vocabulary : [])
                .rename(fileAt: url, label: label, tags: tags)
            Log.write("outcome: \(outcome)")
            if case .renamed(let from, let to) = outcome {
                record(from: from.lastPathComponent, to: to.lastPathComponent)
                // Index it now, not at the next sweep: a screenshot you just
                // took is exactly the one you are about to go looking for. The
                // old path is dropped so a rename does not leave a second,
                // stale entry pointing at a file that no longer exists.
                Task.detached(priority: .utility) {
                    ShotIndex.forget(from.path)
                    ShotIndex.record(to, original: from.lastPathComponent)
                }
                if label != nil { lastError = nil }
            }
        } catch {
            Log.write("rename FAILED: \(error)")
            lastError = error.localizedDescription
        }
    }

    /// The panel's "Rename latest now" — newest raw capture still wearing its
    /// default name. nil-safe: does nothing when everything's already tidy.
    public func renameLatest() {
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]
        let candidates = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? [])
            .filter { imageExts.contains($0.pathExtension.lowercased()) }
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

    /// How the shots are shown. Two views because they answer different
    /// questions: the list answers "what did I just capture", the tiles answer
    /// "which one was it" — and for a screenshot, recognition beats reading.
    public enum ShotView: String, CaseIterable, Identifiable, Sendable {
        case list, tiles
        public var id: String { rawValue }
        public var label: String { self == .list ? "List" : "Tiles" }
        public var symbol: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    }

    @Published var shotView: ShotView = .tiles {
        didSet { Self.defaults.set(shotView.rawValue, forKey: "shotView") }
    }

    public enum ShotSort: String, CaseIterable, Identifiable, Sendable {
        case newest, oldest, nameAsc, nameDesc
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .newest:   return "Newest first"
            case .oldest:   return "Oldest first"
            case .nameAsc:  return "Name A–Z"
            case .nameDesc: return "Name Z–A"
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

    func trash(_ shot: IndexedShot) { trash([shot.url]) }

    private func trash(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
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
        }
    }

    /// What the views show: search hits when searching, the whole corpus
    /// otherwise. The index doubles as the browser — it is the only thing that
    /// knows every shot, since the rename history is capped.
    var visibleShots: [IndexedShot] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? indexCache
            // Search results are ranked by relevance; re-sorting them by date
            // would throw away the ranking that made them results.
            : (sort == .newest ? hits.map(\.shot) : Self.sorted(hits.map(\.shot), by: sort))
    }

    /// Show everything filed the same way. Tags are indexed, so a filter is just
    /// a search — no second code path, and the field shows what is being asked.
    func filter(tag: String) {
        query = tag
        runSearch()
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

    func reveal(_ shot: IndexedShot) {
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
