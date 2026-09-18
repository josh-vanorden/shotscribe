import SwiftUI
import AppKit
import ShotScribeCore

/// **The menu bar item's menu**, in order of whose job it is: the Library
/// first, then what ShotScribe does, then the app's own plumbing last.
///
/// It was a 340pt panel of switches that repeated the Library's inspector and
/// the card's buttons. What is left is what is worth a trip to the menu bar:
/// getting to the Library, pausing, naming the capture that was missed, the
/// last capture into the editor or under the kept watermark, and the handful
/// most recently named. Where the Library and Settings open, and how to quit,
/// are the host's to say — this package never knows what is hosting it.
public struct ShotScribeMenu: View {
    @ObservedObject var model: ShotScribeModel
    private let goToLibrary: () -> Void
    private let openSettings: () -> Void
    private let quit: () -> Void

    public init(model: ShotScribeModel, goToLibrary: @escaping () -> Void,
                openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
        self.model = model
        self.goToLibrary = goToLibrary; self.openSettings = openSettings; self.quit = quit
    }

    public var body: some View {
        Button("Go to Library") { goToLibrary() }

        Section(status) {
            Toggle("Rename new captures", isOn: $model.watching)
                .disabled(model.otherInstanceRunning)
            Button("Rename latest capture now") { model.renameLatest() }
                .disabled(model.busy || model.otherInstanceRunning)
            if let error = model.lastError { Text(error) }
        }

        if let last = model.newestShot {
            Section("Last capture — \(Self.short(last.name))") {
                Button("Edit with ShotScribe…") { model.markUp(last) }
                    .disabled(Capture.isMovie(last.url))
                Menu("Watermark") {
                    let kept = Watermark.stored()
                    Button("Apply") { model.setWatermark(kept, on: last) }
                        .disabled(kept == nil || Capture.isMovie(last.url))
                    Button("Remove") { model.setWatermark(nil, on: last) }
                        .disabled(!model.hasWatermark(last))
                    if kept == nil {
                        Divider()
                        Text("Set one up in the editor, then tick “Use on every edit”")
                    }
                }
            }
        }

        if !model.events.isEmpty {
            Menu("Recent") {
                ForEach(model.events.prefix(5)) { event in
                    let url = model.folder.appendingPathComponent(event.to)
                    Menu(Self.short(event.to)) {
                        Button("Edit with ShotScribe…") { model.editFile(url) }
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        if model.canUndo(event) {
                            Divider()
                            Button("Undo Rename") { model.undo(event) }
                        }
                    }
                }
                Divider()
                Button("Go to Library") { goToLibrary() }
            }
        }

        Divider()
        Button("Settings…") { openSettings() }
        Button("Quit ShotScribe") { quit() }
    }

    private var status: String {
        if model.otherInstanceRunning { return "Standing down" }
        if model.busy { return "Naming the newest capture…" }
        return model.watching ? "Watching \(model.folder.lastPathComponent)" : "Paused — \(model.folder.lastPathComponent)"
    }

    /// A name that fits a menu: the head and the tail, the middle elided.
    static func short(_ name: String, limit: Int = 44) -> String {
        let stem = (name as NSString).deletingPathExtension
        guard stem.count > limit else { return stem }
        return "\(stem.prefix(limit / 2 - 1))…\(stem.suffix(limit / 2 - 1))"
    }
}
