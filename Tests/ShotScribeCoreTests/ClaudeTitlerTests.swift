import XCTest
@testable import ShotScribeCore

/// What the Claude titler makes of what the CLI printed. The exit status is
/// not the verdict: an answer in the result envelope is the answer.
final class ClaudeTitlerTests: XCTestCase {

    private func envelope(_ result: String, isError: Bool = false) -> String {
        """
        {"type":"result","subtype":"\(isError ? "error" : "success")","is_error":\(isError),"duration_ms":4002,"num_turns":1,"result":"\(result)","session_id":"abc"}
        """
    }

    func testAnAnsweredEnvelopeIsTheAnswerWhateverTheExitStatus() throws {
        XCTAssertEqual(try ClaudeTitler.answer(out: envelope("IT Support Tickets | ticket, dashboard"), err: "", status: 0),
                       "IT Support Tickets | ticket, dashboard")
        // The case that named two shots with the offline title: a good answer, exit 1.
        XCTAssertEqual(try ClaudeTitler.answer(out: envelope("Slack Cert Discussion | chat"), err: "", status: 1),
                       "Slack Cert Discussion | chat")
    }

    func testAnErrorEnvelopeIsAFailureWithItsOwnWords() {
        XCTAssertThrowsError(try ClaudeTitler.answer(out: envelope("Rate limit reached", isError: true), err: "", status: 1)) { error in
            guard case ClaudeTitler.CLIError.failed(let reason) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(reason, "Rate limit reached")
        }
    }

    func testPlainTextWithExitZeroIsStillAnAnswer() throws {
        // A CLI that ignores the output flag.
        XCTAssertEqual(try ClaudeTitler.answer(out: "AWS Billing Console | dashboard", err: "", status: 0),
                       "AWS Billing Console | dashboard")
    }

    func testPlainTextWithANonZeroExitIsTheReason() {
        // The CLI prints this on stdout, with exit 1, when the session has expired.
        XCTAssertThrowsError(try ClaudeTitler.answer(out: "Failed to authenticate: OAuth session expired and could not be refreshed",
                                                     err: "", status: 1)) { error in
            guard case ClaudeTitler.CLIError.failed(let reason) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(reason.hasPrefix("Failed to authenticate"), reason)
        }
    }

    // MARK: - The call itself

    /// A title call runs no hooks and saves no session, and still denies
    /// every tool: the quiet flags add to the boundary, never replace it.
    func testATitleCallRunsNoHooksAndSavesNoSession() throws {
        let args = ClaudeTitler.arguments(prompt: "OCR text:\nx\n\nLabel:", system: "sys", model: nil, quiet: true)
        XCTAssertTrue(args.contains("--no-session-persistence"))
        let settings = try XCTUnwrap(args.firstIndex(of: "--settings").map { args[$0 + 1] })
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(settings.utf8)) as? [String: Any])
        XCTAssertEqual(parsed["disableAllHooks"] as? Bool, true)
        XCTAssertTrue(args.contains("--strict-mcp-config"))
        let denied = try XCTUnwrap(args.firstIndex(of: "--disallowedTools").map { args[$0 + 1] })
        for tool in ["Bash", "Read", "Write", "Edit", "WebFetch"] { XCTAssertTrue(denied.contains(tool), tool) }
        XCTAssertEqual(args[args.firstIndex(of: "--output-format")! + 1], "json")
    }

    func testTheFallbackCallIsTheOldOneAndAModelIsPassedEitherWay() {
        let quiet = ClaudeTitler.arguments(prompt: "p", system: "s", model: "sonnet", quiet: true)
        let plain = ClaudeTitler.arguments(prompt: "p", system: "s", model: "sonnet", quiet: false)
        XCTAssertFalse(plain.contains("--no-session-persistence"))
        XCTAssertFalse(plain.contains("--settings"))
        XCTAssertEqual(Array(quiet.prefix(plain.count)), plain, "quiet is the old call plus the two flags")
        XCTAssertTrue(plain.contains("--strict-mcp-config"))
        XCTAssertEqual(plain[plain.firstIndex(of: "--model")! + 1], "sonnet")
    }

    /// An older `claude` refuses the call over a flag it does not know; that,
    /// and only that, is asked again the old way.
    func testOnlyARefusedFlagIsAskedAgain() {
        XCTAssertTrue(ClaudeTitler.rejectedAFlag(out: "error: unknown option '--no-session-persistence'", err: ""))
        XCTAssertTrue(ClaudeTitler.rejectedAFlag(out: "", err: "Error: unknown option '--settings'"))
        XCTAssertFalse(ClaudeTitler.rejectedAFlag(out: envelope("Unknown Option Dialog | error"), err: ""),
                       "an answer is never a refusal, whatever it says")
        XCTAssertFalse(ClaudeTitler.rejectedAFlag(out: "Failed to authenticate: OAuth session expired", err: ""))
    }

    func testNothingPrintedIsEmpty() {
        XCTAssertThrowsError(try ClaudeTitler.answer(out: "", err: "", status: 1)) { error in
            guard case ClaudeTitler.CLIError.empty = error else { return XCTFail("\(error)") }
        }
    }
}
