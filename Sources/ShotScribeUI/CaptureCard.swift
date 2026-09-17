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

    public init(url: URL, from: String, to: String? = nil) {
        self.url = url; self.from = from; self.to = to
    }

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

    @State private var hovered = false
    /// What the cursor is on, said on the card itself rather than left to a
    /// system tooltip. The landing zone already names its tiles this way, and a
    /// tooltip inside a floating panel is not something to rely on.
    @State private var hint: String?
    @State private var binHot = false

    public init(state: CaptureCardState, model: ShotScribeModel,
                open: @escaping () -> Void, dismiss: @escaping () -> Void,
                hovering: @escaping (Bool) -> Void, renew: @escaping () -> Void = {}) {
        self.state = state; self.model = model
        self.open = open; self.dismiss = dismiss
        self.hovering = hovering; self.renew = renew
    }

    private var shot: IndexedShot? { model.shot(atPath: state.url.path) }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                if let shot { model.click(shot) } else { revealDirectly() }
                dismiss()
            } label: {
                AspectThumbnail(path: state.url.path, aspect: 16.0 / 10.0, pixels: 380)
                    .frame(width: 116, height: 73)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hint = $0 ? (shot.map { _ in model.title(of: model.defaultAction) } ?? "Reveal in Finder") : nil }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    // A filled badge, not coloured text: the card floats over
                    // whatever happens to be on screen, and green words on
                    // glass over a bright desktop wash out to nothing.
                    Text(state.to == nil ? "Naming…" : "Named")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(state.to == nil
                                                   ? AnyShapeStyle(Color.secondary)
                                                   : AnyShapeStyle(ShotPalette.chosen)))
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

                Text(state.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(state.to == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)

                Text(hint ?? state.subtitle)
                    .font(.caption2)
                    .foregroundStyle(hint == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(ShotPalette.accent))
                    .lineLimit(1).truncationMode(.middle)

                // The row, under the name it belongs to.
                HStack(spacing: 8) {
                    CardButton("Open ShotScribe", symbol: "text.viewfinder", hint: $hint) { open(); dismiss() }

                    // One AI button, not one per assistant. Which assistant it
                    // reaches is a setting, and the setting is on its own
                    // right-click — the same gesture the landing zone uses to
                    // set what a plain click does.
                    CardButton("Send to \(model.assistantName)",
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
                        Button("Send to \(model.assistantName)") {
                            if let shot { model.sendToAssistant(shot) }
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
                    CardButton("Edit with ShotScribe", art: AppIcons.editor, hint: $hint) {
                        if let shot { model.markUp(shot) } else { model.editFile(state.url) }
                        dismiss()
                    }
                    .contextMenu {
                        Button("Edit with ShotScribe…") {
                            if let shot { model.markUp(shot) } else { model.editFile(state.url) }
                            dismiss()
                        }
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
            .animation(.easeOut(duration: 0.18), value: state.to)
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
            if let p = self.panel, let screen = NSScreen.main, let s = self.state {
                p.setFrame(rect(in: screen.visibleFrame, width: CaptureCard.width(for: s.title)),
                           display: true)
            }
            armTimer()
            return
        }
        state.url = capture.url
        state.to = capture.to
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
        guard !held else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide(animated: true) }
        dismissAt = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.linger, execute: work)
    }

    private func armCeiling() {
        ceiling?.cancel()
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
