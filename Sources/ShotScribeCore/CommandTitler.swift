import Foundation

/// Titles through any command that prints a line: the shipped presets (Codex,
/// Gemini CLI, Cursor Agent, Ollama) and whatever the person types. The
/// instruction and the text read off the capture travel as one argument in
/// place of `{prompt}`; the reply's last non-empty line is the answer, parsed
/// the way Claude's is. Same runner as `ClaudeTitler`, same watchdog.
public struct CommandTitler: Titler {
    public enum Error: LocalizedError {
        case notFound(String), empty, failed(String)
        public var errorDescription: String? {
            switch self {
            case .notFound(let n): return "`\(n)` isn’t installed or isn’t on the PATH."
            case .empty:           return "The command returned nothing."
            case .failed(let m):   return "The command failed: \(m)"
            }
        }
    }

    public let template: String
    public let model: String?
    public let modelFlag: String?
    public var timeout: TimeInterval

    public init(template: String, model: String? = nil, modelFlag: String? = nil, timeout: TimeInterval = 45) {
        self.template = template; self.model = model; self.modelFlag = modelFlag; self.timeout = timeout
    }

    public func title(forOCRText text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= TitlerPrompt.minOCRChars else { return "Screenshot" }
        return LabelCleaner.clean(try await complete(system: TitlerPrompt.system, text: trimmed))
    }

    public func labelling(forOCRText text: String, vocabulary: [String]) async throws -> Labelling {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= TitlerPrompt.minOCRChars else { return Labelling(title: "Screenshot") }
        guard !vocabulary.isEmpty else { return Labelling(title: try await title(forOCRText: trimmed)) }
        let raw = try await complete(system: TitlerPrompt.system(taggedFrom: vocabulary), text: trimmed)
        return ClaudeTitler.parseLabelling(raw, vocabulary: vocabulary)
    }

    /// The argument list: the template split on whitespace, `{prompt}` and
    /// `{model}` replaced as whole arguments (never spliced into a shell), the
    /// model flag appended when the preset has one and a model is set.
    public static func argv(template: String, prompt: String, model: String?, modelFlag: String?) -> [String] {
        var args: [String] = []
        for token in template.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init) {
            let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            switch bare {
            case "{prompt}": args.append(prompt)
            case "{model}":  if let model, !model.isEmpty { args.append(model) }
            case "{system}": break   // the instruction rides inside {prompt}; the token is tolerated
            default:         args.append(bare.replacingOccurrences(of: "{model}", with: model ?? ""))
            }
        }
        if let modelFlag, let model, !model.isEmpty, !template.contains("{model}") {
            args += [modelFlag, model]
        }
        return args
    }

    private func complete(system: String, text: String) async throws -> String {
        let argv = Self.argv(template: template, prompt: "\(system)\n\nOCR text:\n\(text)\n\nLabel:",
                             model: model, modelFlag: modelFlag)
        guard let name = argv.first else { throw Error.notFound(template) }
        guard let bin = Executables.resolve(name) else { throw Error.notFound(name) }
        let run = try await CommandRunner.run(bin, Array(argv.dropFirst()), timeout: timeout)
        let answer = run.out.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? ""
        if run.status == 0, !answer.isEmpty { return answer }
        let reason = run.err.isEmpty ? run.out : run.err
        throw reason.isEmpty ? Error.empty : Error.failed(String(reason.prefix(200)))
    }
}
