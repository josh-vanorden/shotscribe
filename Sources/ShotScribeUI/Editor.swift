import SwiftUI
import AppKit
import Combine
import ShotScribeCore

// MARK: - Tools

/// What a drag on the picture does — and **only** that.
///
/// A drawing tool draws, including on top of marks already there. **Select**
/// is the one tool that picks marks up and moves them. The single exception is
/// a handle: they are only ever shown on the selected mark, and what can be
/// seen can be grabbed.
///
/// The first cut let every drawing tool pick up a mark it was pressed on. A
/// pixelation is a large rectangle, so it swallowed every press inside it and
/// nothing could be started over it (Josh, 2026-09-16: "the implied fights the
/// end user").
enum EditorTool: String, CaseIterable, Identifiable {
    case select, pixelate, blackOut, rectangle, ellipse, line, arrow, highlight, text, step, crop
    var id: String { rawValue }

    var kind: Mark.Kind? { self == .crop ? nil : Mark.Kind(rawValue: rawValue) }

    var name: String {
        switch self {
        case .select:    return "Select"
        case .pixelate:  return "Pixelate"
        case .blackOut:  return "Black out"
        case .rectangle: return "Rectangle"
        case .ellipse:   return "Ellipse"
        case .line:      return "Line"
        case .arrow:     return "Arrow"
        case .highlight: return "Highlight"
        case .text:      return "Text"
        case .step:      return "Step"
        case .crop:      return "Crop"
        }
    }

    var symbol: String {
        switch self {
        case .select:    return "cursorarrow"
        case .pixelate:  return "square.grid.3x3.square"
        case .blackOut:  return "rectangle.fill"
        case .rectangle: return "rectangle"
        case .ellipse:   return "circle"
        case .line:      return "line.diagonal"
        case .arrow:     return "arrow.up.right"
        case .highlight: return "highlighter"
        case .text:      return "textformat"
        case .step:      return "1.circle.fill"
        case .crop:      return "crop"
        }
    }

    /// One key each, the ones people already know from other editors.
    var key: Character {
        switch self {
        case .select:    return "v"
        case .pixelate:  return "p"
        case .blackOut:  return "b"
        case .rectangle: return "r"
        case .ellipse:   return "o"
        case .line:      return "l"
        case .arrow:     return "a"
        case .highlight: return "h"
        case .text:      return "t"
        case .step:      return "n"
        case .crop:      return "c"
        }
    }

    var hint: String {
        switch self {
        case .select:    return "Click a mark to select it. Drag to move, handles resize, arrow keys nudge, Delete removes."
        case .pixelate:  return "Drag over anything to hide it. Text under it can't be read back."
        case .blackOut:  return "Drag to cover a region completely."
        case .rectangle: return "Drag to draw a box."
        case .ellipse:   return "Drag to circle something."
        case .line:      return "Drag to draw a line. Its middle handle bends it."
        case .arrow:     return "Drag from where the arrow starts to what it points at. Its middle handle bends it."
        case .highlight: return "Drag across text to highlight it."
        case .text:      return "Click where the label goes and type. Double-click a label to change it."
        case .step:      return "Click to drop the next number. Each click counts up; Renumber closes any gaps."
        case .crop:      return "Drag the corners to what you want to keep, then Apply. The rest stays in the edit and can come back."
        }
    }
}

enum Weight: String, CaseIterable, Identifiable {
    case thin, medium, thick
    var id: String { rawValue }
    var factor: CGFloat { self == .thin ? 0.6 : self == .medium ? 1 : 1.8 }
    var name: String { rawValue.capitalized }
}

/// What the watermark panel is editing.
enum WatermarkKind: Hashable {
    case text, logo, stamp
    static func of(_ w: Watermark?) -> WatermarkKind { w?.stamp != nil ? .stamp : w?.imageName != nil ? .logo : .text }
}

private enum CropDrag {
    case none
    case move(grab: CGPoint, original: CGRect)
    case resize(Mark.Handle, original: CGRect)
    case draw(from: CGPoint)
}

private enum Drag {
    case create(UUID, before: [Mark])
    case move(UUID, grab: CGPoint, original: Mark, before: [Mark])
    case resize(UUID, Mark.Handle, original: Mark, before: [Mark])
    case none
}

// MARK: - The editor

/// **The editor.** Marks are live objects until Save: select one to move it,
/// resize it, recolour it, restyle it, retype it or delete it.
///
/// What is drawn on screen is `ImageEditor.draw` — the same routine that writes
/// the file — so the saved picture is the picture that was shown. Pixelation is
/// the one exception on screen: it needs the image's own pixels, so it is baked
/// into a base picture off the main thread and redrawn when a pixelation moves.
public struct EditorView: View {
    let url: URL
    @ObservedObject var model: ShotScribeModel
    let close: () -> Void

    @State private var source: CGImage?
    @State private var base: CGImage?
    @State private var baseGeneration = 0
    @State private var marks: [Mark]
    @State private var selected: UUID?
    @State private var tool: EditorTool
    /// Black for every mark by default; the highlighter keeps its own colour,
    /// because a black wash is a dim, not a highlight.
    @State private var color: MarkColor = .black
    @State private var highlightColor: MarkColor = .vividYellow
    @State private var weight: Weight = .medium
    /// Text and step size as a multiple of the picture's base size. A slider,
    /// not five buttons: 2026-09-16 the steps were still the wrong size at every stop.
    @State private var sizeFactor: CGFloat = 1
    @State private var sizeDragBefore: [Mark]?
    @State private var filled = false
    @State private var undoStack: [[Mark]] = []
    @State private var redoStack: [[Mark]] = []
    @State private var drag: Drag = .none
    @State private var editingText: UUID?
    @State private var textDraft = ""
    @State private var saving = false
    @State private var failed = false
    @FocusState private var textFocused: Bool
    @State private var frame: FrameStyle = .plain
    @State private var framing = false
    /// Opened from a kept edit rather than from the file itself.
    @State private var reopened = false
    /// Whether `source` is still the untouched capture — what makes Revert honest.
    @State private var sourceIsOriginal = true
    @State private var confirmRevert = false
    /// The mark under the pointer in Select, lit before it is clicked — so a
    /// person can see what a click will pick up.
    @State private var hoveredMark: UUID?
    @State private var pickingFirst = false
    @State private var pickingSecond = false
    @State private var badge: Mark.Badge = .bubble
    /// What is kept of the base, in base pixels. nil is all of it.
    @State private var crop: CGRect?
    /// The crop being adjusted in the Crop tool, before Apply.
    @State private var cropDraft: CGRect?
    @State private var cropDrag: CropDrag = .none
    /// The output size as a fraction of the cropped base.
    @State private var scale: CGFloat = 1
    @State private var resizing = false
    @State private var widthDraft = ""
    /// Pictures brought in as frame backgrounds, newest first.
    @State private var backgroundNames: [String] = BackgroundImages.names()
    /// The one drawn now, so the canvas does not decode it per frame.
    @State private var backgroundImage: (name: String, image: CGImage)?
    @State private var customCombos: [FrameStyle.Combo] = FrameStyle.customCombos()
    @State private var addingCombo = false
    @State private var comboName = ""
    @State private var comboA: MarkColor = .sapphire
    @State private var comboB: MarkColor = .frost
    @State private var hexA = MarkColor.sapphire.hex
    @State private var hexB = MarkColor.frost.hex
    /// The mark of ownership over the picture, and its panel.
    @State private var watermark: Watermark?
    @State private var branding = false
    @State private var wmKind: WatermarkKind = .text
    /// When the picture was taken — the file's creation date — for the stamp.
    @State private var capturedAt: Date?
    @State private var logoNames: [String] = WatermarkImages.names()
    @State private var logo: (name: String, image: CGImage)?
    @State private var everyEdit = Watermark.onEveryEdit
    @State private var pickingWatermarkColour = false
    /// Every family installed, read once the first font menu opens.
    @State private var families: [String] = []
    /// The face the next label or step is set in.
    @State private var font: TextFont = .system

    /// Public, with a way to start from marks already made, so the editor can
    /// be rendered off-screen and looked at before an operator sees it.
    public init(url: URL, model: ShotScribeModel, initialMarks: [Mark] = [],
                initialTool: String? = nil, initialSelection: UUID? = nil,
                showingFrame: Bool = false, initialWatermark: Watermark? = nil, showingWatermark: Bool = false,
                close: @escaping () -> Void) {
        self.url = url; self.model = model; self.close = close
        _framing = State(initialValue: showingFrame)
        _watermark = State(initialValue: initialWatermark)
        _branding = State(initialValue: showingWatermark)
        _wmKind = State(initialValue: WatermarkKind.of(initialWatermark))
        _marks = State(initialValue: initialMarks)
        _tool = State(initialValue: initialTool.flatMap(EditorTool.init(rawValue:)) ?? .pixelate)
        _selected = State(initialValue: initialSelection)
    }

    private var selection: Mark? { selected.flatMap { id in marks.first { $0.id == id } } }
    /// A mark, a frame, a crop, a resize, a watermark — or an edit reopened,
    /// which may be having things taken away. A watermark on its own is an
    /// edit (2026-09-16: Save sat grey after "Use on every edit").
    private var hasSomethingToSave: Bool {
        !marks.isEmpty || !frame.isPlain || crop != nil || abs(scale - 1) >= 0.001
            || !(watermark?.isEmpty ?? true) || reopened
    }
    private var redacted: Bool { marks.contains { $0.kind.redacts } }
    private var pixelSignature: [CGRect] { marks.filter { $0.kind == .pixelate }.map(\.rect) }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
                .background(.bar)
            Divider()
            inspector
            Divider()
            canvas
            Divider()
            footer
                .background(.bar)
        }
        .animation(.easeOut(duration: 0.18), value: framing)
        .animation(.easeOut(duration: 0.18), value: branding)
        .animation(.easeOut(duration: 0.18), value: selected)
        .frame(minWidth: 880, minHeight: 520)
        .background(Color(nsColor: .underPageBackgroundColor))
        .tint(ShotPalette.accent)
        .background(shortcuts)
        .task { load() }
        .onChange(of: pixelSignature) { _ in rebake() }
        // On the root, not the panel: a panel's modifier is gone with the
        // panel, and the logo has to load whichever panel picked it (2026-09-16:
        // "no watermark preview so any adjustments are made blindly").
        .onChange(of: watermark?.imageName) { _ in loadLogo() }
        .onChange(of: textFocused) { focused in if !focused { commitText() } }
        .onExitCommand {
            if editingText != nil { commitText() }
            else if tool == .crop { leaveCrop() }
            else if framing || resizing || branding { framing = false; resizing = false; branding = false }
            else { selected = nil }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 2) {
            toolButton(.select)
            separator
            toolButton(.pixelate)
            toolButton(.blackOut)
            separator
            ForEach([EditorTool.rectangle, .ellipse, .line, .arrow, .highlight]) { toolButton($0) }
            separator
            toolButton(.text)
            toolButton(.step)
            separator
            toolButton(.crop)
            modeButton("Frame", symbol: "photo.artframe", on: framing, tinted: !frame.isPlain,
                       help: "Corners, margin, background and shadow around the whole picture") {
                if editingText != nil { commitText() }
                framing.toggle(); resizing = false; branding = false
                if framing { leaveCrop(); if frame.isPlain { frame = .suggested } }
            }
            modeButton("Watermark", symbol: "seal", on: branding, tinted: !(watermark?.isEmpty ?? true),
                       help: "Your name or logo over the picture — in a corner, the middle, or tiled across it") {
                if editingText != nil { commitText() }
                branding.toggle(); framing = false; resizing = false
                if branding {
                    leaveCrop()
                    if watermark == nil { watermark = Watermark.stored() ?? .suggested; wmKind = .of(watermark) }
                }
            }
            modeButton("Resize", symbol: "arrow.down.left.and.arrow.up.right", on: resizing, tinted: abs(scale - 1) > 0.001,
                       help: "The size the picture is saved at") {
                if editingText != nil { commitText() }
                resizing.toggle(); framing = false; branding = false
                if resizing { leaveCrop(); widthDraft = "\(outputSize.width)" }
            }
            separator
            Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless)
                .disabled(undoStack.isEmpty || saving)
                .help("Undo (⌘Z)")
            Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(.borderless)
                .disabled(redoStack.isEmpty || saving)
                .help("Redo (⇧⌘Z)")
            Spacer(minLength: 8)
            Button { model.openInPreview(url) } label: {
                VStack(spacing: 3) {
                    AppIcons.preview.resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18)
                    Text("Preview").font(.system(size: 9.5)).lineLimit(1).fixedSize()
                }
                .frame(width: 52, height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in Preview, for anything the editor doesn't do. Unsaved marks here are not carried over.")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var separator: some View {
        Divider().frame(height: 18).padding(.horizontal, 3)
    }

    /// A mode — Frame, Resize — drawn like a tool, since it lives with them.
    private func modeButton(_ name: String, symbol: String, on: Bool, tinted: Bool, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                Text(name).font(.system(size: 9.5, weight: on ? .semibold : .regular)).lineLimit(1).fixedSize()
            }
            .frame(width: 52, height: 42)
            .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(on ? AnyShapeStyle(ShotPalette.accent)
                         : tinted ? AnyShapeStyle(ShotPalette.accent.opacity(0.15)) : AnyShapeStyle(Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func toolButton(_ t: EditorTool) -> some View {
        Button {
            if editingText != nil { commitText() }
            framing = false; resizing = false; branding = false
            if t == .crop { cropDraft = crop ?? fullRect } else if tool == .crop { cropDraft = nil }
            tool = t
            if t != .select { selected = nil }
        } label: {
            // The name under the icon, always. Nine glyphs with nothing under
            // them left people guessing what each one was for.
            VStack(spacing: 3) {
                Image(systemName: t.symbol).font(.system(size: 14, weight: .medium))
                Text(t.name).font(.system(size: 9.5, weight: tool == t ? .semibold : .regular))
                    .lineLimit(1).fixedSize()
            }
            .frame(width: 52, height: 42)
            .foregroundStyle(tool == t ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tool == t ? AnyShapeStyle(ShotPalette.accent) : AnyShapeStyle(Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(t.name) — \(t.hint)  (\(String(t.key).uppercased()))")
    }

    // MARK: Inspector

    /// What the next mark will look like — or, with a mark selected, what that
    /// mark looks like, and changing it changes the mark.
    private var styleKind: Mark.Kind? { selection?.kind ?? tool.kind }

    /// What the next mark will be, or what the selected one is, or the frame —
    /// a card that changes with what you are doing.
    @ViewBuilder
    private var inspector: some View {
        Group {
            if framing { frameControls }
            else if branding { watermarkControls }
            else if resizing { resizeControls }
            else if tool == .crop { cropControls }
            else { markControls }
        }
        .background(.regularMaterial)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// The style row. Steps carry colour, size and shape, which at the
    /// narrowest window is wider than one line — so the shape group drops to a
    /// second line before anything gets clipped. `ViewThatFits` picks.
    private var markControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                target
                styleGroups(shape: true)
                Spacer(minLength: 8)
                selectionButtons
            }
            .frame(height: 40)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    target
                    styleGroups(shape: false)
                    Spacer(minLength: 8)
                    selectionButtons
                }
                .frame(height: 40)
                if styleKind == .step {
                    HStack(spacing: 10) {
                        shapeGroup
                        Spacer(minLength: 8)
                    }
                    .frame(height: 32)
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder private func styleGroups(shape: Bool) -> some View {
        if styleKind == .pixelate {
            Label("Pixelate hides what's underneath — no colour to choose.", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
        } else if styleKind != nil {
            caption("Colour")
            swatches
            if styleKind?.takesLineWidth ?? false { separator; caption("Width"); weightPicker }
            if styleKind?.takesFill ?? false {
                separator
                Toggle("Fill", isOn: Binding(get: { selection?.filled ?? filled },
                                             set: { on in filled = on; apply { $0.filled = on } }))
                    .toggleStyle(.checkbox)
            }
            if styleKind?.takesFontSize ?? false { separator; sizeSlider; fontMenu(markFont) }
            if shape, styleKind == .step { separator; shapeGroup }
        }
    }

    @ViewBuilder private var shapeGroup: some View {
        caption("Shape")
        badgePicker
        if marks.contains(where: { $0.kind == .step }) {
            Button("Renumber") { renumber() }
                .buttonStyle(CapsuleButtonStyle(quiet: true))
                .lineLimit(1).fixedSize()
                .help("Close the gaps: 1, 2, 3… in the order they were placed")
        }
    }

    @ViewBuilder private var selectionButtons: some View {
        if let sel = selection {
            if sel.kind == .text {
                Button("Edit Text") { beginEditing(sel.id) }
                    .buttonStyle(CapsuleButtonStyle(quiet: true))
            }
            Button { deleteSelected() } label: { Label("Delete", systemImage: "trash") }
                .buttonStyle(CapsuleButtonStyle(quiet: true))
                .lineLimit(1).fixedSize()
                .help("Remove this mark from the picture (Delete)")
        }
    }

    /// The frame: sliders for how round, how much margin and how deep a shadow;
    /// the background as none, one colour, or two along an angle — with Josh's
    /// combos one click away.
    private var frameControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                chip("Frame", symbol: "photo.artframe", on: true)
                slider("Corners", value: $frame.cornerRadius, in: 0...FrameStyle.maxCornerRadius, readout: cornersReadout)
                slider("Margin", value: $frame.padding, in: 0...FrameStyle.maxPadding, readout: marginReadout)
                slider("Shadow", value: $frame.shadow, in: 0...1, readout: shadowReadout)
                    .disabled(frame.padding <= 0)
                Spacer(minLength: 0)
                if !frame.isPlain {
                    Button("No frame") { withAnimation(.easeOut(duration: 0.18)) { frame = .plain } }
                        .buttonStyle(.link).font(.caption)
                }
            }
            backgroundRow
                .opacity(frame.padding > 0 ? 1 : 0.45)
                .disabled(frame.padding <= 0)
                .help(frame.padding > 0 ? "" : "Give the picture a margin to show a background")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        // Pinned leading: a row wider than the window then loses its right end,
        // never its labels. Centred, both edges went (2026-09-16).
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(.easeOut(duration: 0.18), value: frame.background.kind)
    }

    // MARK: Watermark

    /// The watermark being edited; a fresh one until something is set.
    private var wm: Watermark { watermark ?? .suggested }

    /// Change the watermark, and the kept one with it while "every edit" is on.
    private func setWatermark(_ change: (inout Watermark) -> Void) {
        var w = wm
        change(&w)
        watermark = w
        if everyEdit { Watermark.store(w) }
    }

    private func wmBinding<T>(_ get: @escaping (Watermark) -> T, _ set: @escaping (inout Watermark, T) -> Void) -> Binding<T> {
        Binding(get: { get(wm) }, set: { value in setWatermark { set(&$0, value) } })
    }

    /// Words or a logo; where; how big and how strong; and whether every new
    /// edit should start with it.
    private var watermarkControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                chip("Watermark", symbol: "seal", on: true)
                Picker("", selection: Binding(get: { wmKind }, set: { kind in
                    wmKind = kind
                    setWatermark {
                        $0.imageName = kind == .logo ? logoNames.first : nil
                        if kind == .stamp { if $0.stamp == nil { $0.stamp = Watermark.Stamp(name: Watermark.Stamp.thisPerson) } }
                        else { $0.stamp = nil }
                    }
                })) {
                    Text("Text").tag(WatermarkKind.text)
                    Text("Logo").tag(WatermarkKind.logo)
                    Text("Stamp").tag(WatermarkKind.stamp)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help("Words, a logo, or an audit stamp: who attests, when it was captured and attested, on which Mac, and a digest of the original")
                switch wmKind {
                case .logo:
                    logoChoices
                case .stamp:
                    TextField("Your name", text: wmBinding({ $0.stamp?.name ?? "" }, { $0.stamp?.name = $1 }))
                        .textFieldStyle(.roundedBorder).font(.callout).frame(width: 150)
                    fontMenu(wmBinding({ $0.font }, { $0.font = $1 }))
                    stampLines
                case .text:
                    TextField("Your name or company", text: wmBinding({ $0.text }, { $0.text = $1 }))
                        .textFieldStyle(.roundedBorder).font(.callout).frame(width: 190)
                    fontMenu(wmBinding({ $0.font }, { $0.font = $1 }))
                }
                separator
                caption("Ink")
                Picker("", selection: wmBinding({ $0.ink }, { $0.ink = $1 })) {
                    Text("Auto").tag(Watermark.Ink.auto)
                    Text(wmKind == .logo ? "As is" : "Colour").tag(Watermark.Ink.own)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help("Auto sets it in white or near-black, whichever reads against what is under it, with a soft halo of the other.")
                if wm.ink == .own, wmKind != .logo {
                    colourWell("", color: wmBinding({ $0.color }, { $0.color = $1 }), open: $pickingWatermarkColour)
                }
                Spacer(minLength: 0)
                if !(watermark?.isEmpty ?? true) {
                    Button("No watermark") { withAnimation(.easeOut(duration: 0.18)) { watermark = nil; branding = false } }
                        .buttonStyle(.link).font(.caption)
                }
            }
            HStack(spacing: 12) {
                caption("Place")
                placementPicker
                separator
                slider("Size", value: wmBinding({ $0.size }, { $0.size = $1 }), in: Watermark.sizeRange,
                       readout: "\(Int((wm.size * 100).rounded()))%", width: 100)
                slider("Opacity", value: wmBinding({ $0.opacity }, { $0.opacity = $1 }), in: Watermark.opacityRange,
                       readout: "\(Int((wm.opacity * 100).rounded()))%", width: 100)
                separator
                Toggle("Use on every edit", isOn: Binding(get: { everyEdit }, set: { on in
                    everyEdit = on
                    Watermark.onEveryEdit = on
                    Watermark.store(on ? wm : nil)
                }))
                .toggleStyle(.checkbox).font(.caption)
                .help("Keep this watermark and start every new edit with it. Change it here any time and the kept one follows.")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    /// The watermark as the canvas shows it: a stamp with its values filled
    /// the way Save will fill them, attested as of now.
    private func previewWatermark(source: CGImage) -> Watermark? {
        guard let wm = watermark, !wm.isEmpty else { return nil }
        guard let s = wm.stamp else { return wm }
        var shown = wm
        shown.stamp = s.filled(source: source, capturedAt: capturedAt, sourceIsOriginal: sourceIsOriginal)
        return shown
    }

    /// Which lines the stamp carries.
    private var stampLines: some View {
        HStack(spacing: 8) {
            Toggle("Captured", isOn: wmBinding({ $0.stamp?.captured ?? true }, { $0.stamp?.captured = $1 }))
                .help("When the picture was taken — the file's own date")
            Toggle("Attested", isOn: wmBinding({ $0.stamp?.attested ?? true }, { $0.stamp?.attested = $1 }))
                .help("When this edit is saved")
            Toggle("Mac", isOn: wmBinding({ $0.stamp?.machine ?? true }, { $0.stamp?.machine = $1 }))
                .help("This Mac's name")
            Toggle("SHA-256", isOn: wmBinding({ $0.stamp?.digest ?? true }, { $0.stamp?.digest = $1 }))
                .help("A digest of the original picture's pixels — the same for any lossless copy, so an auditor with the original can check it")
        }
        .toggleStyle(.checkbox).font(.caption)
    }

    private var placementPicker: some View {
        HStack(spacing: 2) {
            ForEach(Watermark.Placement.allCases, id: \.self) { place in
                let on = wm.placement == place
                Button { setWatermark { $0.placement = place } } label: {
                    Image(systemName: placementSymbol(place))
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 24)
                        .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(on ? AnyShapeStyle(ShotPalette.accent) : AnyShapeStyle(Color.primary.opacity(0.06))))
                }
                .buttonStyle(.plain)
                .help(place.name)
            }
        }
    }

    private func placementSymbol(_ place: Watermark.Placement) -> String {
        switch place {
        case .topLeft:     return "arrow.up.left.square"
        case .topRight:    return "arrow.up.right.square"
        case .bottomLeft:  return "arrow.down.left.square"
        case .bottomRight: return "arrow.down.right.square"
        case .centre:      return "square.circle"
        case .tiled:       return "square.grid.3x3"
        }
    }

    /// The logos kept for watermarking, and a way to bring another in.
    private var logoChoices: some View {
        HStack(spacing: 6) {
            ForEach(logoNames, id: \.self) { name in
                let on = wm.imageName == name
                Button { setWatermark { $0.imageName = name } } label: {
                    AspectThumbnail(path: WatermarkImages.url(for: name).path, aspect: 1.4, pixels: 120)
                        .frame(width: 34, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(2)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(ShotPalette.accent, lineWidth: on ? 2 : 0))
                }
                .buttonStyle(.plain)
                .help(name)
                .contextMenu {
                    Button("Remove “\(name)”") {
                        WatermarkImages.remove(name)
                        logoNames = WatermarkImages.names()
                        if wm.imageName == name { setWatermark { $0.imageName = logoNames.first } }
                    }
                }
            }
            Button { chooseLogo() } label: {
                Label(logoNames.isEmpty ? "Choose a logo…" : "Add…", systemImage: "photo.badge.plus")
            }
            .buttonStyle(CapsuleButtonStyle(quiet: true))
            .help("A logo of your own, ideally a PNG with a transparent background. It is kept by ShotScribe, so the watermark outlives the file.")
        }
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use as Watermark"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let name = try WatermarkImages.add(url)
                logoNames = WatermarkImages.names()
                setWatermark { $0.imageName = name }
            } catch {
                model.report("Couldn’t bring that logo in: \(error.localizedDescription)")
            }
        }
    }

    private func loadLogo() {
        guard let name = watermark?.imageName else { logo = nil; return }
        if logo?.name == name { return }
        logo = WatermarkImages.load(name).map { (name, $0) }
    }

    // MARK: Fonts

    private var markFont: Binding<TextFont> {
        Binding(get: { selection?.font ?? font },
                set: { f in font = f; apply { if $0.kind.takesFontSize { $0.font = f } } })
    }

    /// The four system designs, then every family installed.
    private func fontMenu(_ selection: Binding<TextFont>) -> some View {
        Menu {
            ForEach(TextFont.designs, id: \.self) { f in
                Toggle(f.name, isOn: Binding(get: { selection.wrappedValue == f }, set: { _ in selection.wrappedValue = f }))
            }
            Divider()
            Menu("Installed Fonts") {
                ForEach(families, id: \.self) { family in
                    Toggle(family, isOn: Binding(get: { selection.wrappedValue == .family(family) },
                                                 set: { _ in selection.wrappedValue = .family(family) }))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "textformat").font(.system(size: 10, weight: .semibold))
                Text(selection.wrappedValue.name).font(.caption.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(selection.wrappedValue.isInstalled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help(selection.wrappedValue.isInstalled ? "The face labels and step numbers are set in"
                                                 : "“\(selection.wrappedValue.name)” is not installed here; the system face stands in")
        .onAppear { if families.isEmpty { families = TextFont.installedFamilies() } }
    }

    // MARK: Crop and resize

    private var fullRect: CGRect {
        CGRect(x: 0, y: 0, width: source?.width ?? 0, height: source?.height ?? 0)
    }

    /// The picture as it will be saved, before the frame.
    private var outputSize: (width: Int, height: Int) {
        let r = (crop ?? fullRect).standardized.integral
        return (Int((r.width * scale).rounded()), Int((r.height * scale).rounded()))
    }

    private var cropControls: some View {
        HStack(spacing: 12) {
            chip("Crop", symbol: "crop", on: true)
            if let d = cropDraft {
                Text("\(Int(d.width)) × \(Int(d.height)) px").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Whole picture") { cropDraft = fullRect }
                .buttonStyle(CapsuleButtonStyle(quiet: true))
                .disabled(cropDraft == fullRect)
            Button("Cancel") { leaveCrop() }
                .buttonStyle(CapsuleButtonStyle(quiet: true))
            Button("Apply") { applyCrop() }
                .buttonStyle(CapsuleButtonStyle(prominent: true))
                .keyboardShortcut(.return, modifiers: [])
                .disabled((cropDraft ?? fullRect).width < 8 || (cropDraft ?? fullRect).height < 8)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private func applyCrop() {
        let d = (cropDraft ?? fullRect).standardized.integral.intersection(fullRect)
        crop = d == fullRect ? nil : d
        leaveCrop()
    }

    private func leaveCrop() {
        cropDraft = nil
        cropDrag = .none
        if tool == .crop { tool = .select }
    }

    private var resizeControls: some View {
        let base = (crop ?? fullRect).standardized.integral
        return HStack(spacing: 12) {
            chip("Resize", symbol: "arrow.down.left.and.arrow.up.right", on: true)
            caption("Saved at")
            Text("\(outputSize.width) × \(outputSize.height) px").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            separator
            Picker("", selection: Binding(get: { Int((scale * 100).rounded()) },
                                          set: { scale = CGFloat($0) / 100; widthDraft = "\(outputSize.width)" })) {
                ForEach([25, 50, 75, 100], id: \.self) { Text("\($0)%").tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            separator
            caption("Width")
            TextField("px", text: $widthDraft)
                .textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 70)
                .onSubmit {
                    if let w = Int(widthDraft), w > 0, base.width > 0 {
                        scale = min(max(CGFloat(w) / base.width, 0.05), 3)
                    }
                    widthDraft = "\(outputSize.width)"
                }
            Text("height follows").font(.caption2).foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            if abs(scale - 1) > 0.001 {
                Button("As taken") { scale = 1; widthDraft = "\(outputSize.width)" }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private var cornersReadout: String {
        if frame.cornerRadius <= 0.002 { return "Square" }
        if frame.cornerRadius >= FrameStyle.maxCornerRadius - 0.002 { return "Round" }
        return "\(Int((frame.cornerRadius / FrameStyle.maxCornerRadius * 100).rounded()))%"
    }
    private var marginReadout: String {
        frame.padding <= 0.002 ? "None" : "\(Int((frame.padding * 100).rounded()))%"
    }
    private var shadowReadout: String {
        frame.shadow <= 0.01 ? "None" : "\(Int((frame.shadow * 100).rounded()))%"
    }

    private var backgroundKind: Binding<FrameStyle.Background.Kind> {
        Binding(get: { frame.background.kind }, set: { frame.background.kind = $0 })
    }
    private var firstColor: Binding<MarkColor> {
        Binding(get: { frame.background.first }, set: { frame.background.first = $0 })
    }
    private var secondColor: Binding<MarkColor> {
        Binding(get: { frame.background.second }, set: { frame.background.second = $0 })
    }

    private var backgroundRow: some View {
        HStack(spacing: 12) {
            caption("Fill")
            Picker("", selection: backgroundKind) {
                Text("None").tag(FrameStyle.Background.Kind.none)
                Text("Colour").tag(FrameStyle.Background.Kind.solid)
                Text("Gradient").tag(FrameStyle.Background.Kind.gradient)
                Text("Image").tag(FrameStyle.Background.Kind.image)
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()

            if frame.background.kind == .image {
                separator
                imageChoices
            } else if frame.background.kind != .none {
                separator
                colourWell(frame.background.kind == .gradient ? "From" : "Colour", color: firstColor, open: $pickingFirst)
                if frame.background.kind == .gradient {
                    colourWell("To", color: secondColor, open: $pickingSecond)
                    slider("Angle", value: $frame.background.angle, in: 0...360,
                           readout: "\(Int(frame.background.angle.rounded()))°", width: 90)
                }
                separator
                caption("Combos")
                combos
            }
            Spacer(minLength: 0)
        }
        .onChange(of: frame.background.imageName) { _ in loadBackgroundImage() }
        .onAppear { loadBackgroundImage() }
    }

    /// The shipped combos, the operator's own after them, and a + to make one
    /// from a hex code or the colour wheel.
    private var combos: some View {
        HStack(spacing: 5) {
            ForEach(FrameStyle.combos, id: \.name) { combo in comboDot(combo) }
            ForEach(customCombos, id: \.name) { combo in
                comboDot(combo)
                    .contextMenu {
                        Button("Remove “\(combo.name)”") {
                            customCombos.removeAll { $0.name == combo.name }
                            FrameStyle.setCustomCombos(customCombos)
                        }
                    }
            }
            Button { addingCombo = true } label: {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
                    .background(Circle().strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    .padding(3)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("A combo of your own — a hex code or the colour wheel")
            .popover(isPresented: $addingCombo, arrowEdge: .bottom) { comboMaker }
        }
    }

    /// Two colours by hex or by wheel, a name, and it joins the row.
    private var comboMaker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New combo").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                comboColourField("From", color: $comboA, hex: $hexA)
                comboColourField("To", color: $comboB, hex: $hexB)
            }
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Color(cgColor: comboA.cgColor), Color(cgColor: comboB.cgColor)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 22)
            TextField("Name", text: $comboName).textFieldStyle(.roundedBorder).controlSize(.small)
            HStack {
                Text("Right-click a combo of yours to remove it.").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Add") {
                    let name = comboName.trimmingCharacters(in: .whitespaces)
                    let combo = FrameStyle.Combo(name: name.isEmpty ? "\(comboA.hex) → \(comboB.hex)" : name,
                                                 background: .gradient(comboA, comboB, angle: 45))
                    customCombos.removeAll { $0.name == combo.name }
                    customCombos.append(combo)
                    FrameStyle.setCustomCombos(customCombos)
                    frame.background = combo.background
                    comboName = ""
                    addingCombo = false
                }
                .buttonStyle(CapsuleButtonStyle(prominent: true))
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func comboColourField(_ name: String, color: Binding<MarkColor>, hex: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ColorPicker("", selection: Binding(
                    get: { Color(cgColor: color.wrappedValue.cgColor) },
                    set: { new in
                        guard let ns = NSColor(new).usingColorSpace(.sRGB) else { return }
                        color.wrappedValue = MarkColor(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent)
                        hex.wrappedValue = color.wrappedValue.hex
                    }), supportsOpacity: false)
                    .labelsHidden()
                TextField("#RRGGBB", text: hex)
                    .textFieldStyle(.roundedBorder).controlSize(.small).font(.caption.monospaced())
                    .frame(width: 84)
                    .onSubmit {
                        let s = hex.wrappedValue.trimmingCharacters(in: .whitespaces)
                        let digits = s.hasPrefix("#") ? String(s.dropFirst()) : s
                        if digits.count == 6 || digits.count == 3, Int(digits, radix: 16) != nil {
                            color.wrappedValue = MarkColor(hex: s)
                            hex.wrappedValue = color.wrappedValue.hex
                        } else {
                            hex.wrappedValue = color.wrappedValue.hex
                        }
                    }
            }
        }
    }

    /// The pictures kept for framing, and a way to bring another in.
    private var imageChoices: some View {
        HStack(spacing: 6) {
            ForEach(backgroundNames, id: \.self) { name in
                let on = frame.background.imageName == name
                Button { frame.background.imageName = name } label: {
                    AspectThumbnail(path: BackgroundImages.url(for: name).path, aspect: 1.4, pixels: 120)
                        .frame(width: 34, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(2)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(ShotPalette.accent, lineWidth: on ? 2 : 0))
                }
                .buttonStyle(.plain)
                .help(name)
                .contextMenu {
                    Button("Remove “\(name)”") {
                        BackgroundImages.remove(name)
                        backgroundNames = BackgroundImages.names()
                        if frame.background.imageName == name { frame.background.imageName = backgroundNames.first }
                    }
                }
            }
            Button { chooseBackgroundImage() } label: {
                Label(backgroundNames.isEmpty ? "Choose a picture…" : "Add…", systemImage: "photo.badge.plus")
            }
            .buttonStyle(CapsuleButtonStyle(quiet: true))
            .help("A picture of your own — a brand background, a texture. It is kept by ShotScribe, so the frame outlives the file.")
            if frame.background.imageName == nil, !backgroundNames.isEmpty {
                Text("Pick one").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use as Background"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let name = try BackgroundImages.add(url)
                backgroundNames = BackgroundImages.names()
                frame.background.imageName = name
            } catch {
                model.report("Couldn’t bring that picture in: \(error.localizedDescription)")
            }
        }
    }

    private func loadBackgroundImage() {
        guard let name = frame.background.imageName else { backgroundImage = nil; return }
        if backgroundImage?.name == name { return }
        Task.detached(priority: .userInitiated) {
            let image = BackgroundImages.load(name)
            await MainActor.run { backgroundImage = image.map { (name, $0) } }
        }
    }

    private func comboDot(_ combo: FrameStyle.Combo) -> some View {
        let on = frame.background == combo.background
        let colors = [Color(cgColor: combo.background.first.cgColor), Color(cgColor: combo.background.second.cgColor)]
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { frame.background = combo.background }
        } label: {
            Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .padding(3)
                .overlay(Circle().strokeBorder(ShotPalette.accent, lineWidth: on ? 2 : 0))
        }
        .buttonStyle(.plain)
        .help(combo.name)
    }

    private func slider(_ name: String, value: Binding<CGFloat>, in range: ClosedRange<CGFloat>,
                        readout: String, width: CGFloat = 120) -> some View {
        HStack(spacing: 7) {
            caption(name)
            Slider(value: value, in: range).controlSize(.small).frame(width: width)
            Text(readout).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
        }
    }

    /// One colour as one swatch. Click it for the palette and a picker — eleven
    /// dots per well, twice, was wider than the window.
    private func colourWell(_ name: String, color: Binding<MarkColor>, open: Binding<Bool>) -> some View {
        HStack(spacing: 5) {
            caption(name)
            Button { open.wrappedValue.toggle() } label: {
                HStack(spacing: 4) {
                    Circle().fill(Color(cgColor: color.wrappedValue.cgColor))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                        .frame(width: 18, height: 18)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(.leading, 3).padding(.trailing, 6).frame(height: 24)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(color.wrappedValue.name)
            .popover(isPresented: open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 6), spacing: 6) {
                        ForEach(FrameStyle.backgroundPalette, id: \.self) { c in
                            paletteDot(c, selected: color.wrappedValue == c) {
                                color.wrappedValue = c
                            }
                        }
                    }
                    Divider()
                    HStack {
                        Text("Any colour").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { Color(cgColor: color.wrappedValue.cgColor) },
                            set: { new in
                                guard let ns = NSColor(new).usingColorSpace(.sRGB) else { return }
                                color.wrappedValue = MarkColor(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent)
                            }), supportsOpacity: false)
                            .labelsHidden()
                    }
                }
                .padding(12)
                .frame(width: 210)
            }
        }
    }

    private func paletteDot(_ c: MarkColor, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(Color(cgColor: c.cgColor))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                .frame(width: 20, height: 20)
                .padding(3)
                .overlay(Circle().strokeBorder(ShotPalette.accent, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .help(c.name)
    }

    private func chip(_ words: String, symbol: String, on: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(words).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9).frame(height: 24)
        .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
        .background(Capsule().fill(on ? AnyShapeStyle(ShotPalette.accent) : AnyShapeStyle(Color.primary.opacity(0.07))))
        .fixedSize()
    }

    /// What the style controls are about to change. The same row styles the
    /// next mark and restyles a selected one; this says which, every time.
    private var target: some View {
        let kind = styleKind
        let name = kind.flatMap { EditorTool(rawValue: $0.rawValue)?.name } ?? "Nothing"
        let symbol = kind.flatMap { EditorTool(rawValue: $0.rawValue)?.symbol } ?? "cursorarrow"
        let editing = selection != nil
        return HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(editing ? "Editing \(name.lowercased())"
                 : kind == nil ? "Select a mark to edit it" : "Next \(name.lowercased())")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9).frame(height: 24)
        .foregroundStyle(editing ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
        .background(Capsule().fill(editing ? AnyShapeStyle(ShotPalette.accent)
                                           : AnyShapeStyle(Color.primary.opacity(0.07))))
        .fixedSize()
    }

    private func caption(_ words: String) -> some View {
        Text(words).font(.caption2.weight(.medium)).foregroundStyle(.tertiary).fixedSize()
    }

    private var currentBadge: Mark.Badge { selection?.badge ?? badge }

    private var badgePicker: some View {
        HStack(spacing: 2) {
            ForEach(Mark.Badge.allCases, id: \.self) { b in
                let on = currentBadge == b
                Button {
                    badge = b
                    apply { if $0.kind == .step { $0.badge = b } }
                } label: {
                    badgeGlyph(b)
                        .frame(width: 30, height: 24)
                        .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(on ? AnyShapeStyle(ShotPalette.accent) : AnyShapeStyle(Color.primary.opacity(0.06))))
                }
                .buttonStyle(.plain)
                .help(b.name)
            }
        }
    }

    private func badgeGlyph(_ b: Mark.Badge) -> some View {
        Image(systemName: b == .bubble ? "1.circle.fill" : b == .square ? "1.square.fill"
                          : b == .chevron ? "chevron.right.2" : b == .flag ? "flag.fill" : "mappin.circle.fill")
            .font(.system(size: 13, weight: b == .chevron ? .bold : .medium))
    }

    private func renumber() {
        let before = marks
        marks = Mark.renumbered(marks)
        if marks != before { record(before) }
    }

    private var currentColor: MarkColor { selection?.color ?? (styleKind == .highlight ? highlightColor : color) }

    private var swatches: some View {
        HStack(spacing: 5) {
            ForEach(MarkColor.palette, id: \.self) { c in
                Button { setColor(c) } label: {
                    Circle()
                        .fill(Color(cgColor: c.cgColor))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(c == .white ? 0.3 : 0.12), lineWidth: 1))
                        .frame(width: 18, height: 18)
                        .padding(2)
                        .overlay(Circle().strokeBorder(ShotPalette.accent, lineWidth: currentColor == c ? 2 : 0))
                }
                .buttonStyle(.plain)
                .help(c.name)
            }
            ColorPicker("", selection: Binding(
                get: { Color(cgColor: currentColor.cgColor) },
                set: { new in
                    guard let ns = NSColor(new).usingColorSpace(.sRGB) else { return }
                    setColor(MarkColor(red: ns.redComponent, green: ns.greenComponent,
                                       blue: ns.blueComponent, alpha: 1))
                }), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 30)
                .help("Any colour")
        }
    }

    private var weightPicker: some View {
        HStack(spacing: 2) {
            ForEach(Weight.allCases) { w in
                let on = currentWeight == w
                Button { setWeight(w) } label: {
                    Capsule().fill(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                        .frame(width: 18, height: w == .thin ? 1.5 : w == .medium ? 3 : 5)
                        .frame(width: 30, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(on ? AnyShapeStyle(ShotPalette.accent) : AnyShapeStyle(Color.primary.opacity(0.06))))
                }
                .buttonStyle(.plain)
                .help(w.name)
            }
        }
    }

    /// One slider from half size to two-and-a-half. It restyles the selected
    /// mark live and records a single undo step when the drag ends.
    private var sizeSlider: some View {
        let value = Binding<CGFloat>(
            get: { currentSizeFactor },
            set: { f in
                sizeFactor = f
                guard let id = selected, let i = marks.firstIndex(where: { $0.id == id }),
                      marks[i].kind.takesFontSize, let source else { return }
                let base = ImageEditor.baseFontSize(for: CGSize(width: source.width, height: source.height))
                marks[i].fontSize = (base * f).rounded()
            })
        return HStack(spacing: 7) {
            caption("Size")
            Slider(value: value, in: 0.5...2.5) { editing in
                if editing { sizeDragBefore = marks }
                else if let before = sizeDragBefore { sizeDragBefore = nil; if marks != before { record(before) } }
            }
            .controlSize(.small).frame(width: 110)
            .help("Drag for the size of text and step numbers")
            Text("\(Int((currentSizeFactor * 100).rounded()))%")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            if let source {
                // While cropping, the whole base is shown, unframed, so what is
                // being cut can be seen; otherwise the picture as it will be saved.
                let fit = Fit(image: source, crop: tool == .crop ? nil : crop,
                              frame: tool == .crop ? .plain : frame, in: geo.size)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in paint(ctx, fit: fit, source: source) }
                    if let id = editingText, let mark = marks.first(where: { $0.id == id }) {
                        textField(for: mark, fit: fit)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { g in tool == .crop ? cropChanged(g, fit: fit) : dragChanged(g, fit: fit) }
                        .onEnded { g in tool == .crop ? cropEnded() : dragEnded(g, fit: fit) }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        if tool == .select, let sel = selection, sel.kind == .text { beginEditing(sel.id) }
                    }
                )
                .onContinuousHover { phase in hover(phase, fit: fit) }
            } else {
                VStack(spacing: 8) {
                    if !failed { ProgressView() }
                    Text(failed ? "This file could not be opened as an image." : "Opening…")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(18)
    }

    private func paint(_ ctx: GraphicsContext, fit: Fit, source: CGImage) {
        let full = CGSize(width: source.width, height: source.height)
        let visible = fit.visible
        let size = visible.size
        let outer = CGRect(origin: fit.origin, size: fit.size)
        let picture = fit.view(visible)
        let shownFrame = tool == .crop ? FrameStyle.plain : frame
        let radius = shownFrame.radius(for: size) * fit.scale
        let shape = Path(roundedRect: picture, cornerRadius: radius, style: .circular)

        // The frame, as it will be saved: background across the whole output,
        // then the picture's shadow on it. The same colours and direction as
        // `ImageEditor.render`, drawn here in the view's own terms.
        switch shownFrame.background.kind {
        case .none:
            if shownFrame.isPlain {
                ctx.stroke(Path(outer.insetBy(dx: -0.5, dy: -0.5)), with: .color(.primary.opacity(0.15)), lineWidth: 1)
            } else {
                checkerboard(ctx, in: outer)
            }
        case .solid:
            ctx.fill(Path(outer), with: .color(Color(cgColor: shownFrame.background.first.cgColor)))
        case .gradient:
            let (start, end) = ImageEditor.gradientPoints(angle: shownFrame.background.angle, in: outer, upright: false)
            ctx.fill(Path(outer), with: .linearGradient(
                Gradient(colors: [Color(cgColor: shownFrame.background.first.cgColor),
                                  Color(cgColor: shownFrame.background.second.cgColor)]),
                startPoint: start, endPoint: end))
        case .image:
            if let bg = backgroundImage, bg.name == shownFrame.background.imageName {
                var clipped = ctx
                clipped.clip(to: Path(outer))
                let fill = ImageEditor.aspectFill(CGSize(width: bg.image.width, height: bg.image.height), in: outer)
                clipped.draw(Image(decorative: bg.image, scale: 1), in: fill)
            } else {
                ctx.fill(Path(outer), with: .color(Color(cgColor: MarkColor.frost.cgColor)))
            }
        }
        if shownFrame.shadow > 0, shownFrame.padding > 0 {
            let short = min(size.width, size.height) * fit.scale
            let s = min(max(shownFrame.shadow, 0), 1)
            var shadowed = ctx
            shadowed.addFilter(.shadow(color: .black.opacity(0.15 + 0.45 * s),
                                       radius: short * 0.03 * (0.5 + s * 1.5) / 2, y: short * 0.012 * (0.5 + s)))
            shadowed.fill(shape, with: .color(.black))
        }

        let live = marks.filter { $0.kind != .pixelate && $0.id != editingText }
        let shown = base ?? source
        ctx.drawLayer { layer in
            layer.clip(to: shape)
            layer.withCGContext { cg in
                cg.translateBy(x: picture.minX, y: picture.minY)
                cg.scaleBy(x: fit.scale, y: fit.scale)
                // Into the visible part of the base: everything below is in
                // base pixels, shifted by the crop's origin.
                cg.translateBy(x: -visible.minX, y: -visible.minY)
                cg.saveGState()
                cg.translateBy(x: 0, y: full.height)
                cg.scaleBy(x: 1, y: -1)
                cg.interpolationQuality = .high
                cg.draw(shown, in: CGRect(origin: .zero, size: full))
                cg.restoreGState()
                ImageEditor.draw(live, in: cg, source: nil)
                if let wm = previewWatermark(source: source) {
                    cg.saveGState()
                    cg.translateBy(x: visible.minX, y: visible.minY)
                    cg.clip(to: CGRect(origin: .zero, size: visible.size))
                    ImageEditor.drawWatermark(wm, in: cg, size: visible.size, under: shown,
                                              underOrigin: visible.origin, logo: logo?.image)
                    cg.restoreGState()
                }
            }
        }

        if tool == .crop, let d = cropDraft {
            // Dim what would go; outline and handle what stays.
            let keep = fit.view(d)
            var scrim = Path(picture)
            scrim.addRect(keep)
            ctx.fill(scrim, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
            ctx.stroke(Path(keep), with: .color(.white), lineWidth: 1.5)
            // Thirds, the way a camera shows them.
            var thirds = Path()
            for i in 1...2 {
                thirds.move(to: CGPoint(x: keep.minX + keep.width * CGFloat(i) / 3, y: keep.minY))
                thirds.addLine(to: CGPoint(x: keep.minX + keep.width * CGFloat(i) / 3, y: keep.maxY))
                thirds.move(to: CGPoint(x: keep.minX, y: keep.minY + keep.height * CGFloat(i) / 3))
                thirds.addLine(to: CGPoint(x: keep.maxX, y: keep.minY + keep.height * CGFloat(i) / 3))
            }
            ctx.stroke(thirds, with: .color(.white.opacity(0.35)), lineWidth: 1)
            for corner in [CGPoint(x: keep.minX, y: keep.minY), CGPoint(x: keep.maxX, y: keep.minY),
                           CGPoint(x: keep.minX, y: keep.maxY), CGPoint(x: keep.maxX, y: keep.maxY)] {
                let dot = CGRect(x: corner.x - 6, y: corner.y - 6, width: 12, height: 12)
                var soft = ctx
                soft.addFilter(.shadow(color: .black.opacity(0.4), radius: 2, y: 1))
                soft.fill(Path(ellipseIn: dot), with: .color(.white))
                ctx.stroke(Path(ellipseIn: dot), with: .color(ShotPalette.accent), lineWidth: 2)
            }
            return
        }

        // The mark under the pointer, before it is clicked.
        if tool == .select, let id = hoveredMark, id != selected, let hov = marks.first(where: { $0.id == id }) {
            let r = fit.view(hov.frame).insetBy(dx: -3, dy: -3)
            ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(ShotPalette.accent.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1.5))
        }

        guard let sel = selection else { return }
        let frameRect = fit.view(sel.frame).insetBy(dx: -4, dy: -4)
        if !sel.kind.isSegment {
            ctx.stroke(Path(frameRect), with: .color(ShotPalette.accent),
                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        }
        for (handle, point) in sel.handles {
            let v = fit.view(point)
            let dot = CGRect(x: v.x - 6, y: v.y - 6, width: 12, height: 12)
            var soft = ctx
            soft.addFilter(.shadow(color: .black.opacity(0.25), radius: 2, y: 1))
            soft.fill(Path(ellipseIn: dot), with: .color(.white))
            ctx.stroke(Path(ellipseIn: dot), with: .color(ShotPalette.accent), lineWidth: 2)
            // The bend handle carries a centre dot: it shapes, the ends stretch.
            if handle == .bend {
                ctx.fill(Path(ellipseIn: dot.insetBy(dx: 3.5, dy: 3.5)), with: .color(ShotPalette.accent))
            }
        }
    }

    /// Transparency, shown the way image apps show it.
    private func checkerboard(_ ctx: GraphicsContext, in rect: CGRect) {
        let cell: CGFloat = 8
        var path = Path()
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX + (row.isMultiple(of: 2) ? 0 : cell)
            while x < rect.maxX {
                path.addRect(CGRect(x: x, y: y, width: min(cell, rect.maxX - x), height: min(cell, rect.maxY - y)))
                x += cell * 2
            }
            y += cell
            row += 1
        }
        ctx.fill(Path(rect), with: .color(.white))
        ctx.fill(path, with: .color(Color(white: 0.88)))
    }

    private func textField(for mark: Mark, fit: Fit) -> some View {
        let frame = fit.view(ImageEditor.labelFrame(text: textDraft, fontSize: mark.fontSize, at: mark.a))
        let size = max(11, mark.fontSize * fit.scale)
        return TextField("Label", text: $textDraft)
            .textFieldStyle(.plain)
            .font(Font(mark.font.font(size: size)))
            .foregroundStyle(mark.color.wantsLightText ? Color.white : Color.black)
            .padding(.horizontal, size * 0.5)
            .frame(minWidth: 120, minHeight: frame.height, alignment: .leading)
            .fixedSize()
            .background(RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                .fill(Color(cgColor: mark.color.cgColor)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                .strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5))
            .offset(x: frame.minX, y: frame.minY)
            .focused($textFocused)
            .onSubmit { commitText() }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(footerHint)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if redacted {
                // Said before the click, not after it.
                // A filled badge, not orange words on grey: those washed out.
                Label("Hidden areas can't be undone after Save", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).frame(height: 22)
                    .background(Capsule().fill(ShotPalette.warning))
                    .fixedSize()
                    .help("A redaction keeps no copy of the original — that is the point of it.")
            } else if reopened {
                Text(sourceIsOriginal ? "Earlier marks are still editable." : "Earlier marks are editable; hidden areas stay hidden.")
                    .font(.caption).foregroundStyle(.tertiary).fixedSize()
            }
            if reopened, sourceIsOriginal {
                Button("Revert to Original…") { confirmRevert = true }
                    .disabled(saving)
                    .help("Remove every mark and the frame, and put the capture back as it was taken")
            }
            Button("Cancel") { close() }
                .keyboardShortcut(.cancelAction)
                .disabled(saving)
            // With nothing to write — a fresh shot whose every-edit watermark
            // was taken off again — the button says so and just closes. A grey
            // Save read as "failing to save" (2026-09-16).
            Button {
                if hasSomethingToSave { save() } else { close() }
            } label: {
                if saving { ProgressView().controlSize(.small) } else { Text(hasSomethingToSave ? "Save" : "Done") }
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(CapsuleButtonStyle(prominent: true))
            .disabled(saving)
            .help(hasSomethingToSave ? "Write the picture with these changes (⌘S)" : "Nothing has changed; the picture stays as it was taken")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .confirmationDialog("Revert to the original capture?", isPresented: $confirmRevert) {
            Button("Revert", role: .destructive) { revert() }
        } message: {
            Text("Every mark and the frame are removed, and the capture goes back to exactly how it was taken.")
        }
    }

    private var footerHint: String {
        if tool == .crop { return EditorTool.crop.hint }
        if resizing { return "Pick a size to save at. The full-size picture stays in the edit." }
        if branding {
            if wmKind == .stamp { return "An audit stamp: your name, when the picture was taken, when you saved it, this Mac, and a SHA-256 of the original's pixels. The times and the digest are filled in when you save." }
            return "A watermark marks the picture as yours. Auto ink reads against whatever is under it; Tiled covers everything; “Use on every edit” keeps it for next time."
        }
        if let sel = selection, tool != .select {
            let name = EditorTool(rawValue: sel.kind.rawValue)?.name.lowercased() ?? "mark"
            return "Drawing: \(tool.hint) The \(name) you just drew can be resized by its handles; to move it or pick another mark, use Select (V)."
        }
        if let sel = selection, sel.kind == .text {
            return "Label selected. Drag to move it, double-click or Return to change the words, Delete to remove it."
        }
        return tool.hint
    }

    /// Keys without a visible button. Hidden buttons are the way to get a key
    /// equivalent on macOS 13; they stand down while a label is being typed,
    /// or typing "a" into a label would switch to the arrow tool.
    private var shortcuts: some View {
        ZStack {
            Button("") { undo() }.keyboardShortcut("z", modifiers: .command)
            Button("") { redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            Group {
                Button("") { nudge(dx: -1, dy: 0) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { nudge(dx: 1, dy: 0) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { nudge(dx: 0, dy: -1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { nudge(dx: 0, dy: 1) }.keyboardShortcut(.downArrow, modifiers: [])
                Button("") { nudge(dx: -10, dy: 0) }.keyboardShortcut(.leftArrow, modifiers: .shift)
                Button("") { nudge(dx: 10, dy: 0) }.keyboardShortcut(.rightArrow, modifiers: .shift)
                Button("") { nudge(dx: 0, dy: -10) }.keyboardShortcut(.upArrow, modifiers: .shift)
                Button("") { nudge(dx: 0, dy: 10) }.keyboardShortcut(.downArrow, modifiers: .shift)
                Button("") { deleteSelected() }.keyboardShortcut(.delete, modifiers: [])
                Button("") { deleteSelected() }.keyboardShortcut(.deleteForward, modifiers: [])
                Button("") { if let sel = selection, sel.kind == .text { beginEditing(sel.id) } }
                    .keyboardShortcut(.return, modifiers: [])
                ForEach(EditorTool.allCases) { t in
                    Button("") { tool = t }.keyboardShortcut(KeyEquivalent(t.key), modifiers: [])
                }
            }
            .disabled(editingText != nil)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: Gestures

    private func dragChanged(_ g: DragGesture.Value, fit: Fit) {
        guard !saving, let source else { return }
        let p = fit.image(g.location)
        if case .none = drag {
            if editingText != nil { commitText() }
            begin(at: fit.image(g.startLocation), fit: fit, source: source)
        }
        switch drag {
        case .create(let id, _):
            update(id) { $0.b = p }
        case .move(let id, let grab, let original, _):
            update(id) { m in
                m = original
                m.move(dx: p.x - grab.x, dy: p.y - grab.y)
            }
        case .resize(let id, let handle, let original, _):
            update(id) { m in m = original.resized(handle, to: p) }
        case .none:
            break
        }
    }

    private func begin(at start: CGPoint, fit: Fit, source: CGImage) {
        switch EditorPress.at(start, drawing: tool.kind != nil, selected: selection,
                              marks: marks, reach: 8 / fit.scale) {
        case .resize(let id, let handle):
            if let sel = selection { drag = .resize(id, handle, original: sel, before: marks) }
            return
        case .move(let id):
            selected = id
            if let hit = marks.first(where: { $0.id == id }) {
                drag = .move(id, grab: start, original: hit, before: marks)
            }
            return
        case .deselect:
            selected = nil
            return
        case .draw:
            break
        }
        guard let kind = tool.kind else { return }
        let size = CGSize(width: source.width, height: source.height)
        let mark = Mark(kind: kind, a: start, b: start,
                        color: kind == .highlight ? highlightColor : color,
                        lineWidth: ImageEditor.baseLineWidth(for: size) * weight.factor,
                        fontSize: (ImageEditor.baseFontSize(for: size) * sizeFactor).rounded(),
                        filled: filled,
                        number: Mark.nextStep(after: marks), badge: badge, font: font)
        let before = marks
        marks.append(mark)
        selected = mark.id
        drag = .create(mark.id, before: before)
    }

    private func dragEnded(_ g: DragGesture.Value, fit: Fit) {
        defer { drag = .none }
        switch drag {
        case .create(let id, let before):
            guard let mark = marks.first(where: { $0.id == id }) else { return }
            if mark.kind == .text {
                beginEditing(id, creating: before)
                return
            }
            if mark.kind == .step {
                // Placed with a click; a drag just moves it to where it ended.
                record(before)
                return
            }
            let big = mark.kind.isSegment
                ? hypot(mark.b.x - mark.a.x, mark.b.y - mark.a.y) > 6 / fit.scale
                : mark.rect.width > 4 / fit.scale && mark.rect.height > 4 / fit.scale
            if big {
                record(before)
            } else {
                marks.removeAll { $0.id == id }
                selected = nil
            }
        case .move(_, _, _, let before), .resize(_, _, _, let before):
            if marks != before { record(before) }
        case .none:
            break
        }
    }

    private func cropChanged(_ g: DragGesture.Value, fit: Fit) {
        guard !saving else { return }
        let p = fit.image(g.location)
        if case .none = cropDrag {
            let start = fit.image(g.startLocation)
            let d = cropDraft ?? fullRect
            let probe = Mark(kind: .rectangle, a: d.origin, b: CGPoint(x: d.maxX, y: d.maxY))
            let reach = 10 / fit.scale
            if let handle = probe.handles.first(where: { hypot($0.1.x - start.x, $0.1.y - start.y) <= reach })?.0 {
                cropDrag = .resize(handle, original: d)
            } else if d.contains(start) {
                cropDrag = .move(grab: start, original: d)
            } else {
                cropDrag = .draw(from: start)
            }
        }
        switch cropDrag {
        case .resize(let handle, let original):
            let probe = Mark(kind: .rectangle, a: original.origin, b: CGPoint(x: original.maxX, y: original.maxY))
            cropDraft = probe.resized(handle, to: p).rect.intersection(fullRect)
        case .move(let grab, let original):
            var moved = original.offsetBy(dx: p.x - grab.x, dy: p.y - grab.y)
            moved.origin.x = min(max(moved.minX, 0), fullRect.width - moved.width)
            moved.origin.y = min(max(moved.minY, 0), fullRect.height - moved.height)
            cropDraft = moved
        case .draw(let from):
            cropDraft = CGRect(x: min(from.x, p.x), y: min(from.y, p.y),
                               width: abs(p.x - from.x), height: abs(p.y - from.y)).intersection(fullRect)
        case .none:
            break
        }
    }

    private func cropEnded() {
        if let d = cropDraft, d.width < 8 || d.height < 8 { cropDraft = fullRect }
        cropDraft = cropDraft?.standardized.integral
        cropDrag = .none
    }

    private func hover(_ phase: HoverPhase, fit: Fit) {
        guard case .active(let location) = phase else { NSCursor.arrow.set(); hoveredMark = nil; return }
        let p = fit.image(location)
        let reach = 8 / fit.scale
        hoveredMark = tool == .select ? marks.last(where: { $0.hit(p, tolerance: reach) })?.id : nil
        if let sel = selection, sel.handles.contains(where: { hypot($0.1.x - p.x, $0.1.y - p.y) <= reach }) {
            NSCursor.crosshair.set()
        } else if tool == .select, marks.contains(where: { $0.hit(p, tolerance: reach) }) {
            NSCursor.openHand.set()
        } else if tool == .select {
            NSCursor.arrow.set()
        } else if tool == .crop {
            NSCursor.crosshair.set()
        } else if tool == .text {
            NSCursor.iBeam.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: Editing

    private func update(_ id: UUID, _ change: (inout Mark) -> Void) {
        guard let i = marks.firstIndex(where: { $0.id == id }) else { return }
        change(&marks[i])
    }

    /// Change the selected mark, as one undoable step.
    private func apply(_ change: (inout Mark) -> Void) {
        guard let id = selected, let i = marks.firstIndex(where: { $0.id == id }) else { return }
        let before = marks
        change(&marks[i])
        if marks != before { record(before) }
    }

    private var currentWeight: Weight {
        guard let sel = selection, let source else { return weight }
        let base = ImageEditor.baseLineWidth(for: CGSize(width: source.width, height: source.height))
        return Weight.allCases.min { abs($0.factor * base - sel.lineWidth) < abs($1.factor * base - sel.lineWidth) } ?? weight
    }

    private var currentSizeFactor: CGFloat {
        guard let sel = selection, sel.kind.takesFontSize, let source else { return sizeFactor }
        let base = ImageEditor.baseFontSize(for: CGSize(width: source.width, height: source.height))
        return min(2.5, max(0.5, sel.fontSize / base))
    }

    private func setColor(_ c: MarkColor) {
        if styleKind == .highlight { highlightColor = c } else { color = c }
        apply { if $0.kind.takesColor { $0.color = c } }
    }

    private func setWeight(_ w: Weight) {
        weight = w
        guard let source else { return }
        let base = ImageEditor.baseLineWidth(for: CGSize(width: source.width, height: source.height))
        apply { $0.lineWidth = base * w.factor }
    }

    /// Arrow keys move the selected mark a pixel; with Shift, ten.
    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard selection != nil else { return }
        apply { $0.move(dx: dx, dy: dy) }
    }

    private func deleteSelected() {
        guard let id = selected, marks.contains(where: { $0.id == id }) else { return }
        let before = marks
        marks.removeAll { $0.id == id }
        selected = nil
        record(before)
    }

    /// `creating` is the list as it stood before a brand-new label, so an
    /// empty one can vanish without leaving an undo step behind.
    @State private var textBefore: [Mark]?

    private func beginEditing(_ id: UUID, creating before: [Mark]? = nil) {
        guard let mark = marks.first(where: { $0.id == id }) else { return }
        textBefore = before ?? marks
        textDraft = mark.text
        selected = id
        editingText = id
        DispatchQueue.main.async { textFocused = true }
    }

    private func commitText() {
        guard let id = editingText else { return }
        let words = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = textBefore ?? marks
        editingText = nil
        textFocused = false
        if words.isEmpty {
            marks.removeAll { $0.id == id }
            selected = nil
            if marks != before { record(before) }
        } else {
            update(id) { $0.text = words }
            if marks != before { record(before) }
        }
        textBefore = nil
        textDraft = ""
    }

    private func record(_ before: [Mark]) {
        undoStack.append(before)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func undo() {
        guard editingText == nil, let last = undoStack.popLast() else { return }
        redoStack.append(marks)
        marks = last
        if let id = selected, !marks.contains(where: { $0.id == id }) { selected = nil }
    }

    private func redo() {
        guard editingText == nil, let next = redoStack.popLast() else { return }
        undoStack.append(marks)
        marks = next
        if let id = selected, !marks.contains(where: { $0.id == id }) { selected = nil }
    }

    // MARK: Loading, baking, saving

    private func load() {
        guard source == nil else { return }
        let url = self.url
        Task.detached(priority: .userInitiated) {
            // An edit made here comes back as it was left: the picture under
            // the marks, and the marks as objects.
            if let kept = EditStore.load(for: url) {
                await MainActor.run {
                    source = kept.base
                    base = kept.base
                    if marks.isEmpty { marks = kept.document.marks }
                    frame = kept.document.frame
                    crop = kept.document.crop
                    scale = kept.document.scale
                    if watermark == nil { watermark = kept.document.watermark; wmKind = .of(watermark) }
                    capturedAt = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                    loadLogo()
                    sourceIsOriginal = kept.document.baseIsOriginal
                    reopened = true
                    rebake()
                }
                return
            }
            let image = ImageEditor.load(url)
            await MainActor.run {
                source = image
                base = image
                failed = image == nil
                // Set once, used on every edit: a fresh edit starts with the kept watermark.
                if watermark == nil, let kept = Watermark.forNewEdit() { watermark = kept; wmKind = .of(kept) }
                capturedAt = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                loadLogo()
                rebake()
            }
        }
    }

    private func revert() {
        saving = true
        model.revertEdit(url) { ok in
            saving = false
            if ok { close() }
        }
    }

    /// Bake the pixelations into the picture underneath. Only the newest
    /// request is kept, so dragging a pixelation around does not queue a
    /// render per mouse event.
    private func rebake() {
        guard let source else { return }
        let pixels = marks.filter { $0.kind == .pixelate }
        baseGeneration += 1
        let generation = baseGeneration
        guard !pixels.isEmpty else { base = source; return }
        Task.detached(priority: .userInitiated) {
            let out = ImageEditor.render(source, marks: pixels)
            await MainActor.run {
                if generation == baseGeneration { base = out ?? source }
            }
        }
    }

    private func save() {
        if editingText != nil { commitText() }
        guard let source else { return }
        saving = true
        if tool == .crop { applyCrop() }
        model.saveEdit(source: source, marks: marks, frame: frame, crop: crop, scale: scale,
                       watermark: watermark, sourceIsOriginal: sourceIsOriginal, to: url) { ok in
            saving = false
            if ok { close() }
        }
    }
}

/// How the framed picture sits in the canvas, and the arithmetic between
/// points on screen and pixels in the capture. Marks live in the capture's
/// pixels; the frame's margin is outside them, so every conversion steps over it.
private struct Fit {
    let scale: CGFloat
    let origin: CGPoint
    let size: CGSize
    /// The part of the base on screen, in base pixels — the crop, or all of it.
    let visible: CGRect
    let inset: CGFloat

    init(image: CGImage, crop: CGRect?, frame: FrameStyle, in box: CGSize) {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        visible = crop.map { $0.standardized.integral.intersection(full) }.flatMap { $0.isEmpty ? nil : $0 } ?? full
        inset = frame.inset(for: visible.size)
        let out = frame.outputSize(for: visible.size)
        let s = min(box.width / max(out.width, 1), box.height / max(out.height, 1), 1)
        scale = max(s, 0.01)
        size = CGSize(width: out.width * scale, height: out.height * scale)
        origin = CGPoint(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2)
    }

    /// Base pixels for a point on screen, clamped to what is visible.
    func image(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max((p.x - origin.x) / scale - inset + visible.minX, visible.minX), visible.maxX),
                y: min(max((p.y - origin.y) / scale - inset + visible.minY, visible.minY), visible.maxY))
    }

    func view(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - visible.minX + inset) * scale + origin.x, y: (p.y - visible.minY + inset) * scale + origin.y)
    }

    func view(_ r: CGRect) -> CGRect {
        CGRect(origin: view(r.origin), size: CGSize(width: r.width * scale, height: r.height * scale))
    }
}

/// Opens an editor window when the model asks for one. **Started by the app**,
/// like the capture card — a library mounted somewhere else must not open
/// windows by itself.
@MainActor
public final class EditorPresenter {
    private let model: ShotScribeModel
    private var windows: [String: NSWindow] = [:]
    private var watching: AnyCancellable?

    public init(model: ShotScribeModel) { self.model = model }

    public func start() {
        watching = model.$editRequest
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] request in self?.open(request.url) }
    }

    private func open(_ url: URL) {
        if let existing = windows[url.path] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var size = CGSize(width: 960, height: 700)
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let h = props[kCGImagePropertyPixelHeight] as? CGFloat, w > 0, h > 0 {
            // The picture at up to 80% of the screen, plus the bars around it.
            let backing = NSScreen.main?.backingScaleFactor ?? 1
            let s = min(screen.width * 0.8 / (w / backing), screen.height * 0.68 / (h / backing), 1)
            size = CGSize(width: max(880, w / backing * s + 36), height: max(520, h / backing * s + 36 + 160))
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Edit — \(url.deletingPathExtension().lastPathComponent)"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(url: url, model: model) { [weak self, weak window] in
            window?.close()
            self?.windows[url.path] = nil
        })
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[url.path] = window
    }
}
