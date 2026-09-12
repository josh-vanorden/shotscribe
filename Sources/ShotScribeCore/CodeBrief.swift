import Foundation

/// Stage two. A capture has a name and a filing; the person now wants it as
/// code. The agent and the repo live in Claude Code, so the app hands over
/// everything it knows — the file, the text with its positions, the working
/// discipline — as one brief to paste there, in the project the code should
/// land in. Self-contained on purpose: it works whether or not ShotScribe's
/// MCP server is registered.
public enum CodeBrief {

    public static func text(forImageAt path: String, maxLines: Int = 80) -> String {
        let (size, lines) = OCR.recognizeLayout(atPath: path, maxLines: maxLines)
        var brief = """
        Rebuild this screenshot as code in this project.

        Image: \(path)
        Read it. Its text is below with positions, in percent of the image, top-left \
        origin: the positions say what is a title, a row of buttons, a sidebar; the \
        strings are exact, use them verbatim. The image is for colour, spacing and \
        everything the text cannot say.

        How to work:
        - Pick the stack from this repo (package.json, Package.swift, pyproject.toml). \
        A repo with a framework gets a component in its own idiom, never a single \
        file of CDN scripts.
        - Create once, then edit with exact-string changes. Never regenerate a file \
        you already wrote.
        - Extract, don't redraw: reference the project's existing assets or leave a \
        labelled placeholder slot. Never embed the screenshot; never hand-draw SVG art.
        - Render and verify against the image before you say done. Fix what differs, \
        then stop; do not polish past the capture.
        - Say what you built in two sentences and offer the diff.

        """
        if size == .zero {
            brief += "Layout: the image could not be read here; work from the image alone.\n"
        } else if lines.isEmpty {
            brief += "Layout: \(Int(size.width))×\(Int(size.height)) px, no text recognised; work from the image alone.\n"
        } else {
            brief += "Layout (\(Int(size.width))×\(Int(size.height)) px, \(lines.count) lines, reading order):\n"
            for l in lines {
                brief += String(format: "top %5.1f  left %5.1f  w %5.1f  h %4.1f  %@\n", l.top, l.left, l.width, l.height, l.text)
            }
        }
        return brief
    }
}
