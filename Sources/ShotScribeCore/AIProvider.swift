import Foundation

/// Who titles a capture — chosen once, honoured by every door. "Bring your own
/// AI": a CLI the person is already signed in to (Claude Code, Codex, Gemini
/// CLI, Cursor Agent, Ollama), any command that prints a line, an
/// OpenAI-compatible endpoint, or nothing at all. The app holds no key of its
/// own; an endpoint key lives in the Keychain.
///
/// Lenient to decode on purpose: a value written by a newer build with a kind
/// this one does not know falls back to the default rather than throwing, and
/// a missing field is simply unset.
public struct AIProvider: Codable, Equatable, Sendable {

    public enum Kind: String, Codable, CaseIterable, Sendable {
        // The picker's order: the named tools, then the two open doors.
        case offline, claude, codex, gemini, cursor, ollama, endpoint, command

        /// The picker's word for it.
        public var name: String {
            switch self {
            case .offline:  return "Offline — keywords only"
            case .claude:   return "Claude Code"
            case .codex:    return "Codex"
            case .gemini:   return "Gemini CLI"
            case .cursor:   return "Cursor Agent"
            case .ollama:   return "Ollama (local)"
            case .endpoint: return "An endpoint"
            case .command:  return "Other CLI…"
            }
        }

        /// Who the Send-to tile hands a shot to: the titler itself, by name.
        /// The tile carries this kind's mark, so a glance at the landing zone
        /// says which AI is in use — offline included.
        public var assistant: String {
            switch self {
            case .offline:  return "an assistant"
            case .claude:   return "Claude"
            case .codex:    return "Codex"
            case .gemini:   return "Gemini"
            case .cursor:   return "Cursor"
            case .ollama:   return "Ollama"
            case .command:  return "your assistant"
            case .endpoint: return "your model"
            }
        }

        /// The brand mark's name under `assets/brands/`, for kinds that have one.
        public var brand: String? {
            switch self {
            case .claude: return "claude"
            case .codex:  return "codex"
            case .gemini: return "gemini"
            case .cursor: return "cursor"
            case .ollama: return "ollama"
            default:      return nil
            }
        }

        /// The SF Symbol for kinds that have no brand: no network, a shell, a URL.
        public var symbol: String? {
            switch self {
            case .offline:  return "wifi.slash"
            case .command:  return "terminal"
            case .endpoint: return "network"
            default:        return nil
            }
        }

        /// The executable a CLI kind needs. nil when there is none to look for.
        public var executable: String? {
            switch self {
            case .claude:  return "claude"
            case .codex:   return "codex"
            case .gemini:  return "gemini"
            case .cursor:  return "cursor-agent"
            case .ollama:  return "ollama"
            default:       return nil
            }
        }

        /// The command as shipped, editable in the AI tab. `{prompt}` is one
        /// argument holding the instruction and the text read off the capture;
        /// `{model}` is the model name. Each preset carries the flags that keep
        /// the CLI from acting on the text it is handed — the prompt is
        /// whatever was on screen — and the tab says to keep them.
        public var commandTemplate: String? {
            switch self {
            case .codex:  return "codex exec --sandbox read-only --skip-git-repo-check {prompt}"
            case .gemini: return "gemini -p {prompt} --sandbox"
            case .cursor: return "cursor-agent -p {prompt} --output-format text"
            case .ollama: return "ollama run {model} {prompt}"
            default:      return nil
            }
        }

        /// How the preset passes a model, when one is set.
        var modelFlag: String? {
            switch self {
            case .codex, .gemini: return "-m"
            case .cursor:         return "--model"
            default:              return nil
            }
        }

        public var defaultModel: String? {
            switch self {
            case .ollama:   return "llama3.2"
            default:        return nil
            }
        }

        /// One quiet line about where the text goes.
        public var whereTextGoes: String {
            switch self {
            case .offline:  return "Nothing leaves this Mac; titles are the salient words."
            case .claude:   return "The text read off each capture goes to Anthropic through your own Claude Code login, with its tools disabled."
            case .codex:    return "The text goes to OpenAI through your own Codex login, in a read-only sandbox."
            case .gemini:   return "The text goes to Google through your own Gemini CLI login, sandboxed."
            case .cursor:   return "The text goes to Cursor through your own Cursor login."
            case .ollama:   return "Nothing leaves this Mac; the model runs in Ollama."
            case .command:  return "The text goes wherever your command sends it."
            case .endpoint: return "The text goes to the endpoint you name; a local one keeps it on this Mac."
            }
        }
    }

    public var kind: Kind
    /// A model name, for kinds that take one. nil means the kind's default.
    public var model: String?
    /// The command to run, for `.command`, or an edited preset for a CLI kind.
    public var command: String?
    /// The base URL of an OpenAI-compatible API, e.g. `http://localhost:11434/v1`.
    public var endpoint: String?

    public init(kind: Kind, model: String? = nil, command: String? = nil, endpoint: String? = nil) {
        self.kind = kind; self.model = model; self.command = command; self.endpoint = endpoint
    }

    public static let `default` = AIProvider(kind: .claude)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .kind) ?? Kind.claude.rawValue
        kind = Kind(rawValue: raw) ?? .claude
        model = try c.decodeIfPresent(String.self, forKey: .model)
        command = try c.decodeIfPresent(String.self, forKey: .command)
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint)
    }

    /// The command that will actually run for a CLI kind.
    public var effectiveCommand: String? {
        if let command, !command.trimmingCharacters(in: .whitespaces).isEmpty { return command }
        return kind.commandTemplate
    }

    public var effectiveModel: String? { model ?? kind.defaultModel }

    // MARK: Can it run here?

    public enum Availability: Equatable, Sendable {
        case ready(String)
        case missing(String)
        public var isReady: Bool { if case .ready = self { return true } else { return false } }
        public var text: String {
            switch self { case .ready(let s), .missing(let s): return s }
        }
    }

    public func availability() -> Availability {
        switch kind {
        case .offline:
            return .ready("Keyword titles, no model.")
        case .claude:
            return ClaudeTitler.isAvailable() ? .ready("claude found.") : .missing("Claude Code isn’t installed.")
        case .codex, .gemini, .cursor, .ollama:
            let name = effectiveCommand.flatMap(Self.firstToken) ?? kind.executable ?? ""
            if let path = Executables.resolve(name) { return .ready("\(name) found at \(path).") }
            return .missing("\(kind.name) isn’t installed (no `\(name)` on the PATH).")
        case .command:
            guard let name = effectiveCommand.flatMap(Self.firstToken) else { return .missing("No command yet.") }
            if let path = Executables.resolve(name) { return .ready("\(name) found at \(path).") }
            return .missing("`\(name)` isn’t on the PATH.")
        case .endpoint:
            guard let e = endpoint, let url = URL(string: e), url.scheme != nil, url.host != nil
            else { return .missing("Enter the endpoint’s base URL, like http://localhost:11434/v1.") }
            guard Self.isWebScheme(url) else { return .missing("The endpoint must be an http or https URL.") }
            guard let m = model, !m.isEmpty else { return .missing("Enter a model name.") }
            let host = url.host ?? e
            let local = ["localhost", "127.0.0.1", "::1"].contains(host) || host.hasSuffix(".local")
            if url.scheme?.lowercased() == "http", !local {
                return .ready("\(host) · \(m) — plain http: the text read off each capture, and any saved API key, travel unencrypted to that host.")
            }
            return .ready("\(host) · \(m)")
        }
    }

    // MARK: The titler

    /// nil means the offline titler. A provider that cannot run here still
    /// returns its titler: the failure is then visible where the capture is,
    /// which is what the app wants, rather than silently swapped for keywords.
    public func makeTitler(timeout: TimeInterval = 45) -> Titler? {
        switch kind {
        case .offline:
            return nil
        case .claude:
            return ClaudeTitler(timeout: timeout, model: model)
        case .codex, .gemini, .cursor, .ollama, .command:
            guard let template = effectiveCommand else { return nil }
            return CommandTitler(template: template, model: effectiveModel, modelFlag: kind.modelFlag, timeout: timeout)
        case .endpoint:
            guard let e = endpoint, let url = URL(string: e), Self.isWebScheme(url) else { return nil }
            return EndpointTitler(baseURL: url, model: model ?? "", apiKey: Secrets.store.get(Secrets.endpointKeyAccount), timeout: timeout)
        }
    }

    /// The endpoint titler speaks http(s) and nothing else. Any other scheme —
    /// file:, ftp: — would turn the one network call into a read of something
    /// else entirely, whose contents then flow into names and tags. The stored
    /// value does not always come through the field in the AI tab, so the
    /// factory checks too, not just the tab's readiness line.
    static func isWebScheme(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    /// The machine-level choice (`~/.config/llm/provider.json`) as a provider,
    /// when it names one this build can honour.
    public static func suggested(from preference: LLMPreference) -> AIProvider? {
        guard preference.isSet else { return nil }
        switch preference.provider {
        case .claude: return AIProvider(kind: .claude, model: preference.model)
        case .local:  return AIProvider(kind: preference.endpoint == nil ? .ollama : .endpoint,
                                        model: preference.model, endpoint: preference.endpoint)
        case .openai: return AIProvider(kind: .endpoint, model: preference.model ?? "gpt-4o-mini",
                                        endpoint: preference.endpoint ?? "https://api.openai.com/v1")
        case .gemini: return AIProvider(kind: .gemini, model: preference.model)
        case .apple:  return nil
        }
    }

    static func firstToken(_ command: String) -> String? {
        command.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
    }
}
