import Testing
import Foundation
@testable import True

@Suite struct BrainErrorTests {
    private func body(_ type: String, _ msg: String) -> Data {
        Data(#"{"type":"error","error":{"type":"\#(type)","message":"\#(msg)"}}"#.utf8)
    }
    @Test func creditsExhausted() {
        let b = body("invalid_request_error", "Your credit balance is too low to access the Anthropic API.")
        #expect(BrainError.from(status: 400, body: b) == .creditsExhausted)
    }
    @Test func keyRejected() {
        #expect(BrainError.from(status: 401, body: body("authentication_error", "invalid x-api-key")) == .keyRejected)
        #expect(BrainError.from(status: 403, body: body("authentication_error", "nope")) == .keyRejected)
    }
    @Test func otherIsHttp() {
        #expect(BrainError.from(status: 400, body: body("invalid_request_error", "bad field")) == .http(400))
        #expect(BrainError.from(status: 529, body: Data()) == .http(529))
        #expect(BrainError.from(status: 400, body: Data("garbage".utf8)) == .http(400))
    }
    @Test func voiceKindFromFailureLabel() {
        #expect(BrainFailureVoice.kind(forFailure: "\(BrainError.creditsExhausted)") == .credits)
        #expect(BrainFailureVoice.kind(forFailure: "\(BrainError.keyRejected)") == .key)
        #expect(BrainFailureVoice.kind(forFailure: "\(BrainError.http(500))") == nil)
    }
    @Test func voiceRateLimit() {
        var v = BrainFailureVoice(); let t = Date()
        let first = v.shouldSpeak(.credits, now: t)
        let again = v.shouldSpeak(.credits, now: t.addingTimeInterval(599))
        let otherKind = v.shouldSpeak(.key, now: t.addingTimeInterval(1))
        let later = v.shouldSpeak(.credits, now: t.addingTimeInterval(601))
        #expect(first); #expect(!again); #expect(otherKind); #expect(later)
    }
    @Test func doubleClickAction() {
        #expect(TitleBarAction.parse("Minimize") == .minimize)
        #expect(TitleBarAction.parse("None") == .none)
        #expect(TitleBarAction.parse("Maximize") == .zoom)
        #expect(TitleBarAction.parse(nil) == .zoom)
    }
}
