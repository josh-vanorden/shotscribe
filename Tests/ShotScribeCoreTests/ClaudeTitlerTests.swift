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

    func testNothingPrintedIsEmpty() {
        XCTAssertThrowsError(try ClaudeTitler.answer(out: "", err: "", status: 1)) { error in
            guard case ClaudeTitler.CLIError.empty = error else { return XCTFail("\(error)") }
        }
    }
}
