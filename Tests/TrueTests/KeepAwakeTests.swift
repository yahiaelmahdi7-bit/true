import Testing
import Foundation
@testable import True

@Suite struct KeepAwakeTests {
    /// The assertion is real: `pmset -g assertions` lists our reason string while held, not after.
    @Test @MainActor func holdRegistersWithPowerManager() throws {
        let k = KeepAwake()
        k.hold()
        #expect(k.held)
        #expect(assertions().contains("True is frontmost"))
        k.release()
        #expect(!k.held)
        #expect(!assertions().contains("True is frontmost"))
        k.release()   // double release is a no-op, never a double-free
    }

    private func assertions() -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "assertions"]; let out = Pipe(); p.standardOutput = out
        try? p.run(); p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
