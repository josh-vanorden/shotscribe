import Foundation

/// The app, read off the capture's own chrome. A full-screen shot starts with
/// the menu bar, whose first item after the Apple mark is the app's name; a
/// window shot starts with its title bar. Metadata never records the app
/// (checked 2026-09-11: a capture carries its type and screen rect, nothing
/// else), but the OCR that already runs reads those lines anyway.
///
/// The structure half of screenshot-to-code's "extract, don't redraw", pointed
/// at filing: it is what the `{app}` template token spells. Best effort, and
/// honest about it — a browser's title bar names the tab, not the browser.
public enum Chrome {

    /// Menu titles that can follow an app's name in the menu bar. Kept to
    /// menus: an app's own name must never be here, or the app is read as a
    /// menu and dropped ("Terminal" was, on the first real run; VS Code shows
    /// as "Code", and its menu bar has a Terminal menu, which is fine — the
    /// scan stops at "File" long before it).
    static let menuWords: Set<String> = [
        "file", "edit", "view", "go", "window", "help", "format", "insert", "tools", "history",
        "bookmarks", "shell", "selection", "find", "navigate", "editor", "product", "debug",
        "source", "arrange", "share", "develop", "message", "mailbox", "image", "layer", "type",
        "select", "filter", "play", "song", "controls", "account", "store", "library",
        "conversation", "call", "meeting", "project", "build", "run", "refactor", "vcs", "git",
        "paragraph", "sheet", "data", "chart", "chat", "actions", "audio", "clip", "sequence",
        "effects", "tab", "tabs", "table", "slide", "plugins", "analysis", "shape", "modify",
        "services", "profiles", "scripts",
    ]

    /// The app or window name in `lines`, or nil when the top of the capture
    /// holds nothing that reads as either.
    public static func app(in lines: [OCR.TextLine]) -> String? {
        // The menu bar: the top strip, its lines short, read left to right.
        // Vision may hand the whole bar back as one line or one per menu.
        // Fast recognition draws generous boxes: a 28px bar on a 700px shot is
        // 4% tall on paper and nearer 6% as Vision reports it.
        let bar = lines.filter { $0.top < 5 && $0.height < 6.5 }.sorted { $0.left < $1.left }
        for line in bar where line.left < 25 {
            var words: [String] = []
            for raw in line.text.split(separator: " ") {
                let word = String(raw.drop(while: { !$0.isLetter && !$0.isNumber }))
                // The Apple mark reads as junk or as one stray accented letter;
                // no app is one character long.
                guard word.count >= 2 else { continue }
                if menuWords.contains(word.lowercased()) { break }
                words.append(word)
                if words.count == 3 { break }
            }
            let name = Naming.sanitize(words.joined(separator: " "), maxChars: 30)
            if name.count >= 2 { return name }
        }
        // The title bar: the topmost line that sits roughly centred.
        let centred = lines.filter { $0.top < 9 && $0.left > 15 && $0.left + $0.width < 85 }
        if let title = centred.min(by: { $0.top < $1.top }) {
            let head = title.text.components(separatedBy: [" — ", " – ", " - ", " | ", " · "].first { title.text.contains($0) } ?? "\u{0}").first ?? title.text
            let name = Naming.sanitize(head.split(separator: " ").prefix(3).joined(separator: " "), maxChars: 30)
            if name.count >= 2 { return name }
        }
        return nil
    }

    /// What the titler should read: everything below the chrome, when there is
    /// chrome. A menu bar's "File Edit View Window Help" is not what a shot is
    /// about, and it was ending up in titles. A shot with no chrome is read whole.
    public static func body(of lines: [OCR.TextLine]) -> [OCR.TextLine] {
        guard app(in: lines) != nil else { return lines }
        return lines.filter { $0.top >= 5 }
    }
}
