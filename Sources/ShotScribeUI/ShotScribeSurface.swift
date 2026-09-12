import SwiftUI
import ShotScribeCore
import UniformTypeIdentifiers
import AppKit

/// How much room the surface has, and therefore which controls make sense.
public enum ShotScribeChrome {
    /// A 340pt menu bar popover: compact, and the place where app-level
    /// controls (launch at login, Quit) belong.
    case menuBar
    /// A roomy detail pane inside some other window. App-level controls are
    /// omitted — `SMAppService.mainApp` would register *that* host at login,
    /// and "Quit" would quit it.
    case hosted
}

/// **ShotScribe's face.** Watch toggle, titler preference, rename-latest, and
/// recent history over a `ShotScribeModel`.
///
/// Self-contained: no arguments, owns its state, one line to mount. Per the
/// repo's doctrine this package has no idea what's hosting it and must never
/// grow one.
public struct ShotScribeSurface: View {
    @StateObject private var model = ShotScribeModel()
    private let chrome: ShotScribeChrome

    public init(chrome: ShotScribeChrome = .hosted) {
        self.chrome = chrome
    }

    public var body: some View {
        ShotScribeView(model: model, chrome: chrome)
    }
}

/// The same surface driven by a model the host already owns — the menu bar app
/// uses it so its welcome window and its panel share one watcher. Note the
/// `@ObservedObject`: a stored `let` here means the view never redraws when a
/// rename lands.
public struct ShotScribeView: View {
    @ObservedObject var model: ShotScribeModel
    let chrome: ShotScribeChrome
    @State private var folderTargeted = false
    /// Drafts, not bindings to the model: half-typed text is invalid text, and
    /// a name template or a vocabulary is only worth saving once it is finished.
    @State private var layoutDraft = ""
    @State private var vocabularyDraft = ""
    /// Supplied by a host that has a window to show — the menu bar app. The
    /// popover cannot open one itself: this package has no idea what is hosting
    /// it, and must never grow one.
    private let onOpenWindow: (() -> Void)?

    public init(model: ShotScribeModel, chrome: ShotScribeChrome = .hosted,
                onOpenWindow: (() -> Void)? = nil) {
        self.onOpenWindow = onOpenWindow
        self.model = model
        self.chrome = chrome
    }

    public var body: some View {
        switch chrome {
        case .menuBar: panel
        case .hosted:  pane
        }
    }

    // MARK: Menu bar popover

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            folderRow
            watchToggle
            claudeToggle
            Toggle(isOn: Binding(get: { model.launchAtLogin },
                                 set: { model.setLaunchAtLogin($0) })) {
                Text("Launch at login")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            renameAction
            errorLine
            if !model.events.isEmpty {
                Divider()
                historyList(limit: 6)
            }
            Divider()
            HStack {
                Button("Open folder") { NSWorkspace.shared.open(model.folder) }
                    .buttonStyle(.link).font(.caption)
                if let onOpenWindow {
                    Spacer()
                    Button("Open ShotScribe") { onOpenWindow() }
                        .buttonStyle(.link).font(.caption)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    // MARK: Hosted detail pane

    private var pane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // The header reads as a BAND, not as a stray line: it runs the
                // whole width the pane is given and closes with a rule at the
                // far edge. Everything below it already stretched; the top did
                // not, so the widest part of the surface was also the emptiest.
                VStack(alignment: .leading, spacing: 9) {
                    header
                    Divider()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.otherInstanceRunning { standDownBanner }
                // One column, in the order you read it: where shots land, what
                // ShotScribe does to them, then how to find one.
                folderRow
                actionsBlock
                namingBlock
                filingBlock
                keepBlock
                searchField
                errorLine
                shotsBlock
                if model.visibleShots.isEmpty && model.events.isEmpty {
                    Text("Nothing renamed yet. New captures that land in the folder above get a name that says what they show.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    historyList(limit: 20)
                }
            }
            .padding(22)
            // The controls stay in a readable column; the SHOTS get the window.
            // This pane used to cap everything at 620pt, so on a 1200pt window
            // the scrollbar sat at the pane edge while the content stopped well
            // short of it — the whole surface read as a narrow page floating in
            // dead space.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// What ShotScribe does to what lands in the folder.
    private var actionsBlock: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                watchToggle
                claudeToggle
                Divider()
                HStack {
                    renameAction
                    Spacer()
                    Button("Open folder") { NSWorkspace.shared.open(model.folder) }
                        .controlSize(.small)
                }
            }
            .padding(4)
        }
    }

    /// One field. It searches what the screenshots SAY, because ShotScribe
    /// already read every one of them to name it and the text is kept.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find a screenshot", text: $model.query)
                .textFieldStyle(.plain)
                .font(.body)
                .onSubmit { model.runSearch() }
                .onChange(of: model.query) { _ in model.runSearch() }
            if !model.query.isEmpty {
                Button { model.query = ""; model.runSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quinary))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(.separator, lineWidth: 1))
    }

    /// The shots themselves, in whichever view is chosen.
    ///
    /// Both views read `visibleShots` — search hits when searching, the whole
    /// indexed corpus otherwise — so the index doubles as the browser. The
    /// rename history cannot do that job: it is capped and holds no paths.
    @ViewBuilder
    private var shotsBlock: some View {
        if !model.visibleShots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(model.query.isEmpty
                         ? "\(model.visibleShots.count) screenshots"
                         : "\(model.visibleShots.count) match\(model.visibleShots.count == 1 ? "" : "es")")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)

                    if model.selecting {
                        Text("· \(model.selected.count) selected")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("All") { model.selectAllVisible() }.controlSize(.small)
                        Button(role: .destructive) {
                            model.trashSelected()
                        } label: {
                            Label("Move to Trash", systemImage: "trash")
                        }
                        .controlSize(.small)
                        .disabled(model.selected.isEmpty)
                    }

                    Spacer()

                    Button {
                        model.selecting.toggle()
                    } label: {
                        Image(systemName: model.selecting
                              ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.selecting ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .help(model.selecting ? "Done selecting" : "Select screenshots")

                    Picker("", selection: $model.sort) {
                        ForEach(ShotScribeModel.ShotSort.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 132)
                    .help("Sort")

                    Picker("", selection: $model.shotView) {
                        ForEach(ShotScribeModel.ShotView.allCases) { v in
                            Image(systemName: v.symbol).tag(v).help(v.label)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                switch model.shotView {
                case .list:  shotsList
                case .tiles: shotsTiles
                }
            }
        }
    }

    private var shotsList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(model.visibleShots.prefix(300)) { shot in
                Button {
                    model.selecting ? model.toggleSelected(shot) : model.reveal(shot)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if model.selecting {
                            Image(systemName: model.selected.contains(shot.path)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.selected.contains(shot.path)
                                                 ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        }
                        Text(shot.name).font(.callout.weight(.medium))
                            .lineLimit(1).truncationMode(.middle)
                            .frame(minWidth: 180, alignment: .leading)
                        if let snip = model.snippet(for: shot), !snip.isEmpty {
                            Text(snip).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                        }
                        Spacer(minLength: 8)
                        tagChips(shot)
                        Text(shot.captured, format: .dateTime.year().month().day())
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(shot.path)
                Divider()
            }
        }
    }

    private var shotsTiles: some View {
        // Adaptive columns rather than a fixed count: the pane may be as narrow
        // as 824pt when hosted, or whatever the user drags it to standalone,
        // and a fixed grid wastes the space this change was meant to reclaim.
        //
        // Bursts fold into one tile when the Keep policy says so; a folded
        // session opens out in place, and its first tile carries the way back.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 12)],
                  alignment: .leading, spacing: 12) {
            ForEach(model.sessions.prefix(300)) { s in
                if s.isBurst && !model.isExpanded(s) {
                    sessionTile(s)
                } else {
                    ForEach(s.shots) { shot in
                        tile(shot, in: s.isBurst ? s : nil)
                    }
                }
            }
        }
    }

    /// One screenshot. `session` is set when the tile is part of an opened-out
    /// burst; its first tile then shows the collapse badge.
    private func tile(_ shot: IndexedShot, in session: Session?) -> some View {
        let picked = model.selected.contains(shot.path)
        let leadsSession = session?.shots.first?.path == shot.path
        return Button {
            model.selecting ? model.toggleSelected(shot) : model.reveal(shot)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Thumbnail(path: shot.path)
                    .overlay(alignment: .topLeading) {
                        if model.selecting {
                            Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 17))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, picked ? AnyShapeStyle(.tint) : AnyShapeStyle(.black.opacity(0.35)))
                                .padding(7)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let session, leadsSession {
                            Button { model.toggleExpanded(session) } label: {
                                Label("\(session.count)", systemImage: "chevron.up")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(.black.opacity(0.55), in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .padding(7)
                            .help("Fold these \(session.count) back into one tile")
                        }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(shot.name).font(.caption.weight(.medium))
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 5) {
                        Text(shot.captured, format: .dateTime.year().month().day())
                            .font(.caption2).foregroundStyle(.secondary)
                        tagChips(shot)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(picked ? AnyShapeStyle(.tint)
                              : session != nil ? AnyShapeStyle(ShotPalette.accent.opacity(0.45))
                              : AnyShapeStyle(.separator),
                              lineWidth: picked ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shot.path)
        .contextMenu {
            Button("Reveal in Finder") { model.reveal(shot) }
            // The vocabulary otherwise only applies at rename time, which leaves
            // every capture from before today reachable only through Finder.
            Menu("File as") {
                ForEach(model.vocabulary, id: \.self) { tag in
                    Button(tag) { model.tag(shot, with: tag) }
                        .disabled((shot.tags ?? []).contains { $0.caseInsensitiveCompare(tag) == .orderedSame })
                }
            }
            if shot.original != nil, !model.otherInstanceRunning {
                Button("Restore original name") { model.undo(shot) }
            }
            Divider()
            Button("Move to Trash", role: .destructive) { model.trash(shot) }
        }
    }

    /// The filing, on the shot. Tapping one searches for it — the shortest path
    /// from "this one" to "everything like this one".
    @ViewBuilder
    private func tagChips(_ shot: IndexedShot) -> some View {
        ForEach(shot.tags ?? [], id: \.self) { tag in
            Button { model.filter(tag: tag) } label: {
                Text(tag)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(ShotPalette.accent.opacity(0.16), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Find everything tagged \(tag)")
        }
    }

    /// A folded burst: the last shot stands for the whole, with the count on
    /// its shoulder and a second edge behind so it reads as a stack.
    private func sessionTile(_ s: Session) -> some View {
        Button { model.toggleExpanded(s) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Thumbnail(path: (s.representative ?? s.shots[0]).path)
                    .overlay(alignment: .topTrailing) {
                        Label("\(s.count)", systemImage: "square.stack")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(7)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.title).font(.caption.weight(.medium))
                        .lineLimit(1).truncationMode(.middle)
                    sessionRange(s).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary).offset(x: 4, y: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(s.count) captures within \(model.keepPolicy.sessionGapMinutes) minutes of each other — click to open them out")
    }

    private func sessionRange(_ s: Session) -> Text {
        Text("\(s.count) shots · ")
            + Text(s.start, format: .dateTime.hour().minute())
            + Text("–")
            + Text(s.end, format: .dateTime.hour().minute())
    }

    // MARK: Name

    /// A style change applies at once — a picker cannot spell an unusable name,
    /// and if it somehow does, the store refuses it and says so in the error
    /// line. The layout is different: half-typed text is invalid text, so it
    /// waits for Return or "Use".
    private func naming<T>(_ path: WritableKeyPath<NameTemplate, T>) -> Binding<T> {
        Binding(get: { model.nameTemplate[keyPath: path] },
                set: {
                    var edited = model.nameTemplate
                    edited[keyPath: path] = $0
                    model.setNameTemplate(edited)
                })
    }

    /// What the layout field would produce, or why it cannot be used. Judged on
    /// the draft, so the answer is there before anything is saved.
    private var draftTemplate: NameTemplate {
        var draft = model.nameTemplate
        draft.layout = layoutDraft
        return draft
    }

    private var namingBlock: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Name").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        TextField("{date} {time} {title}", text: $layoutDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())
                            .onSubmit { applyLayout() }
                        Button("Use") { applyLayout() }
                            .disabled(layoutDraft == model.nameTemplate.layout)
                    }
                    if let problem = Naming.validate(draftTemplate) {
                        Label(problem.why, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(Naming.sampleFilename(draftTemplate) ?? "—")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Text("Tokens: \(NameTemplate.tokens.joined(separator: "  ")). Everything else is literal, so the separators are yours.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                keepRow("Date", "Date first is what keeps a name-sorted folder in order.") {
                    Picker("", selection: naming(\.dateStyle)) {
                        Text("2026-08-11").tag(NameTemplate.DateStyle.iso)
                        Text("08-11-2026").tag(NameTemplate.DateStyle.us)
                        Text("20260811").tag(NameTemplate.DateStyle.compact)
                    }
                    .labelsHidden().frame(width: 116)
                }
                keepRow("Time", "The clock, as the name spells it.") {
                    Picker("", selection: naming(\.timeStyle)) {
                        Text("1541").tag(NameTemplate.TimeStyle.hhmm)
                        Text("15-41").tag(NameTemplate.TimeStyle.dashed)
                        Text("3.41 PM").tag(NameTemplate.TimeStyle.twelveHour)
                    }
                    .labelsHidden().frame(width: 116)
                }
                keepRow("Title", "How the words themselves are joined.") {
                    Picker("", selection: naming(\.titleStyle)) {
                        Text("As read").tag(NameTemplate.TitleStyle.asIs)
                        Text("kebab").tag(NameTemplate.TitleStyle.kebab)
                        Text("snake").tag(NameTemplate.TitleStyle.snake)
                    }
                    .labelsHidden().frame(width: 116)
                }
                keepRow("Words kept", "A longer summary is the titler's job, not the name's.") {
                    Picker("", selection: naming(\.titleWords)) {
                        ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden().frame(width: 60)
                }
                Text("A new template applies to captures from here on. Nothing already named is re-spelled.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(4)
        }
        .onAppear { layoutDraft = model.nameTemplate.layout }
        .onChange(of: model.nameTemplate.layout) { layoutDraft = $0 }
    }

    private func applyLayout() {
        model.setNameTemplate(draftTemplate)
    }

    // MARK: File

    private var filingBlock: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("File").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("A renamed capture is filed under up to \(Tagging.maxPerShot) of these, as Finder tags — so Finder and Spotlight find it whether or not ShotScribe is running. A tag outside the list is never used, however it was suggested.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TextField("terminal, code, error", text: $vocabularyDraft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .lineLimit(1...3)
                        .onSubmit { applyVocabulary() }
                    Button("Use") { applyVocabulary() }
                        .disabled(Tagging.normalised(splitVocabulary(vocabularyDraft)) == model.vocabulary)
                }
                HStack(spacing: 10) {
                    Text("\(model.vocabulary.count) tags, \(Tagging.maxVocabulary) at most")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button("Shipped list") {
                        model.setVocabulary([])
                        vocabularyDraft = model.vocabulary.joined(separator: ", ")
                    }
                    .font(.caption2)
                    .disabled(model.vocabulary == Tagging.defaultVocabulary)
                }
            }
            .padding(4)
        }
        .onAppear { vocabularyDraft = model.vocabulary.joined(separator: ", ") }
        .onChange(of: model.vocabulary) { vocabularyDraft = $0.joined(separator: ", ") }
    }

    private func splitVocabulary(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "\n" }).map(String.init)
    }

    private func applyVocabulary() {
        model.setVocabulary(splitVocabulary(vocabularyDraft))
    }

    // MARK: Keep

    private func keep<T>(_ path: WritableKeyPath<KeepPolicy, T>) -> Binding<T> {
        Binding(get: { model.keepPolicy[keyPath: path] },
                set: { model.keepPolicy[keyPath: path] = $0 })
    }

    /// What is kept — the fourth question, beside where / when / how.
    private var keepBlock: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Keep").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                keepRow("Group bursts into sessions",
                        "Captures within a few minutes of each other fold into one tile.") {
                    Picker("", selection: keep(\.sessionGapMinutes)) {
                        Text("Off").tag(0)
                        ForEach([1, 3, 5, 10, 15], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .labelsHidden().frame(width: 84)
                }
                Divider()
                Toggle(isOn: keep(\.flagDuplicates)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Flag duplicates")
                        Text("A later capture whose text matches an earlier one. Thin or empty text never counts.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch).controlSize(.small)
                keepRow("Flag older than", "Captures past this age are offered for clean-up.") {
                    Picker("", selection: olderThanBinding) {
                        Text("Never").tag(0)
                        ForEach([30, 90, 180, 365], id: \.self) { Text("\($0) days").tag($0) }
                    }
                    .labelsHidden().frame(width: 96)
                }
                keepRow("Flagged captures go to", destinationDetail) { destinationPicker }
                Divider()
                HStack(spacing: 10) {
                    Button {
                        model.previewCleanup()
                    } label: {
                        Label("Preview clean-up", systemImage: "sparkles")
                    }
                    .disabled(model.indexedCount == 0 || model.cleaning)
                    Text("Nothing moves until you confirm the list.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
                if let plan = model.cleanupPlan { cleanupPreview(plan) }
            }
            .padding(4)
        }
    }

    private func keepRow<Control: View>(_ title: String, _ detail: String,
                                        @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control()
        }
    }

    private var olderThanBinding: Binding<Int> {
        Binding(get: { model.keepPolicy.olderThanDays ?? 0 },
                set: { model.keepPolicy.olderThanDays = $0 == 0 ? nil : $0 })
    }

    private var destinationDetail: String {
        switch model.keepPolicy.destination {
        case .trash:             return "The Trash — recoverable from Finder. Nothing is ever deleted outright."
        case .archive(let path): return (path as NSString).abbreviatingWithTildeInPath
        }
    }

    private var destinationPicker: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding<Bool>(
                get: { if case .archive = model.keepPolicy.destination { return true } else { return false } },
                set: { archive in
                    if archive { model.chooseArchiveFolder() }
                    else { model.keepPolicy.destination = .trash }
                })) {
                Text("Trash").tag(false)
                Text("Archive folder").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            if case .archive(let path) = model.keepPolicy.destination {
                Button((path as NSString).lastPathComponent + "…") { model.chooseArchiveFolder() }
                    .controlSize(.small)
                    .help(path)
            }
        }
    }

    /// The list, before anything moves. Every row says why it is there.
    private func cleanupPreview(_ plan: Cleanup.Plan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if plan.isEmpty {
                HStack {
                    Text("Nothing to clean up — no duplicates, nothing past the age you set.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { model.cancelCleanup() }.controlSize(.small)
                }
            } else {
                Text("\(plan.moves.count) screenshot\(plan.moves.count == 1 ? "" : "s") in \(model.folder.lastPathComponent) would move to \(plan.destination.label): \(plan.duplicates) duplicate\(plan.duplicates == 1 ? "" : "s"), \(plan.stale) older than you keep.")
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                // Every row, scrolling past a screenful: a list you confirm is
                // a list you can read to the end.
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(plan.moves) { m in
                            HStack(spacing: 6) {
                                Text(m.shot.name).font(.caption2).lineLimit(1).truncationMode(.middle)
                                Text("— \(m.why)").font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.tail)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        model.applyCleanup()
                    } label: {
                        Label("Move \(plan.moves.count) to \(plan.destination.label)", systemImage: "arrow.right.circle")
                    }
                    .controlSize(.small)
                    .disabled(model.cleaning)
                    Button("Cancel") { model.cancelCleanup() }.controlSize(.small)
                        .disabled(model.cleaning)   // the moves are under way; "cancelled" would be a lie
                    if model.cleaning { ProgressView().controlSize(.small) }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ShotPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// The one thing a hosted copy must say out loud: it is deliberately not
    /// watching, and why.
    private var standDownBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("ShotScribe.app is running").font(.callout.weight(.semibold))
                Text("It already watches this folder. Two watchers would race to rename the same capture, so this copy is standing down — quit ShotScribe.app and it picks up automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Shared pieces

    /// **What ShotScribe is doing — not where the folder is.**
    ///
    /// The header used to lead with the watch folder's full path, so the first
    /// thing anyone read on this surface was `/Users/…/Pictures/…`: the answer
    /// to a question you ask once, parked in the spot you look at every time.
    /// The path did not go away — it moved to the drop zone's hover, where it
    /// is attached to the thing it actually describes.
    ///
    /// What the top of a watcher owes you instead is whether it is *on*. Both
    /// chromes say the same sentence; only the icon differs.
    private var header: some View {
        HStack(spacing: 8) {
            // Standalone only. Hosted, the rail tab is already this tool's
            // head; in its own window there is no rail, so the header is the
            // only place the app says what it is.
            if chrome != .hosted {
                ToolIcon(icon: nil, fallback: "text.viewfinder",
                         tint: ShotPalette.accent, size: 30)
            }
            Image(systemName: watchState.symbol)
                .font(.system(size: 9))
                .foregroundStyle(watchState.tint)
                .accessibilityHidden(true)
            Text(watchState.title)
                .font(chrome == .hosted ? .callout.weight(.medium) : .caption.weight(.medium))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            // The far end of the band is content, not margin. The spinner was
            // already here saying nothing; now it says what it is waiting for,
            // which is the only thing the right edge has to report.
            if model.busy {
                Text("Naming the newest capture…")
                    .font(chrome == .hosted ? .caption : .caption2)
                    .foregroundStyle(.secondary).lineLimit(1)
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The three states worth a word at the top of a folder watcher.
    private enum WatchState {
        case watching, paused, standingDown

        var symbol: String {
            switch self {
            case .watching:     return "circle.fill"
            case .paused:       return "circle"
            case .standingDown: return "pause.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .watching:     return .green
            case .paused:       return .secondary
            case .standingDown: return ShotPalette.warning
            }
        }

        /// Short enough to survive the 340pt popover beside a 30pt icon.
        var title: String {
            switch self {
            case .watching:     return "Watching for new screenshots"
            case .paused:       return "Paused — new captures keep their names"
            case .standingDown: return "Standing down for ShotScribe.app"
            }
        }
    }

    private var watchState: WatchState {
        if model.otherInstanceRunning { return .standingDown }
        return model.watching ? .watching : .paused
    }

    /// The watch folder, drawn as the **folder it is** and doubling as the drop
    /// target.
    ///
    /// It was a label and a "Change…" button, which put a file picker between
    /// you and a folder already open in Finder. Dropping the folder says the
    /// same thing in one gesture, and the three named choices cover the places
    /// captures actually live without opening anything.
    ///
    /// **Where it is lives in the hover.** The row shows the folder the way
    /// Finder shows it — its own icon, its own name — and says only what it is
    /// for; the full path is one hover away, on the row it describes, and also
    /// spelled out under "Current" in the Change menu. That is the whole reason
    /// the header no longer opens with a path: the destination is a property of
    /// this row, not a headline.
    private var folderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FolderIcon(url: model.folder, targeted: folderTargeted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.folder.lastPathComponent)
                        .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text(folderTargeted
                         ? "Drop to watch this folder"
                         : "Drop area for your screenshots")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if model.usesCustomFolder {
                    Button { model.useSystemFolder() } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain).controlSize(.small)
                    .help("Back to the system screenshot folder")
                }
                // A menu rather than a button: the answer is almost always one
                // of four known folders, and a file picker for that is a dialog
                // standing between you and a one-click choice.
                Menu {
                    // Spelled out, tilde-abbreviated: the second place the
                    // path is readable, for anyone who opens the menu instead
                    // of resting on the row.
                    Section("Current") {
                        Button {
                        } label: {
                            Label(abbreviatedFolderPath, systemImage: "checkmark")
                        }
                        .disabled(true)
                    }
                    Section("Common") {
                        ForEach(ShotScribeModel.quickFolders) { c in
                            Button {
                                model.use(c)
                            } label: {
                                Text(c.label)
                            }
                            .disabled(model.folder.path == c.url.path)
                        }
                    }
                    Divider()
                    Button("Choose another folder…") { model.chooseFolder() }
                    if model.usesCustomFolder {
                        Button("Back to system screenshot folder") { model.useSystemFolder() }
                    }
                } label: {
                    Text("Change")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.small)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .foregroundStyle(folderTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator)))
            .contentShape(Rectangle())
            .onDrop(of: [UTType.fileURL], isTargeted: $folderTargeted) { providers in
                guard let p = providers.first else { return false }
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.acceptDrop(url) }
                }
                return true
            }
            // The path, on demand. Rest anywhere on the row — including the
            // icon and the name — and it tells you where you are going.
            .help(destinationHelp)

        }
    }

    /// The whole answer to "where do my screenshots go?", which is the one job
    /// the full path has. Said in the hover so it does not have to be said at
    /// the top of the surface.
    private var destinationHelp: String {
        "New screenshots land in \(model.folder.path)"
    }

    /// `~/Pictures/Screenshots` rather than `/Users/you/Pictures/Screenshots` —
    /// same information, and it fits in a menu.
    private var abbreviatedFolderPath: String {
        (model.folder.path as NSString).abbreviatingWithTildeInPath
    }

    private var watchToggle: some View {
        Toggle(isOn: $model.watching) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Auto-rename new screenshots")
                Text("Watches the folder above; only default “Screenshot …” names are touched.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(model.otherInstanceRunning)
    }

    private var claudeToggle: some View {
        Toggle(isOn: $model.useClaude) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Title with Claude")
                Text(model.claudeAvailable
                     ? "Uses your own Claude Code account — only the text read off the image is sent."
                     : "Claude Code isn’t installed — using the offline titler.")
                    .font(.caption2).foregroundStyle(.secondary)
                if !model.claudeAvailable {
                    Link("Get Claude Code — titles run on your own account",
                         destination: URL(string: "https://claude.com/claude-code")!)
                        .font(.caption2)
                }
                // Say when the machine's setting overrides this toggle, rather
                // than leaving it on and quietly using the offline titler.
                if let note = model.llmMismatchNote {
                    Text(note).font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!model.claudeAvailable)
    }

    private var renameAction: some View {
        Button {
            model.renameLatest()
        } label: {
            Label("Rename latest capture now", systemImage: "wand.and.stars")
        }
        .disabled(model.busy || model.otherInstanceRunning)
    }

    @ViewBuilder
    private var errorLine: some View {
        if let err = model.lastError {
            Text(err).font(.caption2).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func historyList(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(model.events.prefix(limit)) { e in
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.to).font(.caption).lineLimit(1).truncationMode(.middle)
                        Text(e.from).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    // The way back, on the row that describes the rename — for
                    // as long as the file is still where the rename left it.
                    if model.canUndo(e) {
                        Button("Undo") { model.undo(e) }
                            .controlSize(.mini)
                            .help("Put “\(e.from)” back")
                    }
                }
            }
        }
    }
}

/// The watch folder as **Finder draws it** — its real icon, custom ones
/// included — so the drop zone reads as a folder you recognise rather than as a
/// setting with a generic glyph beside it.
///
/// While a drag is over the row it swaps to the badge symbol: mid-drop the
/// question is "will this land here", and a badge answers that better than an
/// accurate picture of the destination does.
private struct FolderIcon: View {
    let url: URL
    let targeted: Bool
    var size: CGFloat = 22

    var body: some View {
        Group {
            if targeted {
                Image(systemName: "folder.fill.badge.plus")
                    .font(.system(size: size * 0.78))
                    .foregroundStyle(.tint)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
