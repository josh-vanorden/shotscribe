import SwiftUI
import AppKit
import Combine
import ShotScribeCore

/// What the card is showing: a capture that has landed, and the name once it
/// has one. The card appears the moment the file lands rather than waiting for
/// the title — titling is a model call and takes seconds, and a card that
/// arrives ten seconds after the screenshot has missed the moment.
@MainActor
public final class CaptureCardState: ObservableObject {
    @Published public var url: URL
    @Published public var from: String
    /// nil while the titler is still thinking.
    @Published public var to: String?
    /// The name it got is the generic word, not one read off the picture.
    @Published public var generic = false
    /// The picture, read once when the capture lands and kept. The file's
    /// name changes under the card; its pixels do not, and a tile that
    /// reloaded by path went blank at the very moment the name arrived.
    @Published public var image: NSImage?

    public init(url: URL, from: String, to: String? = nil) {
        self.url = url; self.from = from; self.to = to
    }

    var named: Bool { to != nil }
    var title: String { (to.map { ($0 as NSString).deletingPathExtension }) ?? "Naming…" }
    var subtitle: String { "was \((from as NSString).deletingPathExtension)" }
}

/// **The card that slides up when a capture lands.**
///
/// The rename is the whole product and it happens in silence: unless the window
/// is open at that moment, nothing tells you it worked. This is the one moment
/// ShotScribe has something to say, so it says it — the picture, the name it
/// gave, and the way straight into marking it up.
///
/// It sits **bottom centre** on purpose. macOS puts its own capture thumbnail
/// bottom right, and that one appears before the rename, so it can only ever
/// show an unnamed file. Two cards in one corner would collide and disagree.
///
/// Deliberately one file: this is an experiment (2026-09-15), and an experiment
/// that might not earn its place should be one `rm` away from gone.
public struct CaptureCard: View {
    @ObservedObject var state: CaptureCardState
    @ObservedObject var model: ShotScribeModel
    /// Opening the main window is the host's job — `ShotScribeUI` must not know
    /// what is hosting it.
    let open: () -> Void
    let dismiss: () -> Void
    let hovering: (Bool) -> Void
    /// Start the linger again. Opening a menu takes the mouse off the card
    /// without SwiftUI reporting the exit, so `hovering(false)` never arrives
    /// and the countdown stays paused — the card then sat until the forty
    /// second ceiling (Josh, 2026-09-15: "the shot remained open for a really
    /// long time"). Anything done *from* a menu says so here instead.
    let renew: () -> Void
    /// A drag from the tile has begun, or ended. The card must not leave in
    /// the middle of one, however long the drop takes to find.
    let dragging: (Bool) -> Void

    @State private var hovered = false
    /// What the cursor is on, said on the card itself rather than left to a
    /// system tooltip. The landing zone already names its tiles this way, and a
    /// tooltip inside a floating panel is not something to rely on.
    @State private var hint: String?
    @State private var binHot = false

    public init(state: CaptureCardState, model: ShotScribeModel,
                open: @escaping () -> Void, dismiss: @escaping () -> Void,
                hovering: @escaping (Bool) -> Void, renew: @escaping () -> Void = {},
                dragging: @escaping (Bool) -> Void = { _ in }) {
        self.state = state; self.model = model
        self.open = open; self.dismiss = dismiss
        self.hovering = hovering; self.renew = renew; self.dragging = dragging
    }

    private var shot: IndexedShot? { model.shot(atPath: state.url.path) }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The picture is the state's own, loaded once; the tile never
            // reloads by path, so it is there before the name and stays
            // after it. On top, the drag source: a real `NSView`, because a
            // drop into Finder or Slack wants the file on disk, not pixels.
            ZStack {
                if let image = state.image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay(Image(systemName: "photo")
                            .foregroundStyle(.secondary).font(.system(size: 18)))
                }
                DragTile(image: state.image, url: state.url,
                         click: {
                             if let shot { model.click(shot) } else { revealDirectly() }
                             dismiss()
                         },
                         hover: { inside in
                             hint = inside ? tileHint : nil
                             // The tile is a platform view; make sure the card
                             // knows it is being looked at while the cursor is
                             // on it, whatever the root's own hover reports.
                             if inside { hovered = true; hovering(true) }
                         },
                         dragging: dragging)
            }
            .frame(width: 116, height: 73)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    // A filled badge, not coloured text: the card floats over
                    // whatever happens to be on screen, and green words on
                    // glass over a bright desktop wash out to nothing.
                    HStack(spacing: 4) {
                        Text(badge).font(.system(size: 10, weight: .bold))
                        if !state.named { PulsingDots() }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(state.named && !state.generic
                                               ? AnyShapeStyle(ShotPalette.chosen)
                                               : AnyShapeStyle(Color.secondary)))
                    // Clicking a chip takes the tag off. Filing from here has
                    // to be as easy to undo as it was to do.
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            if let shot { model.untag(shot, tag) }
                            renew()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "tag.fill").font(.system(size: 7))
                                Text(tag).font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(ShotPalette.accent)
                            .background(Capsule().fill(ShotPalette.accent.opacity(0.14)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .onHover { hint = $0 ? "Take \(tag) off" : nil }
                    }
                    // An empty chip, so filing a shot is something the card can
                    // do rather than something you have to open the window for.
                    if let shot, model.taggingEnabled {
                        Menu {
                            Button("+  New Tag…") { model.askForFileTab(); open(); dismiss() }
                            Divider()
                            ForEach(model.vocabulary, id: \.self) { tag in
                                Button(model.isTagged(shot, tag) ? "\(tag)  ✓" : tag) {
                                    model.toggleTag(shot, tag)
                                    renew()
                                }
                            }
                        } label: {
                            // A chip with the dashed edge of an empty field and
                            // the word on it, so it reads as "one more tag
                            // goes here" beside the filled ones rather than as
                            // a stray glyph.
                            HStack(spacing: 3) {
                                Image(systemName: "plus").font(.system(size: 8, weight: .bold))
                                Text("Tag").font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(Capsule().strokeBorder(Color.secondary.opacity(0.55),
                                                               style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                            .contentShape(Capsule())
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .onHover { hint = $0 ? "Tag this shot" : nil }
                    }
                }

                // Green for a name the shot earned, grey for the generic word:
                // the colour says at a glance whether there is anything to
                // read here, before the word does.
                if state.named {
                    Text(state.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(state.generic ? AnyShapeStyle(.secondary)
                                                       : AnyShapeStyle(ShotPalette.named))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .transition(.opacity)
                } else {
                    Shimmer()
                        .frame(width: 150, height: 15)
                        .transition(.opacity)
                }

                Text(hint ?? state.subtitle)
                    .font(.caption2)
                    .foregroundStyle(hint == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(ShotPalette.accent))
                    .lineLimit(1).truncationMode(.middle)

                // The row, under the name it belongs to.
                HStack(spacing: 8) {
                    CardButton("Go to Library", symbol: "text.viewfinder", hint: $hint) { open(); dismiss() }

                    // One AI button, not one per assistant. Which assistant it
                    // reaches is a setting, and the setting is on its own
                    // right-click — the same gesture the landing zone uses to
                    // set what a plain click does.
                    CardButton(model.title(of: .sendToAssistant),
                               art: AppIcons.icon(for: model.aiProvider.kind),
                               fallback: "paperplane.fill", hint: $hint) {
                        if let shot { model.sendToAssistant(shot) }
                        dismiss()
                    }
                    // Both ways of handing a shot to an assistant live here.
                    // They are not the same job — one says "look at this", the
                    // other says "rebuild this layout as code" — but they are
                    // the same *destination*, so one mark carries both rather
                    // than two marks competing for the same corner.
                    .contextMenu {
                        Button(model.title(of: .sendToAssistant)) {
                            if let shot { model.sendToAssistant(shot) }
                            dismiss()
                        }
                        Button(model.title(of: .sendPicture)) {
                            if let shot { model.sendPicture(shot) }
                            dismiss()
                        }
                        Button("Rebuild as code") {
                            if let shot { model.copyCodeBrief(for: shot) }
                            dismiss()
                        }
                        Divider()
                        Menu("Assistant") {
                            ForEach(AIProvider.Kind.allCases.filter { $0 != .offline }, id: \.self) { kind in
                                Button(model.aiProvider.kind == kind ? "\(kind.name)  ✓" : kind.name) {
                                    model.setAIProvider(AIProvider(kind: kind))
                                    renew()
                                }
                            }
                        }
                    }

                    CardButton("Reveal in Finder", art: AppIcons.finder, hint: $hint) {
                        if let shot { model.reveal(shot) } else { revealDirectly() }
                        dismiss()
                    }
                    // Edit with ShotScribe, in its own editor, with Preview one
                    // right-click away for what the editor does not do.
                    let edit = { if let shot { model.markUp(shot) } else { model.editFile(state.url) }; dismiss() }
                    CardButton("Edit with ShotScribe", art: AppIcons.editor, hint: $hint, action: edit)
                    .contextMenu {
                        Button("Edit with ShotScribe…", action: edit)
                        Button("Open in Preview") { model.openInPreview(state.url); dismiss() }
                    }

                    Spacer(minLength: 10)

                    if let shot {
                        Button {
                            model.trash(shot)
                            dismiss()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(binHot ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(binHot ? AnyShapeStyle(Color.red)
                                                                 : AnyShapeStyle(Color.primary.opacity(0.06))))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            binHot = inside
                            hint = inside ? (model.deletesForGood ? "Delete for good" : "Move to Trash") : nil
                        }
                        .animation(.easeOut(duration: 0.14), value: binHot)
                        .help(model.deletesForGood ? "Delete for good" : "Move to Trash")
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.3), value: state.to)
        }
        .padding(.leading, 12).padding(.trailing, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
        .overlay(alignment: .topTrailing) {
            if hovered {
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.secondary)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(5)
                .transition(.opacity)
            }
        }
        .tint(ShotPalette.accent)
        .onHover { inside in
            hovered = inside
            if !inside { hint = nil }
            hovering(inside)
        }
        .animation(.easeOut(duration: 0.14), value: hovered)
    }

    private var tags: [String] { Array((shot?.tags ?? []).prefix(3)) }

    private var badge: String {
        guard state.named else { return "Naming" }
        return state.generic ? "Nothing to read" : "Named"
    }

    /// What the tile does, said on the card: a click, or a drag.
    private var tileHint: String {
        let click = shot.map { _ in model.title(of: model.defaultAction) } ?? "Reveal in Finder"
        return "\(click) · or drag it into any app"
    }

    /// Tall enough for a badge line, the name, what it was, and the row of
    /// actions underneath it.
    public static let height: CGFloat = 132

    /// Wide enough for the longer of the name and the button row.
    public static func width(for title: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize,
                                     weight: .semibold)
        let measured = (title as NSString).size(withAttributes: [.font: font]).width
        let buttons: CGFloat = 32 * 4 + 8 * 3 + 10 + 30      // four marks, gaps, then the bin
        let content = max(measured.rounded(.up), buttons)
        let chrome: CGFloat = 12 + 116 + 12 + 14 + 4
        let ceiling = min(760, (NSScreen.main?.visibleFrame.width ?? 900) - 80)
        return min(max(430, content + chrome), ceiling)
    }

    // The index sweep can trail the new path by a beat. These keep the common
    // actions working in that window rather than offering a button that does
    // nothing.
    private func revealDirectly() {
        NSWorkspace.shared.activateFileViewerSelecting([state.url])
    }

}

/// Three dots that breathe in turn: the badge's sign that something is
/// happening, on a card that used to say "Naming…" and then sit still.
private struct PulsingDots: View {
    @State private var lit = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle().frame(width: 3, height: 3)
                    .opacity(lit ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.15), value: lit)
            }
        }
        .onAppear { lit = true }
    }
}

/// A band of light crossing the place the name will take.
private struct Shimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.09))
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.primary.opacity(0.22), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.55)
                        .offset(x: phase * geo.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { phase = 1.2 }
            }
    }
}

/// The tile as a drag source, and as the click it always was.
///
/// A real `NSView` with a real `NSDraggingSource`, not `onDrag`: the drop has
/// to receive the **file on disk** under the name it was just given — Finder
/// copies it, a browser's upload field takes it, Slack and Jira attach it —
/// and the card has to know when the drag ends so it does not leave in the
/// middle of one.
///
/// Draggable from the moment the card appears. Naming takes seconds, and a
/// drag that has to wait for it is a drag that fires the click instead (Josh,
/// 2026-09-23: "clicking the tile opens preview… it does not allow me to drag").
/// So the file URL is not written when the tile is picked up; it is
/// **provided when the drop reads it**, from `url` as it is at that moment.
/// A drag that outlasts the naming delivers the renamed file.
struct DragTile: NSViewRepresentable {
    var image: NSImage?
    var url: URL?
    var click: () -> Void
    var hover: (Bool) -> Void
    var dragging: (Bool) -> Void

    func makeNSView(context: Context) -> DragTileView { DragTileView() }

    func updateNSView(_ view: DragTileView, context: Context) {
        view.image = image
        view.url = url
        view.click = click
        view.hover = hover
        view.dragging = dragging
    }
}

final class DragTileView: NSView, NSDraggingSource, NSPasteboardItemDataProvider {
    var image: NSImage?
    /// The file as it is right now: the raw capture until the name lands, the
    /// renamed file after. Read at drop time, not at pick-up.
    var url: URL?
    var click: () -> Void = {}
    var hover: (Bool) -> Void = { _ in }
    var dragging: (Bool) -> Void = { _ in }
    private var pressedAt: NSPoint?
    private var tracking: NSTrackingArea?

    /// Past this, a press has become a drag. Under it, it is a click that has
    /// not finished yet.
    static func isDrag(from a: NSPoint, to b: NSPoint) -> Bool { hypot(a.x - b.x, a.y - b.y) >= 4 }

    /// What goes on the pasteboard: a file URL — what every receiver that
    /// takes files reads, and what the pasteboard also offers to older
    /// receivers as a filename list — promised now, written when read, so the
    /// name it carries is the name the file has when the drop happens.
    func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setDataProvider(self, forTypes: [.fileURL])
        return item
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .fileURL, let url else { return }
        item.setString(url.absoluteString, forType: .fileURL)
    }

    // The card floats in a non-activating panel; the first click must count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseEntered(with event: NSEvent) { hover(true) }
    override func mouseExited(with event: NSEvent) { hover(false) }

    override func mouseDown(with event: NSEvent) {
        pressedAt = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressedAt, url != nil else { return }
        let now = convert(event.locationInWindow, from: nil)
        guard Self.isDrag(from: start, to: now) else { return }
        pressedAt = nil
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem())
        item.setDraggingFrame(bounds, contents: dragImage())
        dragging(true)
        Log.write("card: drag began (\(url?.lastPathComponent ?? "?"))")
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressedAt != nil else { return }
        pressedAt = nil
        click()
    }

    /// The tile as it looks — the picture filling its rounded frame — so what
    /// travels under the cursor is the thing that was picked up.
    private func dragImage() -> NSImage {
        let picture = image
        return NSImage(size: bounds.size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).addClip()
            guard let picture, picture.size.width > 0, picture.size.height > 0 else {
                NSColor.quaternaryLabelColor.setFill(); rect.fill(); return true
            }
            let scale = max(rect.width / picture.size.width, rect.height / picture.size.height)
            let w = picture.size.width * scale, h = picture.size.height * scale
            picture.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
            return true
        }
    }

    // MARK: NSDraggingSource

    /// Copy, and only copy. `.generic` would let Finder *move* the file out
    /// of the Screenshots folder on a drop to the same volume.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        Log.write("card: drag ended, \(operation == [] ? "nowhere" : "delivered \(url?.lastPathComponent ?? "?")")")
        dragging(false)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

private struct CardButton: View {
    let name: String
    /// A real app icon, when the button reaches an app that has one.
    let art: Image?
    /// Otherwise ShotScribe's own accent with a white glyph on it.
    let symbol: String?
    @Binding var hint: String?
    let action: () -> Void

    init(_ name: String, art: Image, hint: Binding<String?>, action: @escaping () -> Void) {
        self.name = name; self.art = art; self.symbol = nil
        self._hint = hint; self.action = action
    }

    /// A mark when the assistant has one, ShotScribe's own treatment when not.
    init(_ name: String, art: Image?, fallback: String,
         hint: Binding<String?>, action: @escaping () -> Void) {
        self.name = name; self.art = art; self.symbol = art == nil ? fallback : nil
        self._hint = hint; self.action = action
    }

    init(_ name: String, symbol: String, hint: Binding<String?>, action: @escaping () -> Void) {
        self.name = name; self.art = nil; self.symbol = symbol
        self._hint = hint; self.action = action
    }

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if let art {
                    art.resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                } else if let symbol {
                    // A macOS app icon is a glossy squircle with depth. A flat
                    // disc beside two of them reads as the lesser thing, so
                    // this is built the same way: the shape, a lit gradient, a
                    // highlight along the top edge, and its own shadow.
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                        .frame(width: 22, height: 22)
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [ShotPalette.accent.opacity(0.92),
                                             ShotPalette.accent,
                                             ShotPalette.accent.opacity(0.78)],
                                    startPoint: .top, endPoint: .bottom))
                                .overlay(alignment: .top) {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(colors: [.white.opacity(0.55), .clear],
                                                           startPoint: .top, endPoint: .bottom),
                                            lineWidth: 1)
                                }
                                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
                        }
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            Circle().fill(Color.primary.opacity(hovered ? 0.14 : 0.06))
        }
        // A real icon carries its own colour, so hover lifts rather than tints.
        .scaleEffect(hovered ? 1.12 : 1)
        .shadow(color: .black.opacity(hovered ? 0.28 : 0), radius: 5, y: 2)
        .animation(.spring(response: 0.26, dampingFraction: 0.6), value: hovered)
        .onHover { inside in
            hovered = inside
            hint = inside ? name : nil
        }
        .help(name)
    }
}

/// macOS's own capture thumbnail — the one that appears bottom right and sits
/// there for a few seconds.
///
/// It is a setting in Apple's own preferences domain, not ShotScribe's, so this
/// reaches across with `CFPreferences`. Reading another app's domain is
/// ordinary; writing one is only possible because ShotScribe is a Developer ID
/// app rather than a sandboxed one, and it is done **only** when the operator
/// flips the switch — never at launch, never as a side effect of anything else.
///
/// Why offer it at all: ShotScribe's own card says strictly more (it has the
/// name), and two cards in two corners after every capture is one too many.
public enum SystemThumbnail {
    private static let domain = "com.apple.screencapture" as CFString
    private static let key = "show-thumbnail" as CFString

    /// macOS shows it unless told otherwise, so "nothing stored" means on.
    public static var isOn: Bool {
        guard let value = CFPreferencesCopyAppValue(key, domain) as? Bool else { return true }
        return value
    }

    public static func set(_ on: Bool) {
        CFPreferencesSetAppValue(key, on as CFBoolean, domain)
        CFPreferencesAppSynchronize(domain)
    }
}

/// A hosting view that answers the **first** click.
///
/// The card lives in a non-activating panel, so ShotScribe is not the front app
/// when the cursor arrives. By default AppKit spends that first click on
/// bringing the window forward and the button underneath never sees it — which
/// is exactly what a button that "does nothing" looks like (Josh, 2026-09-15,
/// on the middle of the three).
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the floating panel the card lives in, and the rules about when it comes
/// and goes. **The app starts this, never the library** — mounting
/// `ShotScribeView` inside some other host must not put a panel on that host's
/// screen.
@MainActor
public final class CaptureCardPresenter {
    private let model: ShotScribeModel
    private let open: () -> Void
    private var panel: NSPanel?
    private var state: CaptureCardState?
    private var dismissAt: DispatchWorkItem?
    private var ceiling: DispatchWorkItem?
    private var landed: AnyCancellable?
    private var named: AnyCancellable?
    private var held = false
    /// A drag from the tile is under way: no timer, no ceiling, until it ends.
    private var dragging = false

    /// Long enough to read a name and reach for it, short enough not to sit in
    /// the way. The timer stops while the cursor is on the card, and it starts
    /// again from the moment the **name** arrives, so naming never eats the
    /// time you had to read it.
    private static let linger: TimeInterval = 8

    /// A hard stop, whatever the cursor is doing. Pausing on hover reads as
    /// "you are looking at it, take your time", but it cannot tell that apart
    /// from a cursor that happens to be resting where the card appears — and
    /// then the card never leaves.
    private static let ceilingAfter: TimeInterval = 40

    public init(model: ShotScribeModel, open: @escaping () -> Void) {
        self.model = model
        self.open = open
    }

    public func start() {
        landed = model.$justLanded
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] url in
                guard let self, self.model.showsCaptureCard else { return }
                self.show(url: url)
            }
        named = model.$justNamed
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] capture in
                guard let self, self.model.showsCaptureCard else { return }
                self.name(capture)
            }
    }

    /// The capture has landed. Show it at once, still unnamed.
    private func show(url: URL) {
        hide(animated: false)
        guard let screen = NSScreen.main else { return }
        let state = CaptureCardState(url: url, from: url.lastPathComponent)
        self.state = state
        // The picture, once. The name will change the path under this card;
        // the pixels it shows must not follow the path and go blank.
        Task { @MainActor [weak self] in
            let image = await ThumbnailCache.shared.load(url.path, size: CGSize(width: 380, height: 238), scale: 2)
            if let self, self.state === state { state.image = image }
        }

        let size = CGSize(width: CaptureCard.width(for: state.title), height: CaptureCard.height)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        // Hover states and tooltips need mouse-moved events; without this the
        // card never lights up under the cursor.
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = CaptureCard(state: state, model: model, open: { [weak self] in
            self?.open()
        }, dismiss: { [weak self] in
            self?.hide(animated: true)
        }, hovering: { [weak self] inside in
            self?.held = inside
            inside ? self?.cancelTimer() : self?.armTimer()
        }, renew: { [weak self] in
            self?.held = false
            self?.armTimer()
        }, dragging: { [weak self] inDrag in
            guard let self else { return }
            self.dragging = inDrag
            if inDrag {
                self.cancelTimer()
                self.ceiling?.cancel()
                self.ceiling = nil
            } else {
                self.held = false
                self.armTimer()
                self.armCeiling()
            }
        })
        panel.contentView = FirstClickHostingView(rootView: view)

        let frame = screen.visibleFrame
        panel.setFrame(rect(in: frame, width: size.width, dy: -34), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().setFrame(rect(in: frame, width: size.width), display: true)
            panel.animator().alphaValue = 1
        }
        armTimer()
        armCeiling()
    }

    /// The name arrived. Fill it in and widen to fit, and give the reader the
    /// full linger from here.
    private func name(_ capture: NamedCapture) {
        guard let panel, let state, state.url.path == capture.url.path || state.from == capture.from else {
            // A name with no card behind it — the operator turned the card on
            // mid-rename, say. Show the finished thing, with the *raw* name in
            // the "was" line rather than the one it was just given.
            show(url: capture.url)
            self.state?.from = capture.from
            self.state?.to = capture.to
            self.state?.generic = capture.generic
            if let p = self.panel, let screen = NSScreen.main, let s = self.state {
                p.setFrame(rect(in: screen.visibleFrame, width: CaptureCard.width(for: s.title)),
                           display: true)
            }
            armTimer()
            return
        }
        state.url = capture.url
        state.to = capture.to
        state.generic = capture.generic
        guard let screen = NSScreen.main else { return }
        let width = CaptureCard.width(for: state.title)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().setFrame(rect(in: screen.visibleFrame, width: width), display: true)
        }
        armTimer()
        armCeiling()
    }

    private func rect(in frame: NSRect, width: CGFloat, dy: CGFloat = 0) -> NSRect {
        NSRect(x: frame.midX - width / 2, y: frame.minY + 26 + dy,
               width: width, height: CaptureCard.height)
    }

    private func armTimer() {
        cancelTimer()
        // Nothing to read yet: a card still saying "Naming…" must not time out
        // before it has said anything. The ceiling still covers a titler that
        // never answers. (2026-09-15: a ten-second title beat the eight-second
        // linger, the card left, and the name arrived to an empty screen —
        // which then put up a second card with the new name in both lines.)
        guard state?.to != nil else { return }
        guard !held, !dragging else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide(animated: true) }
        dismissAt = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.linger, execute: work)
    }

    private func armCeiling() {
        ceiling?.cancel()
        // Not during a drag. The name landing mid-drag re-arms the timers,
        // and a ceiling started then took the card out from under the cursor
        // forty seconds on (a Codex read-only review, 2026-09-23). The drag's
        // end arms it again; `dragging` is cleared there before this runs.
        guard !dragging else { return }
        let cap = DispatchWorkItem { [weak self] in self?.hide(animated: true) }
        ceiling = cap
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.ceilingAfter, execute: cap)
    }

    private func cancelTimer() {
        dismissAt?.cancel()
        dismissAt = nil
    }

    private func hide(animated: Bool) {
        cancelTimer()
        ceiling?.cancel()
        ceiling = nil
        held = false
        dragging = false
        state = nil
        guard let panel else { return }
        self.panel = nil
        guard animated else { return panel.orderOut(nil) }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}
