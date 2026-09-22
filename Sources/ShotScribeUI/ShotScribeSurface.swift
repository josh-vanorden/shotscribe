import SwiftUI
import ShotScribeCore
import UniformTypeIdentifiers
import AppKit

/// How the surface is mounted. One way, since 1.7.1: the 340pt menu bar popover
/// (`.menuBar`) went when the menu bar item became a real menu —
/// `ShotScribeMenu` — and nothing was left using it. The type and the
/// parameter stay so a host's `ShotScribeSurface(chrome: .hosted)` still reads
/// the same.
public enum ShotScribeChrome {
    /// A roomy pane: the app's own window, or a detail pane inside some other
    /// host. App-level controls are omitted — `SMAppService.mainApp` would
    /// register *that* host at login, and "Quit" would quit it. They belong to
    /// whatever is hosting: ShotScribe.app keeps them in its Settings and menu.
    case hosted
}

/// **ShotScribe's face.** The Library — captures, search, the landing zone and
/// the inspector — over a `ShotScribeModel`.
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingTitle = false
    @State private var heroHovered = false
    @State private var dragging: LandingZone.Tile?
    @State private var endpointKeyDraft = ""
    /// The picker's own state: a menu picker bound to a computed Binding
    /// changed its displayed value without reaching the model (2026-09-13,
    /// Josh: "had to choose twice"); plain state plus an explicit change
    /// handler is the reliable shape.
    @State private var kindDraft: AIProvider.Kind = .claude
    @ObservedObject var model: ShotScribeModel
    @State private var folderTargeted = false
    /// Drafts, not bindings to the model: half-typed text is invalid text, and
    /// a name template or a new tag is only worth saving once it is finished.
    @State private var layoutDraft = ""
    @State private var newTag = ""
    /// The floating inspector: open on first launch so the settings are found,
    /// one tab at a time so it never scrolls.
    /// Folder first: the one setting that has to be right before anything
    /// else means anything is where the screenshots live.
    @State private var tab: InspectorTab = .folder
    /// Shown once per Mac, on the window only.
    @State private var showGreeting = false
    /// Mirrors Apple's own setting, read when the pane first appears — the
    /// value lives in macOS's domain, not ShotScribe's.
    @State private var systemThumbnailOff = false
    public init(model: ShotScribeModel, chrome: ShotScribeChrome = .hosted) {
        self.model = model
    }

    public var body: some View { pane }

    // MARK: The window

    /// The screenshots are the product, so they get the whole window, edge to
    /// edge, and scroll underneath everything else. The chrome floats: a status
    /// capsule and search up top, a tabbed inspector inset on the right. That
    /// is the macOS 26 idiom, and it is what makes glass read as glass — there
    /// has to be content moving behind it.
    ///
    /// Locked in from the glass preview, 2026-09-12: captions on hover, the
    /// latest capture up top, groups by day. The inspector starts closed and
    /// on **Folder** (2026-09-14): the window opens on the screenshots, and
    /// the first question a settings pane can answer is where they live.
    private static let inspectorWidth: CGFloat = 300
    private static let inset: CGFloat = 14

    private var pane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.otherInstanceRunning { standDownBanner.padding(.bottom, 14) }
                if let plan = model.cleanupPlan { cleanupPreview(plan).padding(.bottom, 14) }
                if let run = model.backlog { backlogPreview(run).padding(.bottom, 14) }
                content
                    // Esc backs out of a tag filter, the way it backs out of a title edit.
                    .onExitCommand {
                        if model.arrangingTiles { model.arrangingTiles = false }
                        else if !model.tagFilter.isEmpty { model.clearTagFilter() }
                    }
            }
            .padding(.top, 52)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .padding(.trailing, model.inspectorOpen ? Self.inspectorWidth + Self.inset * 2 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .topTrailing) {
            if model.inspectorOpen {
                inspector
                    .padding(.top, 50)
                    .padding(.trailing, Self.inset)
                    .padding(.bottom, Self.inset)
            }
        }
        .tint(ShotPalette.accent)
        .sheet(isPresented: $showGreeting) { greeting }
        .onChange(of: model.fileTabRequests) { _ in
            tab = .file
            model.inspectorOpen = true
        }
        .onAppear {
            // The window only. The menu bar popover is 340pt of panel and has
            // no room to introduce anything.
            showGreeting = !model.greeted
            systemThumbnailOff = !SystemThumbnail.isOn
        }
        // Paint the window colour ourselves: the content is the ScrollView and
        // nothing else, so a host that does not draw a background would show
        // the grid over nothing at all.
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.inspectorOpen)
    }

    /// Status on the left, search and the inspector toggle on the right, all
    /// as capsules over the content. There is no bar: the content runs under.
    private var topBar: some View {
        HStack(spacing: 8) {
            folderCapsule
            tagCapsule
            if model.busy { ProgressView().controlSize(.mini) }

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

            appearanceFlip

            Button { model.inspectorOpen.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.inspectorOpen ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .background {
                if model.inspectorOpen { Capsule().fill(ShotPalette.accent).shadow(color: ShotPalette.accent.opacity(0.45), radius: 10, y: 4) }
            }
            .glass(in: Capsule())
            .help(model.inspectorOpen ? "Hide the inspector" : "Show the inspector")
        }
        .padding(.horizontal, Self.inset).padding(.top, 10)
    }

    /// The watch folder, as a menu: the status it always showed, and behind
    /// it the four common folders, a picker, the way back to the system's
    /// folder, Finder, and pause. It read as a label and was one (Josh,
    /// 2026-09-17: "we need that to be clickable so the user can set a new
    /// folder").
    private var folderCapsule: some View {
        Menu {
            Section("Watch") {
                ForEach(ShotScribeModel.quickFolders) { c in
                    Button(c.label) { _ = model.use(c) }
                        .disabled(model.folder.path == c.url.path)
                }
                Button("Choose another folder…") { model.chooseFolder() }
                if model.usesCustomFolder {
                    Button("Back to the system screenshot folder") { model.useSystemFolder() }
                }
            }
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.folder]) }
            Divider()
            if model.otherInstanceRunning {
                Text("Standing down — ShotScribe.app is running")
            } else {
                Toggle("Rename new captures", isOn: $model.watching)
            }
        } label: {
            // One `Text`: a menu's label is drawn as a button title, which keeps
            // runs of text and drops any other view — the dot went missing as a
            // `Circle`, and the accent took the words.
            (Text(Image(systemName: "circle.fill")).font(.system(size: 7)).foregroundColor(watchState.tint)
             + Text("  \(watchState.short)  ").foregroundColor(.secondary)
             + Text(model.folder.lastPathComponent).fontWeight(.semibold).foregroundColor(.primary))
                .font(.callout).lineLimit(1)
                .padding(.horizontal, 12).frame(height: 32)
                .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .glass(in: Capsule())
        .help("\(watchState.title) — \(model.folder.path). Click to change the folder.")
    }

    /// Tagging, beside the folder: whether new captures are filed and how many
    /// words they can be filed under; the switch and the vocabulary behind it.
    private var tagCapsule: some View {
        Menu {
            Toggle("Tag new captures", isOn: Binding(get: { model.taggingEnabled }, set: { model.setTaggingEnabled($0) }))
            Divider()
            Section(model.vocabulary.isEmpty ? "No words yet" : "Files under") {
                ForEach(model.vocabulary.prefix(12), id: \.self) { word in
                    Button(word) { model.query = word; model.runSearch() }
                }
                if model.vocabulary.count > 12 {
                    Text("and \(model.vocabulary.count - 12) more")
                }
            }
            Divider()
            Button("Manage tags…") { model.askForFileTab() }
        } label: {
            (Text(Image(systemName: "tag")).foregroundColor(model.taggingEnabled ? .primary : .secondary)
             + Text(model.taggingEnabled ? "  Tags" : "  Tags off").fontWeight(.semibold)
                .foregroundColor(model.taggingEnabled ? .primary : .secondary)
             + Text(model.taggingEnabled ? "  \(model.vocabulary.count)" : "").foregroundColor(.secondary))
                .font(.callout).lineLimit(1)
                .padding(.horizontal, 12).frame(height: 32)
                .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .glass(in: Capsule())
        .help(model.taggingEnabled
              ? "New captures are filed under \(model.vocabulary.count) words. Click to switch it off, search by a tag, or manage the words."
              : "Tagging is off. Click to switch it on or manage the words.")
    }

    /// One click flips light and dark for the whole app; the menu behind it
    /// hands the choice back to the Mac. Shows what a click will do, not
    /// what is on: a moon in the light, a sun in the dark.
    private var appearanceFlip: some View {
        let dark = colorScheme == .dark
        return Button {
            ShotScribeDefaults.Appearance.select(dark ? .light : .dark)
        } label: {
            Image(systemName: dark ? "sun.max" : "moon")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .glass(in: Capsule())
        .help(dark ? "Switch to light. Right-click to follow the Mac again." : "Switch to dark. Right-click to follow the Mac again.")
        .contextMenu {
            Button("Follow the Mac") { ShotScribeDefaults.Appearance.select(.system) }
            .disabled(ShotScribeDefaults.appearance() == .system)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.indexing {
            indexingState
        } else if model.visibleShots.isEmpty {
            if !model.tagFilter.isEmpty {
                // Narrowed to nothing: keep the strip and the way out — never the
                // first-launch welcome, which has neither.
                gridHead
                tagStrip
                noneFiled
            } else if model.query.trimmingCharacters(in: .whitespaces).isEmpty { emptyState } else { noMatches }
        } else if model.shotView == .list {
            // The landing zone is the point of the window; the list is a denser
            // way to see the rest, not a way to lose the newest capture.
            let hero = heroShot
            if let hero { heroCard(hero) }
            gridHead
            if !model.tagCounts.isEmpty { tagStrip }
            shotsList(excluding: hero)
        } else {
            // The carousel: a day at a time, on one line, the cards overlapping
            // and the one under the cursor rising out of the row. Nothing folds
            // here — the overlapping stack already is the folding a burst used
            // to get from `Sessions.collapse`.
            let hero = heroShot
            if let hero { heroCard(hero) }
            gridHead
            if !model.tagCounts.isEmpty { tagStrip }
            ForEach(dayGroups(excluding: hero)) { group in
                let dayShots = group.sessions.flatMap(\.shots)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.title).font(.system(size: 15, weight: .bold)).tracking(-0.3)
                    Text(group.subtitle).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer(minLength: 12)
                    // The whole day, in one gesture. The pill's own animation is
                    // the beat that lets a mis-click be seen before it lands,
                    // and the word it eats carries the count so nobody deletes
                    // twelve shots thinking they are deleting one.
                    DeletePill(size: 13, quiet: true, forGood: model.deletesForGood,
                               word: "Delete \(dayShots.count)") {
                        model.trash(dayShots)
                    }
                    .id(group.id)
                    .help(model.deletesForGood
                          ? "Delete all \(dayShots.count) from \(group.title) for good — there is no Put Back."
                          : "Move all \(dayShots.count) from \(group.title) to the Trash. Finder's Put Back undoes it.")
                }
                .padding(.top, 8)
                DeckRow(shots: dayShots, model: model)
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
                    .overlay(alignment: .topTrailing) {
                        if heroHovered, !model.otherInstanceRunning {
                            DeletePill(size: 15, onImage: true, forGood: model.deletesForGood) { model.trash(shot) }
                                .id(shot.path)
                                .padding(10)
                                .transition(.opacity)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 20, y: 12)
                    .frame(maxWidth: .infinity)
                    .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
                    .onHover { heroHovered = $0 }
                    .animation(.easeOut(duration: 0.16), value: heroHovered)
                    .help("Drag to attach a copy elsewhere.")
                    .contextMenu { ShotMenu(model: model, shot: shot) }
                VStack(alignment: .leading, spacing: 6) {
                    // foregroundColor, not foregroundStyle: on a concatenated Text the
                    // latter is macOS 14+, and this package floors at 13.
                    (Text("Latest, ").foregroundColor(.secondary)
                        + Text(shot.captured, format: .dateTime.hour().minute()).fontWeight(.semibold)
                        + Text(" \(dayWord(shot.captured))").foregroundColor(.secondary))
                    HeroTitle(shot: shot, editing: $editingTitle) { model.retitle(shot, to: $0) }
                    if let original = shot.original {
                        // Restore lives here, beside the name it puts back, so the
                        // tile row stays one row.
                        HStack(spacing: 6) {
                            Text("was \(original)").font(.caption2).foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                            if !model.otherInstanceRunning {
                                Button("Restore") { model.undo(shot) }
                                    .buttonStyle(.link).font(.caption2)
                                    .help("Put the original capture name back")
                            }
                        }
                    }
                    if !(shot.tags ?? []).isEmpty {
                        HStack(spacing: 6) { tagChips(shot) }.padding(.top, 2)
                    }
                    // The landing zone's actions: one row of tiles, each the icon of
                    // the service it reaches, named the moment it is hovered. The
                    // row is the operator's to arrange — right-click any tile — so
                    // it can lead with what gets used and put away what does not.
                    landingZone(for: shot)
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

    /// Every tag in use with its count: click one to isolate, another to
    /// narrow, Clear to see everything again. The filing system's own table of
    /// contents — the answer to "show me everything I filed under error".
    private var tagStrip: some View {
        FlowLayout(spacing: 6) {
            if !model.tagFilter.isEmpty {
                Button { model.clearTagFilter() } label: {
                    Label("Show all", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(CapsuleButtonStyle())
                .help("Stop isolating; every screenshot again (Esc does the same)")
            }
            ForEach(model.tagCounts) { tc in
                let on = model.tagFilter.contains(tc.tag)
                Button { model.toggleTag(tc.tag) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "tag").font(.system(size: 9, weight: .semibold))
                        Text(tc.tag)
                        Text("\(tc.count)").monospacedDigit().opacity(0.7)
                        if on { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).opacity(0.85) }
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9).frame(height: 24)
                    .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                    .background(Capsule().fill(on ? AnyShapeStyle(ShotPalette.accent) : AnyShapeStyle(Color.primary.opacity(0.06))))
                    .overlay(Capsule().strokeBorder(.white.opacity(on ? 0.25 : 0.08), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(on ? "Filed under \(tc.tag) — click to stop isolating it"
                         : "Isolate everything filed under \(tc.tag); a second tag narrows to both")
            }
        }
        .padding(.bottom, 10)
        .animation(.easeOut(duration: 0.15), value: model.tagFilter)
    }

    /// Count, selection, sort and view: quiet, one line, above the groups.
    private var gridHead: some View {
        HStack(spacing: 10) {
            Text(!model.tagFilter.isEmpty
                 ? "\(model.visibleShots.count) filed under \(model.tagFilter.sorted().joined(separator: " + "))"
                 : model.query.isEmpty
                 ? "\(model.visibleShots.count) screenshots"
                 : "\(model.visibleShots.count) match\(model.visibleShots.count == 1 ? "" : "es")")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
            if !model.tagFilter.isEmpty {
                Button("Show all") { model.clearTagFilter() }
                    .buttonStyle(.link).font(.caption.weight(.medium))
            }
            // The backlog says so where the count already is. The Folder tab
            // says it too, but the inspector starts closed.
            if model.tagFilter.isEmpty, model.query.isEmpty, model.backlogCount > 0, model.backlog == nil {
                Button("· \(model.backlogCount) never named") { model.startBacklog() }
                    .buttonStyle(.link).font(.caption.weight(.medium))
                    .help("Captures that landed while ShotScribe was not watching. Read names for them — nothing is renamed until you confirm.")
            }
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
                    Label(model.deletesForGood ? "Delete for good" : "Move to Trash", systemImage: "trash")
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
        let id: String
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
        // By tag: one group per tag in use, a shot under every tag it carries,
        // the untagged last — the filing as a browse.
        if model.sort == .tag, model.query.trimmingCharacters(in: .whitespaces).isEmpty {
            var byTag: [String: [IndexedShot]] = [:]
            var untagged: [IndexedShot] = []
            for s in shots {
                let tags = Set((s.tags ?? []).map { $0.lowercased() })
                if tags.isEmpty { untagged.append(s) } else { for t in tags { byTag[t, default: []].append(s) } }
            }
            var groups = byTag.keys.sorted().map { t -> DayGroup in
                let members = byTag[t]!
                return DayGroup(id: "tag:\(t)", title: t,
                                subtitle: "\(members.count) screenshot\(members.count == 1 ? "" : "s")",
                                sessions: Sessions.collapse(members, gapMinutes: 0))
            }
            if !untagged.isEmpty {
                groups.append(DayGroup(id: "tag:", title: "Untagged",
                                       subtitle: "\(untagged.count) screenshot\(untagged.count == 1 ? "" : "s")",
                                       sessions: Sessions.collapse(untagged, gapMinutes: 0)))
            }
            return groups
        }
        let sessions = Sessions.collapse(shots, gapMinutes: chronological ? model.keepPolicy.sessionGapMinutes : 0)
        guard chronological else {
            return [DayGroup(id: "all", title: model.query.isEmpty ? "All screenshots" : "Matches", subtitle: "", sessions: sessions)]
        }
        let cal = Calendar.current
        var groups: [DayGroup] = []
        var index: [Date: Int] = [:]
        for s in sessions {
            let day = cal.startOfDay(for: (s.representative ?? s.shots[0]).captured)
            if let i = index[day] { groups[i].sessions.append(s) }
            else {
                index[day] = groups.count
                groups.append(DayGroup(id: "day:\(day.timeIntervalSince1970)", title: Self.dayTitle(day), subtitle: Self.daySubtitle(day), sessions: [s]))
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
                    // The welcome: the tagline, then what to do. Seen once, on a
                    // folder with nothing named yet; after that the shots are the welcome.
                    Text("Every screenshot, named.").font(.system(size: 22, weight: .bold)).tracking(-0.6)
                    Text("The moment it lands, by the AI you already use — and it stays a file in your folder.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Take one: press ⇧ ⌘ 4. It lands in **\(model.folder.lastPathComponent)** and gets a name that says what it shows. Drop a folder below to watch a different one.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 70)
            folderRow.frame(maxWidth: 470)
        }
        .frame(maxWidth: 560)
    }

    /// **The first run.** Says what this is, then asks the one thing that has
    /// to be right before anything else means anything: which folder. The
    /// empty state says the same words, but only a person whose folder is
    /// already empty ever sees it — which is nobody who has used a Mac for a
    /// week. This is shown once, to everyone.
    private var greeting: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                FolderIcon(url: model.folder, targeted: false, size: 52)
                    .frame(width: 88, height: 88)
                    .glass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                VStack(alignment: .leading, spacing: 7) {
                    Text("Every screenshot, named.")
                        .font(.system(size: 24, weight: .bold)).tracking(-0.6)
                    Text("The moment it lands, by the AI you already use — and it stays a file in your folder.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider().padding(.vertical, 20)

            Text("Where your screenshots live").font(.callout.weight(.semibold))
            Text("ShotScribe watches this one folder and names what lands in it. Files you named yourself are never touched, and nothing leaves this Mac.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2).padding(.bottom, 10)
            folderRow

            Toggle(isOn: $model.watching) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Name new screenshots as they land")
                    Text("Off, and nothing is renamed until you ask — the window always can.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch).controlSize(.small)
            .padding(.top, 18)

            HStack(spacing: 12) {
                Text("Everything here is in the inspector later.")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                Button("Start") { model.greeted = true; showGreeting = false }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 22)
        }
        .padding(26)
        .frame(width: 520)
        // Closed any other way still counts as greeted: a welcome that comes
        // back because it was dismissed with Esc is a welcome that nags.
        .onDisappear { model.greeted = true }
    }

    private var noneFiled: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing filed under \(model.tagFilter.sorted().joined(separator: " + ")) together.")
                .font(.system(size: 15, weight: .bold)).tracking(-0.3)
            Text("Take one tag off, or show everything.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Show all") { model.clearTagFilter() }
                .buttonStyle(CapsuleButtonStyle(prominent: true)).padding(.top, 4)
        }
        .padding(.top, 24)
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

    private func shotsList(excluding hero: IndexedShot?) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(model.visibleShots.filter { $0.path != hero?.path }.prefix(300)) { shot in
                ShotRow(shot: shot, model: model, snippet: model.snippet(for: shot))
                Divider()
            }
        }
        // The preview is drawn **here**, once, from whichever row says it is
        // hovered — not inside the row. A row's own overlay is layered with its
        // siblings, so in a `LazyVStack` the rows built after it draw over the
        // top of it and `zIndex` does not save you (2026-09-14: the preview
        // came out behind the names). The container's overlay is above every
        // row by construction.
        .overlayPreferenceValue(HoveredRow.self) { item in
            GeometryReader { proxy in
                if let item {
                    let row = proxy[item.anchor]
                    // Pushed well right of the names, so the rows it hangs over
                    // can still be read; pulled back when the pane is too narrow
                    // to hold it there, and flipped above when the list ends.
                    let x = min(max(row.minX + 320, row.minX),
                                max(row.minX, proxy.size.width - Deck.width - 8))
                    let below = row.maxY + 8 + Deck.height <= proxy.size.height
                    let top = below ? row.maxY + 8 : row.minY - 8 - Deck.height
                    AspectThumbnail(path: item.path, aspect: Deck.width / Deck.height, pixels: 620)
                        .frame(width: Deck.width, height: Deck.height)
                        .clipShape(RoundedRectangle(cornerRadius: Deck.corner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Deck.corner, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1))
                        .shadow(color: .black.opacity(0.45), radius: Deck.shadowRadius, y: 8)
                        .position(x: x + Deck.width / 2, y: top + Deck.height / 2)
                }
            }
            .allowsHitTesting(false)
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
    // MARK: The landing zone

    /// The tiles the row shows, in the stored order. "File as" needs filing to
    /// be on at all, so it comes and goes with the File tab's switch rather
    /// than being something to hide.
    private var shownTiles: [LandingZone.Tile] {
        model.landingZone.visible.filter { offered($0) }
    }

    private var putAwayTiles: [LandingZone.Tile] {
        model.landingZone.order.filter { model.landingZone.hidden.contains($0) && offered($0) }
    }

    private func offered(_ tile: LandingZone.Tile) -> Bool {
        tile != .fileAs || model.taggingEnabled
    }

    @ViewBuilder
    private func landingZone(for shot: IndexedShot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.arrangingTiles {
                Text("Drag to reorder · − puts a tile away · the count is your own use")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: model.arrangingTiles ? 12 : 6) {
                ForEach(shownTiles, id: \.self) { tile in
                    if model.arrangingTiles {
                        arrangeTile(tile, putAway: false)
                    } else {
                        liveTile(tile, for: shot)
                            .contextMenu { tileMenu(tile) }
                    }
                }
                if model.arrangingTiles {
                    ForEach(putAwayTiles, id: \.self) { tile in
                        arrangeTile(tile, putAway: true)
                    }
                }
            }
            if model.arrangingTiles { arrangeBar }
        }
        .padding(model.arrangingTiles ? 10 : 0)
        .background {
            if model.arrangingTiles {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(ShotPalette.accent.opacity(0.35), lineWidth: 1))
            }
        }
        .padding(.top, 8)
        .animation(.easeOut(duration: 0.2), value: model.arrangingTiles)
        .animation(.easeOut(duration: 0.2), value: model.landingZone)
    }

    /// The tile as it works: the real control, which is a button for most, the
    /// unfolding share pill for one and a menu for another.
    @ViewBuilder
    private func liveTile(_ tile: LandingZone.Tile, for shot: IndexedShot) -> some View {
        switch tile {
        case .reveal:
            ActionTile("Reveal in Finder", icon: AppIcons.finder, art: true, sets: .reveal, model: model) { model.reveal(shot) }
        case .markUp:
            ActionTile("Edit with ShotScribe", icon: AppIcons.editor, art: true, sets: .markUp, model: model) { model.markUp(shot) }
        case .share:
            ShareRow(url: shot.url) { model.note(.share) }.id(shot.path)
        case .sendTo:
            // The mark of the titler in use — offline included — so the landing
            // zone says which AI this is at a glance.
            if let symbol = model.aiProvider.kind.symbol {
                ActionTile("Send to \(model.assistantName)", icon: Image(systemName: symbol), sets: .sendToAssistant, model: model) { model.sendToAssistant(shot) }
            } else if let mark = AppIcons.icon(for: model.aiProvider.kind) {
                ActionTile("Send to \(model.assistantName)", icon: mark, art: true, sets: .sendToAssistant, model: model) { model.sendToAssistant(shot) }
            } else {
                ActionTile("Send to \(model.assistantName)", monogram: model.assistantName, sets: .sendToAssistant, model: model) { model.sendToAssistant(shot) }
            }
        case .editTitle:
            ActionTile("Edit title", icon: Image(systemName: "pencil")) { model.note(.editTitle); editingTitle = true }
        case .fileAs:
            fileAsMenu(shot)
        }
    }

    /// The tile while arranging: the same face, but inert — no button, so the
    /// drag has the gesture to itself — with its tally under it and a badge to
    /// put it away or bring it back.
    private func arrangeTile(_ tile: LandingZone.Tile, putAway: Bool) -> some View {
        VStack(spacing: 3) {
            tileFace(tile)
                .overlay(alignment: .topTrailing) {
                    // The badge is the only thing that puts a tile away, so a
                    // click that was meant to be a drag cannot empty the row
                    // by accident.
                    Button { _ = model.setTileHidden(tile, !putAway) } label: {
                        Image(systemName: putAway ? "plus.circle.fill" : "minus.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, putAway ? ShotPalette.accent : Color.secondary)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                }
            Text("\(model.landingZone.uses(of: tile))")
                .font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .opacity(putAway ? 0.45 : (dragging == tile ? 0.35 : 1))
        .contentShape(Rectangle())
        .onDrag {
            dragging = tile
            return NSItemProvider(object: tile.rawValue as NSString)
        }
        .onDrop(of: [.text], delegate: TileDrop(target: tile, dragging: $dragging, model: model))
        .contextMenu { tileMenu(tile) }
        .help(putAway ? "\(model.name(of: tile)) — put away; the plus brings it back"
                      : "\(model.name(of: tile)) — used \(model.landingZone.uses(of: tile))×; drag to reorder, the minus puts it away")
    }

    /// The face alone: the icon in its circle, with nothing to press.
    private func tileFace(_ tile: LandingZone.Tile) -> some View {
        tileIcon(tile)
            .frame(width: 28, height: 28)
            .background {
                Circle().fill(Color.primary.opacity(0.08))
                    .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1))
            }
    }

    @ViewBuilder
    private func tileIcon(_ tile: LandingZone.Tile) -> some View {
        switch tile {
        case .reveal:
            AppIcons.finder.resizable().aspectRatio(contentMode: .fit).frame(width: 19, height: 19)
        case .markUp:
            AppIcons.editor.resizable().aspectRatio(contentMode: .fit).frame(width: 19, height: 19)
        case .share:
            Image(systemName: "square.and.arrow.up").resizable().aspectRatio(contentMode: .fit).frame(width: 13, height: 13)
        case .sendTo:
            if let symbol = model.aiProvider.kind.symbol {
                Image(systemName: symbol).resizable().aspectRatio(contentMode: .fit).frame(width: 13, height: 13)
            } else if let mark = AppIcons.icon(for: model.aiProvider.kind) {
                mark.resizable().aspectRatio(contentMode: .fit).frame(width: 19, height: 19)
            } else {
                Text(String(model.assistantName.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 19, height: 19)
                    .background(Circle().fill(ShotPalette.accent))
            }
        case .editTitle:
            Image(systemName: "pencil").resizable().aspectRatio(contentMode: .fit).frame(width: 13, height: 13)
        case .fileAs:
            Image(systemName: "tag").resizable().aspectRatio(contentMode: .fit).frame(width: 13, height: 13)
        }
    }

    /// Every tile's right-click: what a plain click should do, whether this
    /// tile belongs in the row, and the way into arranging it.
    @ViewBuilder
    private func tileMenu(_ tile: LandingZone.Tile) -> some View {
        // Send to carries two jobs, not one: the plain hand-off and the code
        // brief. They reach the same assistant, so they share a mark rather
        // than taking two places in the row (2026-09-15).
        if tile == .sendTo {
            Button(model.title(of: .sendToAssistant)) { heroShot.map(model.sendToAssistant) }
            Button(model.title(of: .sendPicture)) { heroShot.map(model.sendPicture) }
            Button("Rebuild as code") { heroShot.map { model.copyCodeBrief(for: $0) } }
            Divider()
            Menu("Assistant") {
                ForEach(AIProvider.Kind.allCases.filter { $0 != .offline }, id: \.self) { kind in
                    Button(model.aiProvider.kind == kind ? "\(kind.name)  ✓" : kind.name) {
                        model.setAIProvider(AIProvider(kind: kind))
                    }
                }
            }
            Menu("A click does") {
                Button(model.defaultAction == .sendToAssistant
                       ? "\(model.title(of: .sendToAssistant))  ✓" : model.title(of: .sendToAssistant)) {
                    model.defaultAction = .sendToAssistant
                }
                Button(model.defaultAction == .sendPicture
                       ? "\(model.title(of: .sendPicture))  ✓" : model.title(of: .sendPicture)) {
                    model.defaultAction = .sendPicture
                }
                Button(model.defaultAction == .rebuildAsCode
                       ? "Rebuild as code  ✓" : "Rebuild as code") {
                    model.defaultAction = .rebuildAsCode
                }
            }
            Divider()
        } else if tile == .markUp {
            // Preview is nested here rather than standing beside it: it does one
            // thing, and the editor does that thing and the one Preview won't.
            Button("Edit with ShotScribe…") { heroShot.map(model.markUp) }
            Button("Open in Preview") { heroShot.map(model.openInPreview) }
            Divider()
            if model.defaultAction == .markUp { Text("Default ✓") }
            else { Button("Set as default") { model.defaultAction = .markUp } }
            Divider()
        } else if let action = ShotScribeModel.action(for: tile) {
            if model.defaultAction == action { Text("Default ✓") }
            else { Button("Set as default") { model.defaultAction = action } }
            Divider()
        }
        if model.landingZone.hidden.contains(tile) {
            Button("Show \(model.name(of: tile))") { _ = model.setTileHidden(tile, false) }
        } else {
            Button("Hide \(model.name(of: tile))") { _ = model.setTileHidden(tile, true) }
                .disabled(shownTiles.count <= 1)
        }
        Button(model.arrangingTiles ? "Done arranging" : "Arrange tiles…") {
            model.arrangingTiles.toggle()
        }
    }

    private var arrangeBar: some View {
        HStack(spacing: 10) {
            Button("Done") { model.arrangingTiles = false }
                .buttonStyle(CapsuleButtonStyle())
                .lineLimit(1).fixedSize()
            Button("Reset") { model.resetLandingZone() }
                .buttonStyle(.link).font(.caption2)
                .help("Back to the row ShotScribe ships. The counts stay.")
        }
    }

    private func fileAsMenu(_ shot: IndexedShot) -> some View {
        Menu {
            Button("+  New Tag…") { model.askForFileTab() }
            Divider()
            // A tag already on the shot is ticked and comes off when picked.
            // Disabling it, which is what this did, made the first guess final.
            ForEach(model.vocabulary, id: \.self) { tag in
                Button(model.isTagged(shot, tag) ? "\(tag)  ✓" : tag) {
                    model.toggleTag(shot, tag)
                }
            }
        } label: {
            Image(systemName: "tag").resizable().aspectRatio(contentMode: .fit)
                .frame(width: 13, height: 13).frame(width: 28, height: 28).contentShape(Circle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .frame(width: 28, height: 28)
        .background {
            Circle().fill(Color.primary.opacity(0.08))
                .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        }
        .modifier(NamedOnHover(title: "Tag"))
    }

    @ViewBuilder
    func shotMenu(_ shot: IndexedShot) -> some View { ShotMenu(model: model, shot: shot) }

    // MARK: Inspector

    private enum InspectorTab: String, CaseIterable, Identifiable {
        case folder, rename, ai, file, keep
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .folder: return "folder"
            case .rename: return "wand.and.stars"
            case .ai:     return "sparkles"
            case .file:   return "tag"
            case .keep:   return "archivebox"
            }
        }
        var title: String { self == .ai ? "AI" : rawValue.capitalized }
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
                    case .ai:     aiPane
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
            if model.backlogCount > 0 {
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(model.backlogCount) never named").font(.callout.weight(.semibold))
                    Text("Captures that landed while ShotScribe was not watching still carry their raw macOS names. Read a name for each, then choose which to keep.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.startBacklog() } label: {
                        Label("Name the backlog…", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                    .disabled(model.backlog != nil)
                }
            }
        }
    }

    private var renamePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            paneHead("Rename", "What happens to a capture the moment it lands, and how it is spelled.")
            watchToggle
            captureCardToggle
            if model.showsCaptureCard { systemThumbnailToggle }
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
            Divider().padding(.vertical, 4)
            nameFields
        }
    }

    /// The AI tab: who titles a capture. One picker, the fields the kind needs,
    /// a line saying whether it can run here and where the text goes, and a
    /// button that proves it on the newest capture without renaming anything.
    private var aiPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            paneHead("AI", "Who titles a capture — an assistant you already use, or none.")
            Picker("Titler", selection: $kindDraft) {
                ForEach(AIProvider.Kind.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onAppear { kindDraft = model.aiProvider.kind }
            .onChange(of: kindDraft) { kind in
                if kind != model.aiProvider.kind {
                    model.setAIProvider(AIProvider(kind: kind, model: kind.defaultModel))
                }
            }
            .onChange(of: model.aiProvider.kind) { kind in
                if kindDraft != kind { kindDraft = kind }
            }
            let availability = model.aiAvailability
            HStack(alignment: .top, spacing: 7) {
                Circle().fill(availability.isReady ? Color.green : ShotPalette.warning)
                    .frame(width: 6, height: 6).padding(.top, 5)
                Text(availability.text).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            aiFields
            Text(model.aiProvider.kind.whereTextGoes)
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let suggested = AIProvider.suggested(from: model.llmPreference), suggested != model.aiProvider {
                HStack(spacing: 6) {
                    Text("This Mac prefers \(suggested.kind.name).").font(.caption2).foregroundStyle(.secondary)
                    Button("Use it") { model.setAIProvider(suggested) }.controlSize(.mini)
                }
            }
            if model.aiProvider.kind != .offline {
                Button { model.tryTitler() } label: {
                    Label(model.aiTrying ? "Trying…" : "Try it on the newest capture", systemImage: "sparkles")
                }
                .buttonStyle(CapsuleButtonStyle(prominent: true))
                .disabled(model.aiTrying)
                .padding(.top, 4)
            }
            if let trial = model.aiTrial {
                Text(trial).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    /// The fields a kind needs, bound straight to the stored setting.
    @ViewBuilder private var aiFields: some View {
        let kind = model.aiProvider.kind
        switch kind {
        case .offline:
            EmptyView()
        case .claude:
            aiField("Model (optional)", placeholder: "the CLI’s default", keyPath: \.model)
            if !model.claudeAvailable {
                Link("Get Claude Code — titles run on your own account",
                     destination: URL(string: "https://claude.com/claude-code")!).font(.caption2)
            }
        case .codex, .gemini, .cursor, .ollama, .command:
            if kind == .command {
                Text("Any tool that answers a prompt on the command line — llm, aichat, mods, a team script.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            aiField("Command", placeholder: kind.commandTemplate ?? "tool --flag {prompt}", keyPath: \.command, mono: true)
            Text("{prompt} is the instruction plus the text read off the capture, as one argument. Keep the flags that stop the tool from acting on it.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            aiField("Model", placeholder: kind.defaultModel ?? "optional", keyPath: \.model)
        case .endpoint:
            aiField("Base URL", placeholder: "http://localhost:11434/v1", keyPath: \.endpoint, mono: true)
            aiField("Model", placeholder: "llama3.2, gpt-4o-mini…", keyPath: \.model)
            HStack(spacing: 8) {
                SecureField(model.endpointKeyStored ? "A key is in your Keychain" : "API key (none for a local server)", text: $endpointKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.setEndpointKey(endpointKeyDraft); endpointKeyDraft = "" }
                Button("Save") { model.setEndpointKey(endpointKeyDraft); endpointKeyDraft = "" }
                    .disabled(endpointKeyDraft.isEmpty)
                if model.endpointKeyStored {
                    Button("Remove") { model.setEndpointKey(nil) }
                }
            }
            Text("The key is stored in your login Keychain, never in the settings file.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func aiField(_ label: String, placeholder: String, keyPath: WritableKeyPath<AIProvider, String?>, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption.weight(.medium))
            TextField(placeholder, text: Binding(
                get: { model.aiProvider[keyPath: keyPath] ?? "" },
                set: { new in
                    var p = model.aiProvider
                    p[keyPath: keyPath] = new.isEmpty ? nil : new
                    model.setAIProvider(p)
                }))
            .textFieldStyle(.roundedBorder)
            .font(mono ? .callout.monospaced() : .callout)
        }
    }

    /// The spelling of a name: template, sample, pickers. On the Rename tab
    /// since 1.6, under the switch; it was its own tab until the AI tab
    /// needed the fifth slot.
    private var nameFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spelling").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
            Toggle(isOn: Binding(get: { model.spotlightKeywords }, set: { model.setSpotlightKeywords($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Make the words findable in Spotlight")
                        if model.spotlightBusy { ProgressView().controlSize(.mini) }
                    }
                    Text("Writes each capture's significant words into its file metadata, so a Spotlight search for what a shot showed finds it at once. The words travel with the file when it is shared.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch).controlSize(.small)
            .help("Off by default. On: written to every shot in the library now and to each new one; off: taken off them all.")
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
                // Sixteen words is a lot of little × buttons. "Remove all"
                // empties it in one gesture, and "Shipped list" is the way
                // back — it restores rather than clearing, which is what
                // emptying the field used to do by accident.
                if !model.vocabulary.isEmpty {
                    Button("Remove all") { model.clearVocabulary() }
                        .font(.caption2).buttonStyle(.link)
                }
                Button("Shipped list") { model.restoreVocabulary() }
                    .font(.caption2).buttonStyle(.link)
                    .disabled(model.vocabulary == Tagging.defaultVocabulary)
            }
            if model.vocabulary.isEmpty {
                Text("Nothing to file under. Add a word above, or put the suggested list back.")
                    .font(.caption2).foregroundStyle(ShotPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
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
            keepRow("Deleted captures go to", destinationDetail) { destinationPicker }
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
        case .trash:             return "The Trash — Finder’s Put Back undoes it. The bin on every shot does the same."
        case .delete:            return "Deleted outright: no Trash, no Put Back. The bin on every shot does the same."
        case .archive(let path): return (path as NSString).abbreviatingWithTildeInPath + " for clean-up; a single shot’s bin still uses the Trash."
        }
    }

    private enum DestinationChoice: Hashable { case trash, delete, archive }

    private var destinationPicker: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Picker("", selection: Binding<DestinationChoice>(
                get: {
                    switch model.keepPolicy.destination {
                    case .trash:   return .trash
                    case .delete:  return .delete
                    case .archive: return .archive
                    }
                },
                set: { choice in
                    switch choice {
                    case .trash:   model.keepPolicy.destination = .trash
                    case .delete:  model.keepPolicy.destination = .delete
                    case .archive: model.chooseArchiveFolder()
                    }
                })) {
                Text("Trash").tag(DestinationChoice.trash)
                Text("Delete").tag(DestinationChoice.delete)
                Text("Archive").tag(DestinationChoice.archive)
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
                Text("\(plan.moves.count) screenshot\(plan.moves.count == 1 ? "" : "s") in \(model.folder.lastPathComponent) \(plan.destination == .delete ? "would be deleted for good" : "would move to \(plan.destination.label)"): \(plan.duplicates) duplicate\(plan.duplicates == 1 ? "" : "s"), \(plan.stale) older than you keep.")
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

    /// **The backlog, read and waiting for a yes.**
    ///
    /// Every raw capture is listed at once, and names arrive as they are read —
    /// so the operator watches the list fill rather than a spinner. Each row can
    /// be unticked; only ticked rows are renamed, and only when asked. What has
    /// been read can be applied before the rest finishes.
    private func backlogPreview(_ run: ShotScribeModel.BacklogRun) -> some View {
        let total = run.pending.count
        let read = run.read.count
        let chosen = run.chosen.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(total == 0 ? "Nothing to name" : "Naming \(total) older screenshot\(total == 1 ? "" : "s")")
                    .font(.system(size: 15, weight: .bold)).tracking(-0.3)
                if run.reading {
                    Text("\(read) of \(total) read").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else if run.applying {
                    Text("\(run.applied) of \(chosen) renamed").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 8)
                if run.reading {
                    Button("Stop reading") { model.stopBacklogReading() }
                        .buttonStyle(CapsuleButtonStyle(quiet: true))
                        .help("Keep the names read so far; don't read the rest.")
                }
                Button(total == 0 ? "Done" : "Cancel") { model.cancelBacklog() }
                    .buttonStyle(CapsuleButtonStyle(quiet: true))
                    .disabled(run.applying)
            }
            if total == 0 {
                Text("Every capture in \(model.folder.lastPathComponent) already has a name.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                if run.reading || run.applying {
                    ProgressView(value: Double(run.reading ? read : run.applied),
                                 total: Double(max(run.reading ? total : chosen, 1)))
                        .progressViewStyle(.linear)
                        .tint(ShotPalette.accent)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(run.pending, id: \.path) { url in
                            backlogRow(url: url, proposal: run.read[url.path],
                                       ticked: !run.excluded.contains(url.path),
                                       locked: run.applying)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 360)
                HStack(spacing: 10) {
                    Button {
                        model.applyBacklog()
                    } label: {
                        Label(run.applying ? "Renaming…" : "Rename \(chosen)", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                    .disabled(chosen == 0 || run.applying)
                    Button("All") { model.setBacklogAll(true) }
                        .buttonStyle(.link).font(.caption).disabled(run.applying)
                    Button("None") { model.setBacklogAll(false) }
                        .buttonStyle(.link).font(.caption).disabled(run.applying)
                    Spacer(minLength: 8)
                    Text(run.reading
                         ? "Renaming now takes only the rows already read."
                         : "Only ticked rows are renamed. Files you named yourself are never touched.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeOut(duration: 0.18), value: read)
    }

    private func backlogRow(url: URL, proposal: Backlog.Proposal?, ticked: Bool, locked: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                model.toggleBacklog(url.path)
            } label: {
                Image(systemName: ticked && proposal != nil ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(ticked && proposal != nil ? AnyShapeStyle(ShotPalette.accent) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .disabled(proposal == nil || locked)

            AspectThumbnail(path: url.path, aspect: 16.0 / 10.0, pixels: 160)
                .frame(width: 64, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.separator, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text((url.lastPathComponent as NSString).deletingPathExtension)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
                if let proposal {
                    HStack(spacing: 6) {
                        Text((proposal.name as NSString).deletingPathExtension)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(ticked ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            .strikethrough(!ticked)
                            .lineLimit(1).truncationMode(.middle)
                        ForEach(proposal.tags, id: \.self) { tag in
                            Text(tag).font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .foregroundStyle(ShotPalette.accent)
                                .background(Capsule().fill(ShotPalette.accent.opacity(0.14)))
                        }
                    }
                } else {
                    Text("Reading…").font(.callout).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .opacity(proposal == nil ? 0.6 : 1)
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

    /// The card's off switch. A panel that appears on its own and cannot be
    /// turned off is an imposition, so it gets a switch beside the thing that
    /// triggers it.
    private var captureCardToggle: some View {
        Toggle(isOn: $model.showsCaptureCard) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Show a card when a capture is named")
                Text("Slides up from the bottom for a few seconds, with the new name and a way into Preview.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    /// macOS's own thumbnail, muted from here. Beside the card's switch because
    /// the two are one decision: which card you want after a capture, if any.
    private var systemThumbnailToggle: some View {
        Toggle(isOn: Binding(get: { !systemThumbnailOff },
                             set: { off in
                                 systemThumbnailOff = !off
                                 SystemThumbnail.set(off)
                             })) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Let macOS show its own thumbnail too")
                Text("Apple's appears bottom right before the rename, so it can only ever show an unnamed file. Off is a change to a macOS setting, from your next capture on.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

/// **The straight deck.** One day on one line: the cards overlap, and the one
/// under the cursor rises out of the row while the cards after it step aside.
/// It is the "Cards Fan-Out" reference Josh sent on 2026-09-14 with the arch
/// taken out — every card upright, every card on the same baseline.
///
/// The numbers are his, chosen off the bake-off on localhost:9013 rather than
/// guessed: 200pt cards, 40pt of overlap, a 22pt lift, neighbours stepping 60pt,
/// a 10pt corner and the reference's own easing over 0.6s.
///
/// Only the cards **after** the hovered one move. The bake-off's deck was
/// centred, so it could open in both directions; a day row is anchored at its
/// leading edge, and pushing the earlier cards left would walk them off it.
private enum Deck {
    /// The size the adaptive grid gave a tile at the usual window width, and
    /// the tiles' own 4:3 — the carousel replaced that grid, so a card should
    /// not be the smaller thing.
    static let width: CGFloat = 260
    static let height: CGFloat = 195
    static let overlap: CGFloat = 40
    static let lift: CGFloat = 22
    static let stepAside: CGFloat = 60
    static let corner: CGFloat = 10
    /// The bake-off's CSS blur, which is about twice a SwiftUI shadow radius.
    static let shadow: CGFloat = 25
    static var shadowRadius: CGFloat { shadow / 2 }
    static let motion = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.6)
}

/// Which row the cursor is on, and where that row sits — published by the row,
/// read by the list so it can draw one preview above all of them.
private struct HoveredRow: PreferenceKey {
    struct Item {
        let path: String
        let anchor: Anchor<CGRect>
    }
    static var defaultValue: Item? { nil }
    static func reduce(value: inout Item?, nextValue: () -> Item?) {
        if let next = nextValue() { value = next }
    }
}

/// One line in the list. Hovering shades the row and publishes where the row
/// is; the list itself draws the capture underneath it, at the carousel's card
/// size, so "a card" is one size everywhere in the window. The list is names
/// and matched text, which is fast to scan and says nothing about what the
/// shot *looked* like.
///
/// The row does not draw the preview itself — see `shotsList`. And the preview
/// takes no hits: without that, moving onto it would end the hover that
/// summoned it and the thing would flicker under the cursor.
private struct ShotRow: View {
    let shot: IndexedShot
    @ObservedObject var model: ShotScribeModel
    let snippet: String?
    @State private var hovered = false

    var body: some View {
        let picked = model.selected.contains(shot.path)
        Button { model.click(shot) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if model.selecting {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(picked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                }
                Text(shot.name).font(.callout.weight(.medium))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 180, alignment: .leading)
                if let snippet, !snippet.isEmpty {
                    Text(snippet).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 8)
                ForEach(shot.tags ?? [], id: \.self) { tag in
                    TagChip(tag: tag) { model.filter(tag: tag) }
                }
                Text(shot.captured, format: .dateTime.year().month().day())
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                DeletePill(size: 12, quiet: true, forGood: model.deletesForGood) { model.trash(shot) }
                    .id(shot.path)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.07 : 0)))
            .padding(.horizontal, -8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .anchorPreference(key: HoveredRow.self, value: .bounds) { anchor in
            hovered && !model.selecting ? HoveredRow.Item(path: shot.path, anchor: anchor) : nil
        }
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.14), value: hovered)
        .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
        // The hint, and only the hint. The path was the noise — the preview
        // already says which shot this is, and Reveal in Finder is where a
        // path belongs.
        .help("Drag to attach a copy elsewhere.")
        .contextMenu { ShotMenu(model: model, shot: shot) }
    }
}

private struct DeckRow: View {
    let shots: [IndexedShot]
    @ObservedObject var model: ShotScribeModel
    @State private var hovered: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: -Deck.overlap) {
                ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                    let isUp = hovered == shot.path
                    let after = hovered.flatMap { h in shots.firstIndex { $0.path == h } }
                        .map { index > $0 } ?? false
                    DeckCard(shot: shot, model: model, raised: isUp)
                        .offset(x: after ? Deck.stepAside : 0, y: isUp ? -Deck.lift : 0)
                        .scaleEffect(isUp ? 1.05 : 1, anchor: .bottom)
                        .brightness(hovered != nil && !isUp ? -0.05 : 0)
                        // The leading card sits on top, so the row reads newest
                        // first; whichever is raised comes over all of them.
                        .zIndex(isUp ? 999 : Double(shots.count - index))
                        .onHover { inside in
                            if inside { hovered = shot.path }
                            else if hovered == shot.path { hovered = nil }
                        }
                }
            }
            // Room for the lift and the shadow, and for the last card's step.
            .padding(.vertical, 24)
            .padding(.trailing, Deck.stepAside + 8)
            .animation(Deck.motion, value: hovered)
        }
        .padding(.bottom, 4)
    }
}

/// One card in the deck: the same capture, the same click, the same menu and
/// the same drag-out as a tile — at the deck's fixed size.
private struct DeckCard: View {
    let shot: IndexedShot
    @ObservedObject var model: ShotScribeModel
    let raised: Bool
    @State private var leaving = false

    var body: some View {
        let picked = model.selected.contains(shot.path)
        Button { model.click(shot) } label: {
            AspectThumbnail(path: shot.path, aspect: Deck.width / Deck.height, pixels: 620)
                .frame(width: Deck.width, height: Deck.height)
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
                    .padding(.horizontal, 10).padding(.bottom, 8).padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.black.opacity(0.88), .clear],
                                               startPoint: .bottom, endPoint: .top))
                    .opacity(raised || model.selecting ? 1 : 0)
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
                    if raised, !model.selecting {
                        DeletePill(onImage: true, forGood: model.deletesForGood) {
                            withAnimation(.easeIn(duration: 0.18)) { leaving = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { model.trash(shot) }
                        }
                        .id(shot.path)
                        .padding(7)
                        .transition(.opacity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Deck.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Deck.corner, style: .continuous)
                    .strokeBorder(picked ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                                  lineWidth: picked ? 2 : 1))
                .shadow(color: .black.opacity(raised ? 0.45 : 0.3),
                        radius: Deck.shadowRadius, y: Deck.shadowRadius * 0.45)
                .opacity(leaving ? 0 : 1)
                .scaleEffect(leaving ? 0.86 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { ShotMenu(model: model, shot: shot) }
        // Drag it out as the file itself, the way the hero does.
        .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
        .help("Drag to attach a copy elsewhere.")
    }
}

/// A tag, drawn as a tag: the glyph, the word, and a tooltip that says what it
/// is and what clicking does. It was a bare pill, and a pill that says "code"
/// beside a feature called code reads as a button. Nothing here runs anything;
/// it filters.
/// The right-click menu on a screenshot — the landing zone's functions, in
/// the same order, wherever a shot is: a tile, a list row, the hero, the
/// popover. The click action is marked so a person can see what a plain
/// click will do without trying it.
private struct ShotMenu: View {
    @ObservedObject var model: ShotScribeModel
    let shot: IndexedShot

    private func title(_ a: ShotScribeModel.ShotAction) -> String {
        model.defaultAction == a ? "\(model.title(of: a))  ✓ default" : model.title(of: a)
    }

    // What ShotScribe adds comes first, what the Mac already does next, the
    // bin last (Josh, 2026-09-17: "ShotScribe Benefits first then the system
    // defaults, send to trash last").
    var body: some View {
        Button(title(.markUp) + "…") { model.markUp(shot) }
        Button(title(.sendToAssistant)) { model.sendToAssistant(shot) }
        Button(title(.sendPicture)) { model.sendPicture(shot) }
        Button(title(.rebuildAsCode)) { model.copyCodeBrief(for: shot) }
        if model.taggingEnabled {
            Menu("Tag") {
                Button("+  New Tag…") { model.askForFileTab() }
                Divider()
                ForEach(model.vocabulary, id: \.self) { tag in
                    Button(model.isTagged(shot, tag) ? "\(tag)  ✓" : tag) {
                        model.toggleTag(shot, tag)
                    }
                }
            }
        }
        if shot.original != nil, !model.otherInstanceRunning {
            Button("Restore original name") { model.undo(shot) }
        }
        Divider()
        Button(title(.reveal)) { model.reveal(shot) }
        Button("Open in Preview") { model.openInPreview(shot) }
        ShareLink(item: shot.url) { Text("Share…") }
        Divider()
        Button(model.deletesForGood ? "Delete for good" : "Move to Trash", role: .destructive) { model.trash(shot) }
    }
}

/// The bin that eats the label. Idle it is a bin; hover unfurls the word
/// "Delete" beside it; the click sends the letters into the bin one after
/// another — the level inside rises with each — then the pill furls to the bin
/// alone, an arc turns for a beat, seals, and the shot goes to the Trash. The
/// move itself takes milliseconds, so the arc is a beat rather than a
/// measurement: a wait should read as a wait, not a flicker. Finder's Put Back
/// undoes it, and the help says so. (After the reel Josh sent, 2026-09-13.)
private struct DeletePill: View {
    enum Stage: Equatable { case idle, eating, furled, pending, done }
    var size: CGFloat = 13
    /// Tiles and the hero: white on a glass capsule over the image.
    var onImage = false
    /// List rows: faint until hovered, so a column of bins is not a column of
    /// warnings.
    var quiet = false
    /// The Keep tab's choice, so the help tells the truth about Put Back.
    var forGood = false
    /// What the bin eats. A day's bin says "Delete 12", so the count is read
    /// before the click rather than after it.
    var word = "Delete"
    let action: () -> Void

    @State private var stage = Stage.idle
    @State private var hovering = false
    @State private var flying: Set<Int> = []
    @State private var landed = 0
    @State private var spin = 0.0
    private var letters: [Character] { Array(word) }

    private var wordShown: Bool { (stage == .idle && hovering) || stage == .eating }

    var body: some View {
        Button(action: fire) {
            HStack(spacing: 5) {
                if wordShown {
                    HStack(spacing: 0) {
                        ForEach(letters.indices, id: \.self) { i in
                            Text(String(letters[i]))
                                .opacity(flying.contains(i) ? 0 : 1)
                                .modifier(FlyToBin(progress: flying.contains(i) ? 1 : 0,
                                                   dx: CGFloat(letters.count - i) * 6.5 + 9))
                        }
                    }
                    .font(.caption.weight(.semibold)).fixedSize()
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .trailing)))
                }
                ZStack {
                    TrashCan(open: hovering || stage == .eating, flung: stage == .eating,
                             fill: Double(landed) / Double(max(letters.count, 1)))
                        .frame(width: size, height: size)
                    if stage == .pending || stage == .done {
                        Circle().trim(from: 0, to: stage == .done ? 1 : 0.3)
                            .stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                            .frame(width: size + 9, height: size + 9)
                            .rotationEffect(.degrees(spin))
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, wordShown ? 8 : 5).padding(.vertical, 4)
            .background {
                // Over an image the bin sits on a dark scrim, not glass: white on
                // a light capture was invisible (Josh, 2026-09-13). The scrim is
                // what Photos does with its hover controls.
                if onImage {
                    Capsule().fill(Color.black.opacity(hovering ? 0.78 : 0.62))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                } else {
                    Capsule().fill(Color.primary.opacity(hovering || stage != .idle ? 0.1 : 0))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(onImage ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .opacity(quiet && !hovering && stage == .idle ? 0.55 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: wordShown)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .help(forGood ? "Delete for good — there is no Put Back. (Keep tab: Deleted captures go to.)"
                      : "Move to the Trash. Finder’s Put Back undoes it.")
    }

    /// Back to a bin that can be clicked again.
    ///
    /// The view usually leaves with the shot it deleted — but in a lazy stack
    /// SwiftUI reuses it for whatever moves into that slot, and `@State` comes
    /// along for the ride. Left at `.done`, the next shot's bin is dead: the
    /// guard in `fire` swallows every click (Josh, 2026-09-15: "I delete one
    /// image and then try to delete a second and the button no longer works
    /// until I click somewhere else").
    private func reset() {
        stage = .idle
        flying.removeAll()
        landed = 0
        spin = 0
    }

    private func fire() {
        guard stage == .idle else { return }
        stage = .eating
        let step = 0.05, flight = 0.34
        for i in letters.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i)) {
                withAnimation(.easeIn(duration: flight)) { _ = flying.insert(i) }
                DispatchQueue.main.asyncAfter(deadline: .now() + flight * 0.8) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { landed += 1 }
                }
            }
        }
        let eaten = step * Double(letters.count) + flight
        DispatchQueue.main.asyncAfter(deadline: .now() + eaten) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { stage = .furled }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                stage = .pending
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) { spin = 360 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.28)) { stage = .done }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        action()
                        reset()
                    }
                }
            }
        }
    }
}

/// One letter's flight into the bin: an arc up and over, shrinking as it goes.
/// A `GeometryEffect` so the whole path is one animatable number at the
/// macOS 13 floor (keyframes are 14+).
private struct FlyToBin: GeometryEffect {
    var progress: CGFloat
    var dx: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = progress
        let scale = 1 - 0.75 * t
        let x = dx * t + size.width / 2 * (1 - scale)
        let y = -11 * sin(.pi * t) + 2 * t + size.height / 2 * (1 - scale)
        return ProjectionTransform(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: x, y: y)))
    }
}

/// The can and its lid as two strokes, so the lid can move on its own: it
/// hinges at the right, lifts a little for a hover and swings up for the click.
private struct TrashCan: View {
    var open: Bool
    var flung: Bool
    /// How full it is, 0…1: rises as the letters land.
    var fill: Double = 0

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let stroke = StrokeStyle(lineWidth: max(1.5, w * 0.12), lineCap: .round, lineJoin: .round)
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w * 0.17, y: h * 0.33))
                    p.addLine(to: CGPoint(x: w * 0.83, y: h * 0.33))
                    p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.92))
                    p.addQuadCurve(to: CGPoint(x: w * 0.24, y: h * 0.92), control: CGPoint(x: w * 0.5, y: h * 0.99))
                    p.closeSubpath()
                }
                .fill(.primary.opacity(0.32))
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: max(0, h * 0.62 * fill))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: fill)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.17, y: h * 0.33))
                    p.addLine(to: CGPoint(x: w * 0.83, y: h * 0.33))
                    p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.92))
                    p.addQuadCurve(to: CGPoint(x: w * 0.24, y: h * 0.92), control: CGPoint(x: w * 0.5, y: h * 0.99))
                    p.closeSubpath()
                    p.move(to: CGPoint(x: w * 0.41, y: h * 0.47)); p.addLine(to: CGPoint(x: w * 0.43, y: h * 0.80))
                    p.move(to: CGPoint(x: w * 0.59, y: h * 0.47)); p.addLine(to: CGPoint(x: w * 0.57, y: h * 0.80))
                }
                .stroke(style: stroke)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.06, y: h * 0.25)); p.addLine(to: CGPoint(x: w * 0.94, y: h * 0.25))
                    p.move(to: CGPoint(x: w * 0.37, y: h * 0.25)); p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.10))
                    p.addLine(to: CGPoint(x: w * 0.60, y: h * 0.10)); p.addLine(to: CGPoint(x: w * 0.63, y: h * 0.25))
                }
                .stroke(style: stroke)
                .rotationEffect(.degrees(flung ? -42 : open ? -16 : 0), anchor: UnitPoint(x: 0.94, y: 0.25))
                .offset(y: flung ? -h * 0.16 : open ? -h * 0.07 : 0)
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.58), value: open)
            .animation(.spring(response: 0.22, dampingFraction: 0.5), value: flung)
        }
    }
}

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

/// The title in the landing zone, editable in place: click it (or the pencil
/// tile) and it becomes a field; Return renames the file with the stamp kept,
/// Escape puts it back. The fastest fix for a rename the person would not
/// have written.
private struct HeroTitle: View {
    let shot: IndexedShot
    @Binding var editing: Bool
    let onRename: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    init(shot: IndexedShot, editing: Binding<Bool>, onRename: @escaping (String) -> Void) {
        self.shot = shot; _editing = editing; self.onRename = onRename
    }

    var body: some View {
        Group {
            if editing {
                TextField("Title", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(ShotPalette.accent.opacity(0.5), lineWidth: 1))
                    .padding(.horizontal, -8)
                    .onAppear { draft = Sessions.stem(of: shot.name); focused = true }
            } else {
                Text(Sessions.stem(of: shot.name))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = true }
                    .help("Click to edit the title")
            }
        }
        .font(.system(size: 22, weight: .bold)).tracking(-0.6)
        .onChange(of: shot.path) { _ in editing = false }
    }

    private func commit() {
        let title = draft.trimmingCharacters(in: .whitespaces)
        editing = false
        if !title.isEmpty, title != Sessions.stem(of: shot.name) { onRename(title) }
    }
}

/// One action in the landing zone: a round tile carrying the icon of the
/// service it reaches, named on hover.
private struct ActionTile: View {
    let name: String
    let icon: Image?
    let monogram: String?
    let art: Bool
    /// The click action this tile can become: right-click, "Set as the click
    /// action". The one that is wears a soft accent shadow.
    let sets: ShotScribeModel.ShotAction?
    let model: ShotScribeModel?
    let action: () -> Void

    init(_ name: String, icon: Image, art: Bool = false, sets: ShotScribeModel.ShotAction? = nil,
         model: ShotScribeModel? = nil, action: @escaping () -> Void) {
        self.name = name; self.icon = icon; self.monogram = nil; self.art = art
        self.sets = sets; self.model = model; self.action = action
    }

    /// A tile for a name with no mark on this Mac: its initial, set like a
    /// contact's, until the brand's own artwork is in `assets/brands/`.
    init(_ name: String, monogram: String, sets: ShotScribeModel.ShotAction? = nil,
         model: ShotScribeModel? = nil, action: @escaping () -> Void) {
        self.name = name; self.icon = nil; self.monogram = String(monogram.prefix(1)).uppercased()
        self.art = true; self.sets = sets; self.model = model; self.action = action
    }

    /// What the hover bubble says: the name, whether a click does this, and —
    /// for the tile that hides a second job — that more is a right-click away.
    /// There is no macOS affordance for "a right-click has more here", so the
    /// bubble that already names the tile says it. Josh, 2026-09-15: "not sure
    /// how to convey that to a user so they would know its there".
    private var bubble: String {
        var words = name
        if isDefault { words += " — default" }
        if sets == .sendToAssistant || sets == .markUp { words += " · right-click for more" }
        return words
    }

    private var isDefault: Bool {
        guard let sets, let model else { return false }
        // Send to owns Rebuild as code as well, so it wears the halo for either.
        if sets == .sendToAssistant {
            return model.defaultAction == .sendToAssistant || model.defaultAction == .rebuildAsCode
        }
        return model.defaultAction == sets
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    icon.resizable().aspectRatio(contentMode: .fit)
                        .frame(width: art ? 19 : 13, height: art ? 19 : 13)
                } else if let monogram {
                    Text(monogram)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 19, height: 19)
                        .background(Circle().fill(ShotPalette.accent))
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(TileButtonStyle())
        // The default wears a halo *outside* its circle — the icon itself is
        // left alone; a 2 pt green ring sits 4 pt off the edge, with a glow,
        // so it reads in light mode as well as dark.
        .overlay(
            Circle()
                .strokeBorder(ShotPalette.chosen, lineWidth: 2)
                .padding(-4)
                .shadow(color: ShotPalette.chosen.opacity(0.7), radius: 6)
                .opacity(isDefault ? 1 : 0)
        )
        .modifier(NamedOnHover(title: bubble))
    }
}

/// Dragging one tile onto another puts it there, live, while the drag is still
/// in the air — the row reorders under the cursor rather than on release.
private struct TileDrop: DropDelegate {
    let target: LandingZone.Tile
    @Binding var dragging: LandingZone.Tile?
    let model: ShotScribeModel

    func dropEntered(info: DropInfo) {
        guard let moving = dragging, moving != target else { return }
        withAnimation(.easeOut(duration: 0.18)) { model.moveTile(moving, onto: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background {
                Circle().fill(Color.primary.opacity(0.08))
                    .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1))
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Real app icons, so a tile reflects its service: Finder's face for Reveal
/// in Finder, Claude's mark for Send to Claude (a glyph when it is not installed).
enum AppIcons {
    static let finder = Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app"))
    static let preview = Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Applications/Preview.app"))
    /// Edit with ShotScribe: its own mark, drawn for it (assets/brands/editor.svg).
    static var editor: Image { BrandArt.image("editor") ?? Image(systemName: "pencil.tip.crop.circle") }

    /// ShotScribe's own artwork, for the button that brings its window up.
    static let shotScribe = Image(nsImage: NSApp?.applicationIconImage
        ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))

    /// The titler's mark: the brand mark embedded from `assets/brands/` when
    /// there is one (it is the mark people know), else the installed app's own
    /// icon (Claude.app, Cursor.app, Ollama.app), else nothing and the tile
    /// draws an initial. Never a generic glyph for a known name.
    static func icon(for kind: AIProvider.Kind) -> Image? {
        if let brand = kind.brand, let mark = BrandArt.image(brand) { return mark }
        switch kind {
        case .claude: return app("com.anthropic.claudefordesktop")
        case .cursor: return app("com.todesktop.230313mzl4w4u92")
        case .ollama: return app("com.electron.ollama")
        default:      return nil
        }
    }

    private static var cache: [String: Image?] = [:]
    private static func app(_ bundleID: String) -> Image? {
        if let hit = cache[bundleID] { return hit }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { Image(nsImage: NSWorkspace.shared.icon(forFile: $0.path)) }
        cache[bundleID] = image
        return image
    }
}

/// The brand marks shipped inside the binary — see `assets/brands/README.md`.
private enum BrandArt {
    private static var cache: [String: Image?] = [:]
    static func image(_ name: String) -> Image? {
        if let hit = cache[name] { return hit }
        let image = BrandArtData.png[name]
            .flatMap { Data(base64Encoded: $0) }
            .flatMap { NSImage(data: $0) }
            .map { ns -> Image in
                // A single-colour mark is a template: it takes the tile's
                // foreground, so it reads in light and dark alike.
                ns.isTemplate = BrandArtData.monochrome.contains(name)
                return Image(nsImage: ns)
            }
        cache[name] = image
        return image
    }
}

/// Share, unfolding in place: one capsule that opens into the Mac's own
/// destinations for this file — AirDrop, Messages, Mail, Notes, whatever is
/// installed — each named the moment it is hovered, with the full picker one
/// click further as "More". The idiom is the pill Josh sent on 2026-09-12 that
/// becomes a row of icons; here the icons are real services, not logos.
private struct ShareRow: View {
    let url: URL
    /// The landing zone's tally: opening the pill is the use of this tile.
    var onOpen: () -> Void = {}
    @State private var open = false
    @State private var services: [NSSharingService] = []

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if open {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { open = false }
                } else {
                    onOpen()
                    services = Array(ShareRow.destinations(for: url).prefix(6))
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { open = true }
                }
            } label: {
                Image(systemName: "square.and.arrow.up").resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 13, height: 13).frame(width: 20, height: 20)
                    .foregroundColor(open ? ShotPalette.accent : .primary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(NamedOnHover(title: open ? "" : "Share"))

            if open {
                ForEach(Array(services.enumerated()), id: \.offset) { _, service in
                    Button {
                        service.perform(withItems: [url])
                        withAnimation(.easeOut(duration: 0.2)) { open = false }
                    } label: {
                        Image(nsImage: service.image).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16).frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(NamedOnHover(title: service.title))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
                // Everything else the Mac can share to: the system picker.
                ShareLink(item: url) {
                    Image(systemName: "ellipsis").frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(NamedOnHover(title: "More…"))
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, open ? 8 : 4).frame(height: 28)
        .background {
            Capsule().fill(Color.primary.opacity(open ? 0.1 : 0.08))
                .overlay(Capsule().strokeBorder(open ? ShotPalette.accent.opacity(0.35) : .white.opacity(0.1), lineWidth: 1))
        }
    }

    /// `sharingServices(forItems:)` is deprecated at 13 in favour of a menu item,
    /// which cannot be laid out as a row. It still answers, and nothing else
    /// enumerates the destinations with their icons.
    static func destinations(for url: URL) -> [NSSharingService] {
        NSSharingService.sharingServices(forItems: [url])
    }
}

/// A destination's name, above it the moment it is hovered — the reel's
/// bubble, without the tooltip's delay.
private struct NamedOnHover: ViewModifier {
    let title: String
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .overlay(alignment: .top) {
                if hovering, !title.isEmpty {
                    Text(title).font(.caption2.weight(.medium)).fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                        .offset(y: -30)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.14), value: hovering)
            .zIndex(hovering ? 1 : 0)
    }
}

struct CapsuleButtonStyle: ButtonStyle {
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
