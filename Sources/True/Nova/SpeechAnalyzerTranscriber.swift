import Foundation
@preconcurrency import AVFoundation
import Speech

/// Apple's macOS 26 speech stack (`SpeechAnalyzer` + `SpeechTranscriber`) as an opt-in backend.
/// The API is built for streaming — an AsyncSequence of results off a live input — but here it
/// runs the same batch contract as every other `Transcriber`: whole take in, final text out.
/// That's deliberate: this is the roadmap's #4 spike made selectable so it can be compared against
/// whisper.cpp on real dictations; the streaming ears grow from this exact call surface later.
/// whisper.cpp stays the default.
struct SpeechAnalyzerTranscriber: Transcriber {
    /// ISO language hint from config ("" = the system locale).
    let language: String

    func transcribe(samples: [Float], wav: URL?) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw VoiceError.unavailable("Apple's macOS 26 speech engine")
        }
        guard !samples.isEmpty else { throw VoiceError.noAudio }
        let text = try await SpeechAnalyzerCore.run(samples: samples, language: language)
        if text.isEmpty { throw VoiceError.empty }
        return text
    }
}

// The deployment target is macOS 14; everything that names a SpeechAnalyzer type lives behind
// this gate so the file compiles — and the symbols simply don't load — on an older OS.
@available(macOS 26.0, *)
private enum SpeechAnalyzerCore {

    /// One batch pass: ensure the locale's on-device model, feed the take as a single buffer,
    /// finalize, and assemble the final results in order.
    static func run(samples: [Float], language: String) async throws -> String {
        guard let locale = await resolveLocale(language) else {
            throw VoiceError.unavailable("Apple transcription for “\(language.isEmpty ? Locale.current.identifier : language)”")
        }

        // No volatile results requested — batch wants finals only, so the results stream is
        // exactly the finished transcript in segment order.
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        try await ensureAssets(for: transcriber, locale: locale)

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              let buffer = pcmBuffer(samples, convertedTo: analyzerFormat) else {
            throw VoiceError.cli("couldn't prepare audio for Apple transcription")
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Subscribe BEFORE the analyzer runs — the results stream ends when analysis finishes,
        // and a late subscriber has no replay guarantee.
        let collector = Task {
            var pieces: [String] = []
            for try await result in transcriber.results where result.isFinal {
                let piece = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { pieces.append(piece) }
            }
            return pieces.joined(separator: " ")
        }

        do {
            let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
            inputBuilder.yield(AnalyzerInput(buffer: buffer))
            inputBuilder.finish()
            try await analyzer.start(inputSequence: inputSequence)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            throw error
        }

        return try await collector.value
    }

    /// Map the config's language hint onto a locale the engine actually supports. The supported
    /// list is region-qualified ("en-US"), while the hint is a bare ISO code ("en") or empty
    /// (= system language) — an exact bcp47 test alone rejects every bare hint, so fall back to
    /// same-language matching, preferring the user's own region.
    private static func resolveLocale(_ language: String) async -> Locale? {
        let supported = await SpeechTranscriber.supportedLocales
        let wanted = language.isEmpty ? Locale.current : Locale(identifier: language)
        if supported.contains(where: { $0.identifier(.bcp47) == wanted.identifier(.bcp47) }) { return wanted }
        guard let lang = wanted.language.languageCode?.identifier else { return nil }
        let sameLanguage = supported.filter { $0.language.languageCode?.identifier == lang }
        return sameLanguage.first { $0.region == Locale.current.region } ?? sameLanguage.first
    }

    /// The models are per-locale downloads managed by the OS. First use of a language pulls its
    /// asset once (which can take a moment); after that it's local forever — surfaced to the user
    /// in the lens copy, not silently.
    private static func ensureAssets(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let wanted = locale.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == wanted }) { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    /// Wrap the 16 kHz mono floats the recorder hands every backend into whatever format the
    /// analyzer asks for. Most of the time that IS 16 kHz mono Float32 and no conversion runs.
    private static func pcmBuffer(_ samples: [Float], convertedTo format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let src = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { p in
            inBuf.floatChannelData![0].update(from: p.baseAddress!, count: samples.count)
        }
        if format.commonFormat == .pcmFormatFloat32,
           format.sampleRate == 16_000, format.channelCount == 1 {
            return inBuf
        }

        guard let converter = AVAudioConverter(from: src, to: format) else { return nil }
        let capacity = AVAudioFrameCount(Double(samples.count) * format.sampleRate / 16_000 + 4096)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        // Same one-shot pull discipline as AudioResampler: serve the buffer exactly once.
        final class OneShot: @unchecked Sendable { var used = false }
        let oneShot = OneShot()
        var error: NSError?
        converter.convert(to: outBuf, error: &error) { _, status in
            if oneShot.used { status.pointee = .noDataNow; return nil }
            oneShot.used = true; status.pointee = .haveData; return inBuf
        }
        return error == nil ? outBuf : nil
    }
}
