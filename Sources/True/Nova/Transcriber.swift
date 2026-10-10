import Foundation

/// A transcription backend. True v1 has exactly one: Apple's on-device SpeechAnalyzer (macOS 26).
protocol Transcriber: Sendable {
    func transcribe(samples: [Float], wav: URL?) async throws -> String
}
