import XCTest
import AppKit
@testable import ShotScribeCore

/// "Bring your own AI": one setting names the titler for every door, the
/// generic command titler runs anything that prints a line, the endpoint
/// titler speaks the one request shape every compatible server takes, and
/// the upgrade changes nobody's titler.
final class AIProviderTests: XCTestCase {

    private var suite: UserDefaults!

    override func setUp() {
        suite = UserDefaults(suiteName: "ai-tests-\(UUID().uuidString)")
        ShotScribeDefaults.suiteOverride = suite
        Secrets.store = MemoryStore()
    }
    override func tearDown() {
        ShotScribeDefaults.suiteOverride = nil
        suite.removePersistentDomain(forName: suite.description)
    }

    func testTheDefaultIsWhatOnePointFiveDid() {
        XCTAssertEqual(ShotScribeDefaults.aiProvider().kind, .claude, "nothing stored: Claude Code, as before")
        suite.set(false, forKey: "shotscribe.useClaude")
        XCTAssertEqual(ShotScribeDefaults.aiProvider().kind, .offline, "the old switch off means offline")
        ShotScribeDefaults.setAIProvider(AIProvider(kind: .ollama, model: "qwen2.5:7b"))
        XCTAssertEqual(ShotScribeDefaults.aiProvider(), AIProvider(kind: .ollama, model: "qwen2.5:7b"))
    }

    func testAnUnknownKindFromANewerBuildDecodesToTheDefault() throws {
        let data = Data(#"{"kind":"holodeck","model":"x"}"#.utf8)
        let p = try JSONDecoder().decode(AIProvider.self, from: data)
        XCTAssertEqual(p.kind, .claude)
        XCTAssertEqual(p.model, "x")
    }

    func testThePromptIsOneArgumentAndTheModelRidesItsFlag() {
        let argv = CommandTitler.argv(template: "codex exec --sandbox read-only {prompt}",
                                      prompt: "line one\nline two", model: "o4-mini", modelFlag: "-m")
        XCTAssertEqual(argv, ["codex", "exec", "--sandbox", "read-only", "line one\nline two", "-m", "o4-mini"])
        XCTAssertEqual(CommandTitler.argv(template: "ollama run {model} {prompt}", prompt: "p", model: "llama3.2", modelFlag: nil),
                       ["ollama", "run", "llama3.2", "p"])
        XCTAssertEqual(CommandTitler.argv(template: "tool \"{prompt}\"", prompt: "p", model: nil, modelFlag: "-m"),
                       ["tool", "p"], "quotes around a token are tolerated; no model, no flag")
    }

    func testAnyCommandThatPrintsALineIsATitler() async throws {
        // A command that ignores the prompt and prints one line is enough.
        let l = try await CommandTitler(template: "/bin/echo Deploy Dashboard | code, dashboard", timeout: 5)
            .labelling(forOCRText: "some screen text here", vocabulary: ["code", "dashboard", "email"])
        XCTAssertEqual(l.title, "Deploy Dashboard")
        XCTAssertEqual(l.tags, ["code", "dashboard"])
    }

    func testAFailingOrMissingCommandIsAVisibleError() async {
        do {
            _ = try await CommandTitler(template: "/usr/bin/false {prompt}", timeout: 5).title(forOCRText: "enough text here")
            XCTFail("false should fail")
        } catch { XCTAssertTrue(error is CommandTitler.Error, "a command that exits non-zero is a titler error: \(error)") }
        do {
            _ = try await CommandTitler(template: "no-such-tool-xyz {prompt}", timeout: 5).title(forOCRText: "enough text here")
            XCTFail("a missing tool should fail")
        } catch CommandTitler.Error.notFound(let n) { XCTAssertEqual(n, "no-such-tool-xyz") }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testTheWatchdogEndsAHungCommand() async {
        let start = Date()
        do {
            _ = try await CommandTitler(template: "/bin/sleep 30", timeout: 0.5).title(forOCRText: "enough text here")
            XCTFail("should have been terminated")
        } catch {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testTheEndpointRequestIsTheCompatibleShape() throws {
        let req = EndpointTitler.request(baseURL: URL(string: "http://localhost:11434/v1")!, model: "llama3.2",
                                         apiKey: "sk-test", system: "S", user: "U")
        XCTAssertEqual(req.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "llama3.2")
        XCTAssertEqual((body["messages"] as? [[String: Any]])?.count, 2)
        let noKey = EndpointTitler.request(baseURL: URL(string: "http://localhost:11434/v1")!, model: "m", apiKey: nil, system: "S", user: "U")
        XCTAssertNil(noKey.value(forHTTPHeaderField: "Authorization"), "a local server has no key")
    }

    func testTheEndpointReplyIsParsedAndGarbageIsRefused() throws {
        let ok = Data(#"{"choices":[{"message":{"role":"assistant","content":" Slack Thread | chat "}}]}"#.utf8)
        XCTAssertEqual(try EndpointTitler.parse(ok), "Slack Thread | chat")
        XCTAssertThrowsError(try EndpointTitler.parse(Data("<html>".utf8)))
        XCTAssertThrowsError(try EndpointTitler.parse(Data(#"{"choices":[]}"#.utf8)))
    }

    func testAvailabilityAndTheTitlerFollowTheKind() {
        XCTAssertNil(AIProvider(kind: .offline).makeTitler())
        XCTAssertTrue(AIProvider(kind: .offline).availability().isReady)
        XCTAssertTrue(AIProvider(kind: .claude).makeTitler() is ClaudeTitler)
        XCTAssertTrue(AIProvider(kind: .command, command: "/bin/echo hi").makeTitler() is CommandTitler)
        XCTAssertTrue(AIProvider(kind: .command, command: "/bin/echo hi").availability().isReady)
        XCTAssertFalse(AIProvider(kind: .command, command: "nonexistent-tool-q").availability().isReady)
        XCTAssertFalse(AIProvider(kind: .endpoint).availability().isReady, "no URL yet")
        XCTAssertTrue(AIProvider(kind: .endpoint, model: "m", endpoint: "http://localhost:11434/v1").availability().isReady)
        XCTAssertTrue(AIProvider(kind: .endpoint, model: "m", endpoint: "http://localhost:11434/v1").makeTitler() is EndpointTitler)
    }

    func testTheHandoffLineFollowsTheAssistant() {
        XCTAssertTrue(SendToClaude.line(forImageAt: "/a/b.png", kind: .claude).hasPrefix("/screenshot "))
        XCTAssertTrue(SendToClaude.line(forImageAt: "/a/b.png", kind: .ollama).hasPrefix("Look at the screenshot"), "only Claude Code has /screenshot")
        XCTAssertTrue(SendToClaude.line(forImageAt: "/a/b.png", kind: .cursor).hasPrefix("Look at the screenshot"))
        XCTAssertEqual(AIProvider.Kind.cursor.assistant, "Cursor")
        XCTAssertEqual(AIProvider.Kind.ollama.assistant, "Ollama")
        XCTAssertEqual(AIProvider.Kind.offline.symbol, "wifi.slash", "offline wears its own mark")
        XCTAssertEqual(AIProvider.Kind.gemini.brand, "gemini")
    }

    func testTheMachinePreferenceMapsToAProvider() {
        XCTAssertEqual(AIProvider.suggested(from: LLMPreference(provider: .local, endpoint: nil, model: "qwen2.5:7b", isSet: true)),
                       AIProvider(kind: .ollama, model: "qwen2.5:7b"))
        XCTAssertEqual(AIProvider.suggested(from: LLMPreference(provider: .openai, endpoint: nil, model: nil, isSet: true))?.endpoint,
                       "https://api.openai.com/v1")
        XCTAssertNil(AIProvider.suggested(from: LLMPreference(provider: .apple, endpoint: nil, model: nil, isSet: true)))
        XCTAssertNil(AIProvider.suggested(from: LLMPreference(provider: .claude, endpoint: nil, model: nil, isSet: false)))
    }

    /// The command's first token goes to `command -v` in a login shell, so it
    /// must be a name and nothing else.
    func testOnlyAPlainNameReachesTheShell() {
        XCTAssertTrue(Executables.isPlainName("codex"))
        XCTAssertTrue(Executables.isPlainName("cursor-agent"))
        XCTAssertTrue(Executables.isPlainName("llm2.0_beta+"))
        XCTAssertFalse(Executables.isPlainName("codex; rm -rf ~"))
        XCTAssertFalse(Executables.isPlainName("$(open /Applications/Calculator.app)"))
        XCTAssertFalse(Executables.isPlainName(""))
        XCTAssertNil(Executables.resolve("no-such; echo pwned"))
        // "echo hi; rm" is harmless: argv, no shell — "hi;" and "rm" are echo's words.
        // A metacharacter glued to the name is what must never reach `command -v`.
        XCTAssertFalse(AIProvider(kind: .command, command: "codex;rm -rf ~ {prompt}").availability().isReady)
        XCTAssertTrue(AIProvider(kind: .command, command: "/bin/echo hi; rm {prompt}").availability().isReady)
    }

    func testPlainHTTPToARemoteHostIsSaidOutLoud() {
        let remote = AIProvider(kind: .endpoint, model: "m", endpoint: "http://gateway.example.com/v1").availability()
        XCTAssertTrue(remote.isReady)
        XCTAssertTrue(remote.text.contains("unencrypted"), remote.text)
        let local = AIProvider(kind: .endpoint, model: "m", endpoint: "http://localhost:11434/v1").availability()
        XCTAssertFalse(local.text.contains("unencrypted"), "a local server is not a wire")
        let tls = AIProvider(kind: .endpoint, model: "m", endpoint: "https://api.openai.com/v1").availability()
        XCTAssertFalse(tls.text.contains("unencrypted"))
    }

    /// The endpoint titler is the one network call. A stored URL whose scheme
    /// is not http(s) — file:, ftp: — must reach neither the readiness line
    /// nor the factory, because the stored value does not always arrive
    /// through the AI tab's field.
    func testOnlyWebSchemesReachTheEndpointTitler() {
        for bad in ["ftp://host/v1", "file:///etc/hosts", "gopher://host/v1"] {
            let p = AIProvider(kind: .endpoint, model: "m", endpoint: bad)
            XCTAssertFalse(p.availability().isReady, bad)
            XCTAssertNil(p.makeTitler(), bad)
        }
        let upper = AIProvider(kind: .endpoint, model: "m", endpoint: "HTTPS://api.openai.com/v1")
        XCTAssertTrue(upper.availability().isReady, "the scheme check is not case-sensitive")
    }

    func testSecretsStayOutOfDefaults() {
        Secrets.store.set("sk-abc", for: Secrets.endpointKeyAccount)
        XCTAssertEqual(Secrets.store.get(Secrets.endpointKeyAccount), "sk-abc")
        Secrets.store.set(nil, for: Secrets.endpointKeyAccount)
        XCTAssertNil(Secrets.store.get(Secrets.endpointKeyAccount))
        XCTAssertNil(suite.string(forKey: "endpoint-api-key"))
    }

    /// A titler that fails is reported and the shot still gets the offline
    /// name — never a silent "Screenshot".
    func testAFailingTitlerIsReportedAndTheOfflineNameStands() async throws {
        struct Broken: Titler {
            func title(forOCRText text: String) async throws -> String { throw CommandTitler.Error.empty }
        }
        let size = NSSize(width: 600, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        ("Billing Console Invoice" as NSString).draw(at: NSPoint(x: 30, y: 200), withAttributes: [
            .font: NSFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID().uuidString).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        var renamer = Renamer(titler: Broken())
        let reported = Reported()
        renamer.onTitlerError = { reported.errors.append("\($0)") }
        let got = await renamer.labelling(fileAt: url)
        XCTAssertEqual(reported.errors.count, 1, "the failure reaches the door")
        XCTAssertNotEqual(got.title, "Screenshot", "the offline titler named it: \(got.title)")
        XCTAssertTrue(got.title.contains("Billing") || got.title.contains("Invoice"), got.title)
    }
}

private final class Reported: @unchecked Sendable {
    var errors: [String] = []
}
