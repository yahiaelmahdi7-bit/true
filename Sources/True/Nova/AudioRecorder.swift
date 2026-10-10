@preconcurrency import AVFoundation

/// Microphone capture on an `AVAudioEngine` tap. The tap fires on a real-time audio thread, so the
/// sample buffer + live level are guarded by a lock and this type is `@unchecked Sendable`; the
/// `@MainActor` engine only ever touches it through these methods. On `stop()` the raw mono samples
/// are resampled to 16 kHz (what Whisper/whisper.cpp/Parakeet expect) and written to a temp WAV.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sourceRate: Double = 48_000
    private var level: Float = 0
    private var running = false
    private var voiceProcessing = false
    /// Why echo cancellation could not be turned on, when it could not. Surfaced rather than
    /// swallowed: a silent failure here means every transcript quietly carries the room's audio
    /// while the setting still reads "on".
    private var lastAECError: String?

    /// Ask for microphone access, resolving to whether it's granted.
    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            }
        default: return false
        }
    }

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Begin capturing. Throws if the engine can't start (e.g. no input device).
    func start() throws {
        lock.lock(); samples.removeAll(keepingCapacity: true); level = 0; lock.unlock()

        let input = engine.inputNode

        // AEC (barge-in stage 1): Apple's voice processing subtracts the Mac's own speaker output
        // from the mic, so Nova can hear you over her own voice. Toggling it rebuilds the IO unit
        // and can change the input format, so it MUST happen before the tap is installed and before
        // the format is read. The persisted config (saved on every change) is the source of truth
        // here. Failure to enable is a degrade, not an error — the take still records, just
        // without cancellation.
        // True: AEC always on (Nova must hear you over her own voice); no config store in v1.
        let wantAEC = true
        var aecError: String?
        if input.isVoiceProcessingEnabled != wantAEC {
            // NOT `try?`. Swallowing this is how cancellation could be off for months while the
            // setting still said "on" and every transcript quietly carried the room. Still a
            // degrade rather than a fatal error — but a degrade somebody can SEE.
            do { try input.setVoiceProcessingEnabled(wantAEC) }
            catch { aecError = error.localizedDescription }
        }
        if input.isVoiceProcessingEnabled {
            // Ducking turns down OTHER apps while this unit is live. It was pinned to `.min`
            // because voice processing was believed to be up throughout hands-free listening —
            // the whole Mac going quiet reads as "Axon breaks my audio".
            //
            // It isn't up throughout. The wake word runs its OWN `AVAudioEngine` with no voice
            // processing (WakeWord.swift), so this unit is live only during an actual take.
            // Ducking therefore lasts the few seconds you are genuinely talking to Nova — which
            // is precisely when a film playing on the same Mac must not be in the microphone.
            // Whisper cannot tell your voice from an actor's, so whatever is audible in the room
            // lands in the transcript beside what you said.
            //
            // Advanced (adaptive) ducking stays off: it pumps audibly as it tracks the signal.
            //
            // Arming the duck is only half the contract — `stop()` MUST release it. See
            // `releaseDucking()`: the level is a property of an IO unit that outlives the take,
            // so "duck to `.max`" is permanent until something says otherwise.
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(
                enableAdvancedDucking: false,
                duckingLevel: .min)
        }
        lock.lock()
        voiceProcessing = input.isVoiceProcessingEnabled
        lastAECError = aecError
        lock.unlock()

        // Same guard, same reason as the wake word's (see AudioSafety.swift): a 0 Hz format from an
        // input device that hasn't come back after sleep makes `installTap` raise an uncatchable
        // ObjC exception and abort the process. Here `start()` already throws, so the transient
        // case becomes an ordinary Swift error the caller can report and retry. Read AFTER the AEC
        // toggle — enabling voice processing rebuilds the IO unit and can change the format.
        guard let format = input.safeTapFormat() else {
            releaseDucking()   // a take that never began must not leave the Mac quiet
            throw AudioSetupError.inputNotReady
        }
        lock.lock(); sourceRate = format.sampleRate; lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.absorb(buffer)
        }
        engine.prepare()
        do { try engine.start() }
        catch {
            releaseDucking()
            throw error
        }
        running = true
    }

    /// Put every other app's audio back to full volume.
    ///
    /// Ducking is configured on the voice-processing IO unit, and that unit OUTLIVES the take: it
    /// is instantiated the first time voice processing is enabled and then stays on
    /// `engine.inputNode` for the life of this recorder (`start()` only ever toggles voice
    /// processing when the *setting* changes, never per take). `engine.stop()` halts rendering; it
    /// does not hand other apps their volume back. So a `.max` set on the first take is permanent
    /// — every app but this one stays turned down for the rest of the session, which is loudest
    /// exactly when Nova replies: her own output is not ducked by her own unit, so she is all you
    /// hear while a browser video plays silently behind her.
    ///
    /// That is how "Axon breaks my audio" (fixed in eb80f0a by pinning `.min`) returned when
    /// ducking was raised to `.max` for the take (2ca415a). Both commits are right and neither is
    /// reverted here: `.max` still covers the take, so a film cannot land in the transcript, and
    /// the duck is released the moment the take ends, so the Mac is loud again the rest of the time
    /// — which is the contract `VoiceConfig.duckOtherAudio` already promised in writing.
    ///
    /// Called BEFORE `engine.stop()`, while the unit is still live to act on the change.
    private func releaseDucking() {
        let input = engine.inputNode
        guard input.isVoiceProcessingEnabled else { return }
        input.voiceProcessingOtherAudioDuckingConfiguration = .init(
            enableAdvancedDucking: false, duckingLevel: .min)
    }

    /// Real-time thread: copy channel 0 into the buffer and update the RMS level.
    private func absorb(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        let ptr = channels[0]
        var local = [Float](repeating: 0, count: n)
        var sum: Float = 0
        for i in 0..<n {
            let s = ptr[i]
            local[i] = s
            sum += s * s
        }
        let rms = (sum / Float(n)).squareRoot()
        lock.lock()
        samples.append(contentsOf: local)
        level = rms
        lock.unlock()
    }

    /// Current RMS level (0…~0.4 for speech), read by the meter timer on the main actor.
    /// Voice processing's documented AGC lands speech markedly quieter; compensate HERE — in the
    /// meter reading only, never the samples — so the bars and the silence-stop threshold behave
    /// the same with AEC on or off.
    func currentLevel() -> Float {
        lock.lock(); defer { lock.unlock() }
        return voiceProcessing ? min(level * 2.5, 1) : level
    }

    /// Stop and hand back 16 kHz mono samples plus a temp WAV url for the CLI backends.
    func stop() -> (samples: [Float], wav: URL?, seconds: Double) {
        guard running else { return ([], nil, 0) }
        releaseDucking()   // before engine.stop() — the unit must still be live to act on it
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // HAND THE MICROPHONE BACK. Voice processing is an audio unit that claims the input
        // device, and `engine.stop()` does not release it — the unit outlives the take (see
        // `releaseDucking`). While it is alive, every OTHER engine on the same device gets no
        // input at all: the wake-word listener's watchdog measured exactly that — a fresh engine
        // after each take, "no audio buffers in 4s", rebuild, repeat, forever. That was "Hey Nova
        // works once per launch". `start()` re-enables it before the next take's tap goes in,
        // so takes keep their echo cancellation; the ~100 ms it costs to rebuild the unit lands
        // at take start, where the ack line already covers it.
        if engine.inputNode.isVoiceProcessingEnabled {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        running = false

        lock.lock(); let raw = samples; let rate = sourceRate; level = 0; lock.unlock()
        let seconds = rate > 0 ? Double(raw.count) / rate : 0
        // Peak-normalise before the model sees it. Voice processing's AGC and a speaker a metre
        // from the laptop both land speech well under the level whisper was trained on, and a
        // quiet clip is where names and short words go first. Only quiet-but-real audio is lifted:
        // below the floor it is room tone (amplifying that manufactures hallucinations), above
        // the ceiling it is already fine.
        let mono16k = AudioLevel.normalized(AudioResampler.to16kMono(raw, sourceRate: rate))
        let wav = WavWriter.write(mono16k, sampleRate: 16_000)
        return (mono16k, wav, seconds)
    }
}

// MARK: - Resampling

/// Sample-rate conversion to 16 kHz mono via `AVAudioConverter` (proper anti-aliasing, unlike a
/// naive decimation). Input is already channel-0 mono at the hardware rate.
enum AudioResampler {
    static func to16kMono(_ input: [Float], sourceRate: Double) -> [Float] {
        guard !input.isEmpty else { return [] }
        guard sourceRate != 16_000 else { return input }
        guard sourceRate > 0,
              let src = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false),
              let dst = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: src, to: dst),
              let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(input.count)) else {
            return input
        }
        inBuf.frameLength = AVAudioFrameCount(input.count)
        input.withUnsafeBufferPointer { p in
            inBuf.floatChannelData![0].update(from: p.baseAddress!, count: input.count)
        }

        let ratio = 16_000 / sourceRate
        let capacity = AVAudioFrameCount(Double(input.count) * ratio + 4096)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: capacity) else { return input }

        // The pull block is typed @Sendable; a boxed flag serves it the buffer exactly once.
        final class OneShot: @unchecked Sendable { var used = false }
        let oneShot = OneShot()
        var error: NSError?
        converter.convert(to: outBuf, error: &error) { _, status in
            if oneShot.used { status.pointee = .noDataNow; return nil }
            oneShot.used = true; status.pointee = .haveData; return inBuf
        }
        if error != nil { return input }

        let n = Int(outBuf.frameLength)
        let out = outBuf.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: out, count: n))
    }
}

// MARK: - WAV writing

/// Writes 16-bit PCM mono WAV (little-endian, which Apple silicon is natively) to a temp file.
enum WavWriter {
    static func write(_ samples: [Float], sampleRate: Int) -> URL? {
        guard !samples.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("axon-voice-\(UUID().uuidString).wav")

        let channels = 1, bits = 16
        let byteRate = sampleRate * channels * bits / 8
        let blockAlign = channels * bits / 8
        let dataBytes = samples.count * 2

        var data = Data(capacity: 44 + dataBytes)
        func put<T>(_ value: T) { var v = value; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        put(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        put(UInt32(16))                 // PCM header size
        put(UInt16(1))                  // PCM format
        put(UInt16(channels))
        put(UInt32(sampleRate))
        put(UInt32(byteRate))
        put(UInt16(blockAlign))
        put(UInt16(bits))
        data.append(contentsOf: Array("data".utf8))
        put(UInt32(dataBytes))
        for s in samples {
            let clamped = max(-1, min(1, s))
            put(Int16(clamped * 32_767))
        }

        do { try data.write(to: url); return url } catch { return nil }
    }
}


// MARK: - Level

enum AudioLevel {
    /// Scale a clip so its peak sits at `target`, when its peak is between `floor` (room tone —
    /// leave it) and `target` (already loud enough). Never attenuates.
    static func normalized(_ samples: [Float], target: Float = 0.85, floor: Float = 0.02) -> [Float] {
        guard let peak = samples.map({ abs($0) }).max(), peak > floor, peak < target else { return samples }
        let gain = target / peak
        return samples.map { max(-1, min(1, $0 * gain)) }
    }
}
