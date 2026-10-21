import Testing
import Foundation
@testable import True

// Nova is private: this file is stripped from the public export (Tests/TrueTests/Nova*.swift).
@Suite struct NovaTellChatFallbackTests {
    @Test func offlineTellFallsBackToAgentInbox() {
        #expect(NovaTell.fallbackChannel(for: "scout") == "@scout")
        #expect(ChatNaming.normalize(NovaTell.fallbackChannel(for: "scout")) != nil)
    }
}
