import SwiftUI
import ShotScribeCore
import UniformTypeIdentifiers
import AppKit

/// How much room the surface has, and therefore which controls make sense.
public enum ShotScribeChrome {
    /// A 340pt menu bar popover: compact, and the place where app-level
    /// controls (launch at login, Quit) belong.
    case menuBar
    /// A roomy pane: the app's own window, or a detail pane inside some other
    /// host. App-level controls are omitted — `SMAppService.mainApp` would
    /// register *that* host at login, and "Quit" would quit it.
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
/// uses it so its window and its panel share one watcher. Note the
/// `@ObservedObject`: a stored `let` here means the view never redraws when a
/// rename lands.
public struct ShotScribeView: View {
    @ObservedObject var model: ShotScribeModel
    let chrome: ShotScribeChrome
    @State private var folderTargeted = false
    /// Drafts, not bindings to the model: half-typed text is invalid text, and
    /// a name template or a new tag is only worth saving once it is finished.
    @State private var layoutDraft = ""
    @State private var newTag = ""
    /// The floating inspector: open on first launch so the settings are found,
    /// one tab at a time so it never scrolls.
    @State private var inspectorOpen = true
    @State private var tab: InspectorTab = .rename
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

    // MARK: The window

    /// The screenshots are the product, so they get the whole window, edge to
    /// edge, and scroll underneath everything else. The chrome floats: a status
    /// capsule and search up top, a tabbed inspector inset on the right. That
    /// is the macOS 26 idiom, and it is what makes glass read as glass — there
    /// has to be content moving behind it.
    ///
    /// Locked in from the glass preview, 2026-09-12: captions on hover, the
    /// latest capture up top, groups by day, inspector open on Rename.
    private static let inspectorWidth: CGFloat = 300
    private static let inset: CGFloat = 14

    private var pane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.otherInstanceRunning { standDownBanner.padding(.bottom, 14) }
                if let plan = model.cleanupPlan { cleanupPreview(plan).padding(.bottom, 14) }
                content
            }
            .padding(.top, 52)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .padding(.trailing, inspectorOpen ? Self.inspectorWidth + Self.inset * 2 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .topTrailing) {
            if inspectorOpen {
                inspector
                    .padding(.top, 50)
                    .padding(.trailing, Self.inset)
                    .padding(.bottom, Self.inset)
            }
        }
        .tint(ShotPalette.accent)
        // Paint the window colour ourselves: the content is the ScrollView and
        // nothing else, so a host that does not draw a background would show
        // the grid over nothing at all.
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: inspectorOpen)
    }

    /// Status on the left, search and the inspector toggle on the right, all
    /// as capsules over the content. There is no bar: the content runs under.
    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(watchState.tint).frame(width: 7, height: 7)
                    .shadow(color: watchState.tint.opacity(0.45), radius: 3)
                Text(watchState.short).foregroundStyle(.secondary)
                Text(model.folder.lastPathComponent).fontWeight(.semibold)
                    .lineLimit(1).truncationMode(.middle)
                if model.busy { ProgressView().controlSize(.mini).padding(.leading, 2) }
            }
            .font(.callout)
            .padding(.horizontal, 12).frame(height: 32)
            .glass(in: Capsule())
            .help(watchState.title)

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a screenshot", text: $model.query)
                    .textFieldStyle(.plain)
                    .onSubmit { model.runSearch() }
                    .onChange(of: model.query) { _ in model.runSearch() }
                if !model.query.isEmpty {
                    Button { model.query = ""; model.runSearch() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 12).frame(width: 250, height: 32)
            .glass(in: Capsule())

            Button { inspectorOpen.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(inspectorOpen ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .background {
                if inspectorOpen { Capsule().fill(ShotPalette.accent).shadow(color: ShotPalette.accent.opacity(0.45), radius: 10, y: 4) }
            }
            .glass(in: Capsule())
            .help(inspectorOpen ? "Hide the inspector" : "Show the inspector")
        }
        .padding(.horizontal, Self.inset).padding(.top, 10)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.indexing {
            indexingState
        } else if model.visibleShots.isEmpty {
            if model.query.trimmingCharacters(in: .whitespaces).isEmpty { emptyState } else { noMatches }
        } else if model.shotView == .list {
            gridHead
            shotsList
        } else {
            let hero = heroShot
            if let hero { heroCard(hero) }
            gridHead
            ForEach(dayGroups(excluding: hero)) { group in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.title).font(.system(size: 15, weight: .bold)).tracking(-0.3)
                    Text(group.subtitle).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.top, 8).padding(.bottom, 10)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 196, maximum: 300), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    ForEach(group.sessions) { s in
                        if s.isBurst && !model.isExpanded(s) {
                            GallerySessionTile(session: s, model: model)
                        } else {
                            ForEach(s.shots) { shot in
                                GalleryTile(shot: shot, session: s.isBurst ? s : nil, model: model)
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    /// The capture that just landed, large, with what it was called and what
    /// it is called now. Only in the chronological view: a search result or a
    /// name sort has no "latest".
    private var heroShot: IndexedShot? {
        guard model.query.trimmingCharacters(in: .whitespaces).isEmpty,
              model.sort == .newest else { return nil }
        return model.visibleShots.first
    }

    private func heroCard(_ shot: IndexedShot) -> some View {
        ZStack(alignment: .top) {
            // Ambient: the capture's own colours, blurred, fading into the
            // window. Content-derived, so the top of the window takes its tint
            // from what is actually there.
            AspectThumbnail(path: shot.path, aspect: 2.2, pixels: 320)
                .blur(radius: 46)
                .saturation(1.4)
                .scaleEffect(1.25)
                .opacity(0.55)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(LinearGradient(colors: [Color(nsColor: .windowBackgroundColor).opacity(0.2),
                                                 Color(nsColor: .windowBackgroundColor)],
                                        startPoint: .top, endPoint: .bottom))
                .padding(.horizontal, -18).padding(.top, -52)
                .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 18) {
                AspectThumbnail(path: shot.path, aspect: 1.6, pixels: 960)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 20, y: 12)
                    .frame(maxWidth: .infinity)
                    .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
                    .help("Drag to attach a copy elsewhere.")
                VStack(alignment: .leading, spacing: 6) {
                    // foregroundColor, not foregroundStyle: on a concatenated Text the
                    // latter is macOS 14+, and this package floors at 13.
                    (Text("Latest, ").foregroundColor(.secondary)
                        + Text(shot.captured, format: .dateTime.hour().minute()).fontWeight(.semibold)
                        + Text(" \(dayWord(shot.captured))").foregroundColor(.secondary))
                    Text(Sessions.stem(of: shot.name))
                        .font(.system(size: 22, weight: .bold)).tracking(-0.6)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if let original = shot.original {
                        Text("was \(original)").font(.caption2).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    if !(shot.tags ?? []).isEmpty {
                        HStack(spacing: 6) { tagChips(shot) }.padding(.top, 2)
                    }
                    HStack(spacing: 6) {
                        Button { model.reveal(shot) } label: {
                            Label("Reveal in Finder", systemImage: "arrow.up.forward.square")
                        }
                        .buttonStyle(CapsuleButtonStyle())
                        Button { model.sendToClaude(shot) } label: {
                            Label("Send to Claude", systemImage: "paperplane")
                        }
                        .buttonStyle(CapsuleButtonStyle())
                        .help("Copies a /screenshot line for this shot. Paste it into any Claude Code session and Claude reads the shot there.")
                        Button { model.copyCodeBrief(for: shot) } label: {
                            Label("Rebuild as code", systemImage: "curlybraces")
                        }
                        .buttonStyle(CapsuleButtonStyle())
                        .help("Copies a brief for Claude Code: the file, its text with positions, and how to work. Paste it in the project the code should land in.")
                        if shot.original != nil, !model.otherInstanceRunning {
                            Button { model.undo(shot) } label: {
                                Label("Restore name", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(CapsuleButtonStyle(quiet: true))
                        }
                        if model.taggingEnabled { fileAsMenu(shot) }
                    }
                    .padding(.top, 6)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.top, 6)
        }
        .padding(.bottom, 18)
    }

    /// Count, selection, sort and view: quiet, one line, above the groups.
    private var gridHead: some View {
        HStack(spacing: 10) {
            Text(model.query.isEmpty
                 ? "\(model.visibleShots.count) screenshots"
                 : "\(model.visibleShots.count) match\(model.visibleShots.count == 1 ? "" : "es")")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
            if let handoff = model.handoffNote {
                Label(handoff.text, systemImage: handoff.symbol)
                    .font(.caption).foregroundStyle(ShotPalette.accent)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            if model.selecting {
                Text("\(model.selected.count) selected").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button("All") { model.selectAllVisible() }.controlSize(.small)
                Button(role: .destructive) { model.trashSelected() } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .controlSize(.small).disabled(model.selected.isEmpty)
            }
            Spacer()
            Button { model.selecting.toggle() } label: {
                Image(systemName: model.selecting ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.selecting ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .help(model.selecting ? "Done selecting" : "Select screenshots")
            Picker("", selection: $model.sort) {
                ForEach(ShotScribeModel.ShotSort.allCases) { s in Text(s.label).tag(s) }
            }
            .labelsHidden().controlSize(.small).frame(width: 118).help("Sort")
            Picker("", selection: $model.shotView) {
                ForEach(ShotScribeModel.ShotView.allCases) { v in
                    Image(systemName: v.symbol).tag(v).help(v.label)
                }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
        }
        .padding(.bottom, 4)
    }

    private struct DayGroup: Identifiable {
        let id: Date
        let title: String
        let subtitle: String
        var sessions: [Session]
    }

    /// Yesterday, Thursday, 3 September. Hierarchy the grid did not have, and
    /// only when the order is chronological: grouped by day under a name sort
    /// or a search would put unrelated things together.
    private func dayGroups(excluding hero: IndexedShot?) -> [DayGroup] {
        let chronological = model.query.trimmingCharacters(in: .whitespaces).isEmpty
            && (model.sort == .newest || model.sort == .oldest)
        let shots = model.visibleShots.filter { $0.path != hero?.path }
        let sessions = Sessions.collapse(shots, gapMinutes: chronological ? model.keepPolicy.sessionGapMinutes : 0)
        guard chronological else {
            return [DayGroup(id: .distantPast, title: model.query.isEmpty ? "All screenshots" : "Matches", subtitle: "", sessions: sessions)]
        }
        let cal = Calendar.current
        var groups: [DayGroup] = []
        var index: [Date: Int] = [:]
        for s in sessions {
            let day = cal.startOfDay(for: (s.representative ?? s.shots[0]).captured)
            if let i = index[day] { groups[i].sessions.append(s) }
            else {
                index[day] = groups.count
                groups.append(DayGroup(id: day, title: Self.dayTitle(day), subtitle: Self.daySubtitle(day), sessions: [s]))
            }
        }
        return groups
    }

    private static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        if let week = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())), day >= week {
            return day.formatted(.dateTime.weekday(.wide))
        }
        return day.formatted(.dateTime.day().month(.wide))
    }

    private static func daySubtitle(_ day: Date) -> String {
        let cal = Calendar.current
        let sameYear = cal.isDate(day, equalTo: Date(), toGranularity: .year)
        if cal.isDateInToday(day) || cal.isDateInYesterday(day)
            || (cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())).map { day >= $0 } ?? false) {
            return sameYear ? day.formatted(.dateTime.day().month(.wide)) : day.formatted(.dateTime.day().month(.wide).year())
        }
        return sameYear ? "" : day.formatted(.dateTime.year())
    }

    private func dayWord(_ date: Date) -> String {
        Self.dayTitle(Calendar.current.startOfDay(for: date)).lowercased()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 22) {
                FolderIcon(url: model.folder, targeted: folderTargeted, size: 56)
                    .frame(width: 96, height: 96)
                    .glass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Take a screenshot").font(.system(size: 20, weight: .bold)).tracking(-0.5)
                    Text("It lands in **\(model.folder.lastPathComponent)** and gets a name that says what it shows. Press ⇧ ⌘ 4, or drop a folder below to watch a different one.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 70)
            folderRow.frame(maxWidth: 470)
        }
        .frame(maxWidth: 560)
    }

    private var noMatches: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing matched “\(model.query)”").font(.system(size: 15, weight: .bold)).tracking(-0.3)
            Text("Search reads what each screenshot said, not only its name. If these shots predate the index, run a sweep from the Folder tab.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 40)
    }

    private var indexingState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Reading the folder").font(.system(size: 15, weight: .bold)).tracking(-0.3)
                if let (i, n) = model.indexProgress {
                    Text("\(i) of \(n)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.top, 8)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 196, maximum: 300), spacing: 10)], spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary)
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
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
                .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
                .help("\(shot.path)\nDrag to attach a copy elsewhere.")
                .contextMenu { shotMenu(shot) }
                Divider()
            }
        }
    }

    /// The filing, on the shot. Tapping one searches for it — the shortest path
    /// from "this one" to "everything like this one".
    @ViewBuilder
    func tagChips(_ shot: IndexedShot) -> some View {
        ForEach(shot.tags ?? [], id: \.self) { tag in
            TagChip(tag: tag) { model.filter(tag: tag) }
        }
    }

    /// The vocabulary otherwise only applies at rename time, which would leave
    /// every capture from before today reachable only through Finder.
    private func fileAsMenu(_ shot: IndexedShot) -> some View {
        Menu {
            ForEach(model.vocabulary, id: \.self) { tag in
                Button(tag) { model.tag(shot, with: tag) }
                    .disabled((shot.tags ?? []).contains { $0.caseInsensitiveCompare(tag) == .orderedSame })
            }
        } label: {
            Label("File as", systemImage: "tag")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .padding(.horizontal, 10).frame(height: 26)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    @ViewBuilder
    func shotMenu(_ shot: IndexedShot) -> some View {
        Button("Reveal in Finder") { model.reveal(shot) }
        Button("Send to Claude") { model.sendToClaude(shot) }
        Button("Rebuild as code") { model.copyCodeBrief(for: shot) }
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

    // MARK: Inspector

    private enum InspectorTab: String, CaseIterable, Identifiable {
        case folder, rename, name, file, keep
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .folder: return "folder"
            case .rename: return "wand.and.stars"
            case .name:   return "textformat"
            case .file:   return "tag"
            case .keep:   return "archivebox"
            }
        }
        var title: String { rawValue.capitalized }
    }

    /// One pane at a time, so the inspector never scrolls past a screen. It
    /// floats inset from the window edge on glass; the grid runs under it.
    private var inspector: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(InspectorTab.allCases) { t in
                    Button { tab = t } label: {
                        Image(systemName: t.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background {
                                if tab == t {
                                    Capsule().fill(.ultraThinMaterial)
                                        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tab == t ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .help(t.title)
                }
            }
            .padding(6)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .padding(8)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch tab {
                    case .folder: folderPane
                    case .rename: renamePane
                    case .name:   namePane
                    case .file:   filePane
                    case .keep:   keepPane
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: Self.inspectorWidth)
        .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func paneHead(_ title: String, _ lead: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .bold)).tracking(-0.3)
            Text(lead).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 6)
    }

    private var folderPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            paneHead("Folder", "Where captures land. New ones are renamed as they arrive.")
            folderRow
            Text(abbreviatedFolderPath).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            Divider().padding(.vertical, 4)
            HStack(spacing: 8) {
                Button { model.rebuildIndex() } label: { Label("Read the folder again", systemImage: "arrow.clockwise") }
                    .buttonStyle(CapsuleButtonStyle()).disabled(model.indexing)
                Button("Open in Finder") { NSWorkspace.shared.open(model.folder) }
                    .buttonStyle(CapsuleButtonStyle(quiet: true))
            }
            Text("\(model.indexedCount) screenshots indexed. Search reads what each one said.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var renamePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            paneHead("Rename", "What happens to a capture the moment it lands.")
            watchToggle
            claudeToggle
            // Never a box: a state worth a word gets one quiet line, next to
            // the toggle it concerns.
            if let err = model.lastError {
                HStack(alignment: .top, spacing: 7) {
                    Circle().fill(ShotPalette.warning).frame(width: 6, height: 6).padding(.top, 5)
                    Text(err).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button { model.renameLatest() } label: {
                Label("Rename latest capture now", systemImage: "wand.and.stars")
            }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
            .disabled(model.busy || model.otherInstanceRunning)
            .padding(.top, 4)
        }
    }

    private var namePane: some View {
        VStack(alignment: .leading, spacing: 8) {
            paneHead("Name", "How a renamed capture is spelled.")
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
                HStack(spacing: 6) {
                    Text("preview").font(.system(size: 9, weight: .semibold)).foregroundStyle(ShotPalette.accent)
                    Text(Naming.sampleFilename(draftTemplate) ?? "—")
                        .font(.caption2.monospaced()).lineLimit(1).truncationMode(.middle)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(ShotPalette.accent.opacity(0.14), in: Capsule())
            }
            Text("Tokens: \(NameTemplate.tokens.joined(separator: "  ")). Everything else is literal, so the separators are yours.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().padding(.vertical, 2)
            keepRow("Date", "Date first is what keeps a name-sorted folder in order.") {
                Picker("", selection: naming(\.dateStyle)) {
                    Text("2026-08-11").tag(NameTemplate.DateStyle.iso)
                    Text("08-11-2026").tag(NameTemplate.DateStyle.us)
                    Text("20260811").tag(NameTemplate.DateStyle.compact)
                }
                .labelsHidden().frame(width: 112)
            }
            keepRow("Time", "The clock, as the name spells it.") {
                Picker("", selection: naming(\.timeStyle)) {
                    Text("1541").tag(NameTemplate.TimeStyle.hhmm)
                    Text("15-41").tag(NameTemplate.TimeStyle.dashed)
                    Text("3.41 PM").tag(NameTemplate.TimeStyle.twelveHour)
                }
                .labelsHidden().frame(width: 112)
            }
            keepRow("Title", "How the words themselves are joined.") {
                Picker("", selection: naming(\.titleStyle)) {
                    Text("As read").tag(NameTemplate.TitleStyle.asIs)
                    Text("kebab").tag(NameTemplate.TitleStyle.kebab)
                    Text("snake").tag(NameTemplate.TitleStyle.snake)
                }
                .labelsHidden().frame(width: 112)
            }
            keepRow("Words kept", "A longer summary is the titler's job, not the name's.") {
                Picker("", selection: naming(\.titleWords)) {
                    ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden().frame(width: 58)
            }
            Text("Applies to captures from here on. Nothing already named is re-spelled.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .onAppear { layoutDraft = model.nameTemplate.layout }
        .onChange(of: model.nameTemplate.layout) { layoutDraft = $0 }
    }

    /// A style change applies at once — a picker cannot spell an unusable name,
    /// and if it somehow does, the store refuses it and says so. The layout is
    /// different: half-typed text is invalid text, so it waits for Return or "Use".
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

    private func applyLayout() {
        model.setNameTemplate(draftTemplate)
    }

    private var filePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            paneHead("File", "Finder tags, from a list you control.")
            Toggle(isOn: Binding(get: { model.taggingEnabled }, set: { model.setTaggingEnabled($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("File under Finder tags")
                    Text("Up to \(Tagging.maxPerShot) per capture. Finder and Spotlight can search them.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch).controlSize(.small)
            FlowLayout(spacing: 6) {
                ForEach(model.vocabulary, id: \.self) { tag in
                    HStack(spacing: 5) {
                        Text(tag).font(.caption)
                        Button {
                            model.setVocabulary(model.vocabulary.filter { $0 != tag })
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Remove \(tag) from the list")
                    }
                    .padding(.leading, 10).padding(.trailing, 7).frame(height: 24)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                }
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    TextField("Add tag", text: $newTag)
                        .textFieldStyle(.plain).font(.caption).frame(width: 64)
                        .onSubmit {
                            model.setVocabulary(model.vocabulary + [newTag])
                            newTag = ""
                        }
                }
                .padding(.horizontal, 10).frame(height: 24)
                .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(.tertiary))
            }
            .opacity(model.taggingEnabled ? 1 : 0.4)
            .disabled(!model.taggingEnabled)
            HStack {
                Text("A tag outside the list is never used, however it was suggested. \(Tagging.maxVocabulary) at most.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Shipped list") { model.setVocabulary([]) }
                    .font(.caption2).buttonStyle(.link)
                    .disabled(model.vocabulary == Tagging.defaultVocabulary)
            }
        }
    }

    private var keepPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            paneHead("Keep", "Sessions, duplicates and age. Nothing moves without a preview.")
            keepRow("Group bursts into sessions",
                    "Captures within a few minutes of each other fold into one tile.") {
                Picker("", selection: keep(\.sessionGapMinutes)) {
                    Text("Off").tag(0)
                    ForEach([1, 3, 5, 10, 15], id: \.self) { Text("\($0) min").tag($0) }
                }
                .labelsHidden().frame(width: 84)
            }
            Toggle(isOn: keep(\.flagDuplicates)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Flag duplicates")
                    Text("A later capture whose text matches an earlier one. Thin or empty text never counts.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            Divider().padding(.vertical, 2)
            Button { model.previewCleanup() } label: {
                Label("Preview clean-up", systemImage: "sparkles")
            }
            .buttonStyle(CapsuleButtonStyle())
            .disabled(model.indexedCount == 0 || model.cleaning)
            Text("Nothing moves until you confirm the list. The list appears with the screenshots.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Keep helpers

    private func keep<T>(_ path: WritableKeyPath<KeepPolicy, T>) -> Binding<T> {
        Binding(get: { model.keepPolicy[keyPath: path] },
                set: { model.keepPolicy[keyPath: path] = $0 })
    }

    private func keepRow<Control: View>(_ title: String, _ detail: String,
                                        @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if !detail.isEmpty {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        VStack(alignment: .trailing, spacing: 4) {
            Picker("", selection: Binding<Bool>(
                get: { if case .archive = model.keepPolicy.destination { return true } else { return false } },
                set: { archive in
                    if archive { model.chooseArchiveFolder() }
                    else { model.keepPolicy.destination = .trash }
                })) {
                Text("Trash").tag(false)
                Text("Archive").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            if case .archive(let path) = model.keepPolicy.destination {
                Button((path as NSString).lastPathComponent + "…") { model.chooseArchiveFolder() }
                    .controlSize(.small)
                    .help(path)
            }
        }
    }

    /// The list, before anything moves. Every row says why it is there. Lives
    /// with the screenshots, not in the inspector: it is about them.
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The one thing a hosted copy must say out loud: it is deliberately not
    /// watching, and why.
    private var standDownBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(ShotPalette.warning).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("ShotScribe.app is running").font(.callout.weight(.semibold))
                Text("It already watches this folder. Two watchers would race to rename the same capture, so this copy is standing down — quit ShotScribe.app and it picks up automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    /// What the top of a watcher owes you instead is whether it is *on*.
    private var header: some View {
        HStack(spacing: 8) {
            ToolIcon(icon: nil, fallback: "text.viewfinder",
                     tint: ShotPalette.accent, size: 30)
            Image(systemName: watchState.symbol)
                .font(.system(size: 9))
                .foregroundStyle(watchState.tint)
                .accessibilityHidden(true)
            Text(watchState.title)
                .font(.caption.weight(.medium))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if model.busy {
                Text("Naming the newest capture…")
                    .font(.caption2)
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

        /// One word, for the capsule that sits beside the folder's name.
        var short: String {
            switch self {
            case .watching:     return "Watching"
            case .paused:       return "Paused"
            case .standingDown: return "Standing down"
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
    /// spelled out under "Current" in the Change menu.
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
    /// the full path has.
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
                    .fixedSize(horizontal: false, vertical: true)
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
                    .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Gallery tiles

/// One screenshot as a 4:3 image. The caption lives on the image and shows on
/// hover, so the grid reads as pictures first and information second. Its own
/// view because hover is per-tile state.
private struct GalleryTile: View {
    let shot: IndexedShot
    let session: Session?
    @ObservedObject var model: ShotScribeModel
    @State private var hovered = false

    var body: some View {
        let picked = model.selected.contains(shot.path)
        let leadsSession = session?.shots.first?.path == shot.path
        Button {
            model.selecting ? model.toggleSelected(shot) : model.reveal(shot)
        } label: {
            AspectThumbnail(path: shot.path)
                .overlay(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shot.name).font(.caption.weight(.semibold))
                            .lineLimit(1).truncationMode(.middle)
                        HStack(spacing: 6) {
                            Text(shot.captured, format: .dateTime.hour().minute())
                                .font(.caption2).monospacedDigit()
                            ForEach(shot.tags ?? [], id: \.self) { tag in
                                TagChip(tag: tag, onImage: true) { model.filter(tag: tag) }
                            }
                        }
                        .foregroundStyle(.white.opacity(0.78))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.bottom, 9).padding(.top, 26)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.black.opacity(0.88), .clear], startPoint: .bottom, endPoint: .top))
                    .opacity(hovered || model.selecting ? 1 : 0)
                }
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
                                .font(.caption2.weight(.semibold)).monospacedDigit()
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .help("Fold these \(session.count) back into one tile")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(picked || hovered ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                                  lineWidth: picked || hovered ? 2 : 1))
                .shadow(color: .black.opacity(hovered ? 0.35 : 0), radius: 14, y: 8)
                .scaleEffect(hovered ? 1.015 : 1)
                .animation(.easeOut(duration: 0.18), value: hovered)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Drag it out as the file itself: Mail, Jira, Slack get a copy, the
        // way they would from Finder.
        .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
        .onHover { hovered = $0 }
        .help("\(shot.path)\nDrag to attach a copy elsewhere.")
        .contextMenu {
            Button("Reveal in Finder") { model.reveal(shot) }
            Button("Send to Claude") { model.sendToClaude(shot) }
            Button("Rebuild as code") { model.copyCodeBrief(for: shot) }
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
}

/// A folded burst: the last shot stands for the whole, with the count on its
/// shoulder and two edges behind so it reads as a stack.
private struct GallerySessionTile: View {
    let session: Session
    @ObservedObject var model: ShotScribeModel
    @State private var hovered = false

    var body: some View {
        Button { model.toggleExpanded(session) } label: {
            AspectThumbnail(path: (session.representative ?? session.shots[0]).path)
                .overlay(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.title).font(.caption.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        (Text("\(session.count) shots, ")
                         + Text(session.start, format: .dateTime.hour().minute())
                         + Text(" to ")
                         + Text(session.end, format: .dateTime.hour().minute()))
                            .font(.caption2).monospacedDigit().foregroundStyle(.white.opacity(0.78))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.bottom, 9).padding(.top, 26)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.black.opacity(0.88), .clear], startPoint: .bottom, endPoint: .top))
                    .opacity(hovered ? 1 : 0)
                }
                .overlay(alignment: .topTrailing) {
                    Label("\(session.count)", systemImage: "square.stack")
                        .font(.caption2.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(hovered ? AnyShapeStyle(.tint) : AnyShapeStyle(ShotPalette.accent.opacity(0.5)),
                                  lineWidth: hovered ? 2 : 1))
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.quaternary).offset(x: 5, y: -5).scaleEffect(0.985))
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.quinary).offset(x: 10, y: -10).scaleEffect(0.97))
                .shadow(color: .black.opacity(hovered ? 0.35 : 0), radius: 14, y: 8)
                .scaleEffect(hovered ? 1.015 : 1)
                .animation(.easeOut(duration: 0.18), value: hovered)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag { NSItemProvider(contentsOf: (session.representative ?? session.shots[0]).url) ?? NSItemProvider() }
        .onHover { hovered = $0 }
        .help("\(session.count) captures within \(model.keepPolicy.sessionGapMinutes) minutes of each other — click to open them out")
    }
}

// MARK: - Tag chips

/// A tag, drawn as a tag: the glyph, the word, and a tooltip that says what it
/// is and what clicking does. It was a bare pill, and a pill that says "code"
/// beside a feature called code reads as a button. Nothing here runs anything;
/// it filters.
private struct TagChip: View {
    let tag: String
    var onImage = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "tag").font(.system(size: 8, weight: .semibold))
                Text(tag).font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(onImage ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(ShotPalette.accent.opacity(0.18)),
                        in: Capsule())
            .foregroundStyle(onImage ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .help("Filed under “\(tag)” (a Finder tag). Click to see everything filed the same way.")
    }
}

// MARK: - Glass, capsules, flow

/// Liquid Glass where the system has it, the thin material everywhere else. A
/// 1pt lit top edge either way: the small thing that makes Apple's controls
/// look lit rather than printed.
private extension View {
    @ViewBuilder
    func glass<S: InsettableShape>(in shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.05)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
    }
}

private struct CapsuleButtonStyle: ButtonStyle {
    var quiet = false
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).frame(height: 27)
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : quiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .background {
                if prominent {
                    Capsule().fill(ShotPalette.accent)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                } else if !quiet {
                    Capsule().fill(Color.primary.opacity(0.08))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Chips that wrap. The one layout SwiftUI does not ship.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
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
