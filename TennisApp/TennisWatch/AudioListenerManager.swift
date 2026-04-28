import Foundation
import AVFoundation

/// Streams microphone audio to xAI's realtime voice agent and emits normalized
/// transcriptions for ScoreManager to act on. Replaces the previous
/// Whisper (Groq) + Claude HTTP pipeline with a single WebSocket round-trip.
///
/// The class name is preserved for compatibility with the existing Xcode
/// project file references; the implementation is now xAI-based.
@MainActor
class AudioListenerManager: ObservableObject {

    @Published var isListening = false
    @Published var isDetectingSpeech = false
    @Published var isProcessing = false
    @Published var lastError: String = ""
    @Published var lastResult: String = ""

    /// Emitted when xAI returns a normalized line for a single utterance.
    var onTranscription: ((String) -> Void)?

    // MARK: - xAI Configuration
    //
    // The xAI API key is resolved at runtime from one of two sources, in order:
    //
    //   1. Process environment: XAI_API_KEY
    //      Set once globally so Xcode and child processes inherit it:
    //
    //        launchctl setenv XAI_API_KEY xai-...
    //
    //      (Then quit and reopen Xcode.) No files to manage; nothing to leak.
    //
    //   2. Bundle resource: a `Secrets.plist` file added to the app target
    //      with a top-level string entry under the key `XAI_API_KEY`.
    //      The file is gitignored — keep it that way.
    //
    // Do NOT put the key in a *shared* Xcode scheme — those XML files live
    // under xcshareddata/ and are committed to git. Get a key at
    // https://console.x.ai
    static var apiKey: String {
        if let env = ProcessInfo.processInfo.environment["XAI_API_KEY"], !env.isEmpty {
            return env
        }
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let plist = NSDictionary(contentsOf: url),
           let key = plist["XAI_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return ""
    }
    static let endpoint = URL(string: "wss://api.x.ai/v1/realtime?model=grok-voice-think-fast-1.0")!

    private static let targetSampleRate: Double = 24000

    /// Instructions tell the model to output a single normalized line per
    /// utterance — either a tennis score in `A-B` form, a known command
    /// keyword, or the literal transcription. ScoreManager already knows how
    /// to consume each of these forms.
    private static let systemInstructions = """
    You are a transcription assistant for a tennis scoring watch app. The user speaks in Turkish or English while playing. Convert each utterance into ONE LINE of normalized output, then stop.

    Output exactly ONE of these forms:
    1. Tennis score "A-B" where each side is one of 0, 15, 30, 40, AD.
       Examples: "fifteen love" -> "15-0"; "on beş sıfır" -> "15-0"; "deuce" or "kırk kırk" -> "40-40"; "advantage" / "avantaj" -> "AD-40"; "thirty all" -> "30-30"; "15'er" / "on beşer" -> "15-15".
    2. "GAME" — when a game is awarded (oyun, game, fifty, elli, "50").
    3. "kort değiştir" — change court / change sides.
    4. "maç bitti" — match over (game over, match over, bitti).
    5. "tiebreak" — start tiebreak (tiebreak, taybrek).
    6. "match tiebreak" — super tiebreak (super tiebreak, süper taybrek, maç taybrek).
    7. "out", "out a" or "out b" — out call.
    8. "setler X-Y" where X and Y are integers 0–5 — direct set score command.
    9. Otherwise: output the literal Turkish/English transcription as spoken (used for player names and unknown commands).

    Common mishearings to correct: "kök" / "kirk" / "kurk" -> "kırk" (40); "om beş" -> "on beş"; "otus" -> "otuz"; "sifir" -> "sıfır".

    Do NOT add explanations, quotes, prefixes, or punctuation other than the hyphen. Output the single normalized line and nothing else.
    """

    // Audio path: tap thread accesses these — declared nonisolated(unsafe) so the
    // converter can run on the audio render thread without re-hopping to MainActor.
    // Lifetime is bounded by start/stopListening which run on MainActor.
    nonisolated(unsafe) private var converter: AVAudioConverter?
    nonisolated(unsafe) private var converterOutputFormat: AVAudioFormat?
    nonisolated(unsafe) private var liveSocket: URLSessionWebSocketTask?

    private var audioEngine: AVAudioEngine?
    private var urlSession: URLSession?
    private var responseBuffer = ""
    private var reconnectAttempts = 0
    private var pingTask: Task<Void, Never>?

    private let sendQueue = DispatchQueue(label: "xai.voice.send")

    // MARK: - Start / Stop

    func startListening() {
        guard !isListening else { return }
        guard !Self.apiKey.isEmpty else {
            lastError = "XAI_API_KEY not set (see AudioListenerManager.apiKey docs)"
            lastResult = lastError
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default, options: [])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastResult = "Mic: \(error.localizedDescription)"
            return
        }

        isListening = true
        lastError = ""
        lastResult = ""
        connect()
        startEngine()
    }

    func stopListening() {
        isListening = false
        teardownEngine()
        teardownSocket()
        pingTask?.cancel()
        pingTask = nil
        isDetectingSpeech = false
        isProcessing = false
        responseBuffer = ""
        reconnectAttempts = 0
    }

    private func teardownEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        converter = nil
        converterOutputFormat = nil
    }

    private func teardownSocket() {
        liveSocket?.cancel(with: .normalClosure, reason: nil)
        liveSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    // MARK: - WebSocket

    private func connect() {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 30
        request.setValue("Bearer \(Self.apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        urlSession = session
        let task = session.webSocketTask(with: request)
        liveSocket = task
        task.resume()

        sendSessionUpdate()
        receiveLoop()
        startPingLoop()
    }

    private func sendSessionUpdate() {
        sendEvent([
            "type": "session.update",
            "session": [
                "instructions": Self.systemInstructions,
                "modalities": ["text"],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.6,
                    "silence_duration_ms": 500,
                    "prefix_padding_ms": 300
                ],
                "audio": [
                    "input": ["format": ["type": "audio/pcm", "rate": Int(Self.targetSampleRate)]],
                    "output": ["format": ["type": "audio/pcm", "rate": Int(Self.targetSampleRate)]]
                ]
            ]
        ])
    }

    nonisolated private func sendEvent(_ payload: [String: Any]) {
        sendQueue.async { [weak self] in
            guard let self = self,
                  let task = self.liveSocket,
                  let data = try? JSONSerialization.data(withJSONObject: payload),
                  let str = String(data: data, encoding: .utf8) else { return }
            task.send(.string(str)) { error in
                if let error = error {
                    print("xAI send error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func receiveLoop() {
        guard let task = liveSocket else { return }
        task.receive { [weak self] result in
            switch result {
            case .failure(let error):
                Task { @MainActor [weak self] in
                    self?.handleSocketFailure(error)
                }
            case .success(let message):
                let text: String?
                switch message {
                case .string(let s): text = s
                case .data(let d): text = String(data: d, encoding: .utf8)
                @unknown default: text = nil
                }
                Task { @MainActor [weak self] in
                    if let text = text {
                        self?.handleEvent(text)
                    }
                    self?.receiveLoop()
                }
            }
        }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.liveSocket?.sendPing { _ in }
                }
            }
        }
    }

    private func handleSocketFailure(_ error: Error) {
        lastError = error.localizedDescription
        guard isListening else { return }
        teardownSocket()
        let attempt = min(reconnectAttempts, 5)
        reconnectAttempts += 1
        let delaySeconds = min(30, Int(pow(2.0, Double(attempt))))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            await MainActor.run {
                guard let self = self, self.isListening else { return }
                self.connect()
            }
        }
    }

    private func handleEvent(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "session.updated":
            reconnectAttempts = 0
        case "input_audio_buffer.speech_started":
            isDetectingSpeech = true
        case "input_audio_buffer.speech_stopped":
            isDetectingSpeech = false
            isProcessing = true
        case "response.text.delta", "response.output_text.delta":
            if let delta = json["delta"] as? String {
                responseBuffer += delta
            }
        case "response.done":
            let text = responseBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            responseBuffer = ""
            isProcessing = false
            if text.isEmpty {
                lastResult = "(sessizlik)"
            } else {
                lastResult = "🎤 \"\(text)\""
                onTranscription?(text)
            }
        case "error":
            if let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String {
                lastError = msg
            }
        default:
            break
        }
    }

    // MARK: - Audio Capture & Conversion

    private func startEngine() {
        let engine = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            lastResult = "Mic: no input available"
            return
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            lastResult = "Audio: cannot build 24kHz format"
            return
        }
        converterOutputFormat = outputFormat
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleTap(buffer)
        }

        do {
            try engine.start()
        } catch {
            lastResult = "Mic: \(error.localizedDescription)"
        }
    }

    nonisolated private func handleTap(_ buffer: AVAudioPCMBuffer) {
        guard let converter = converter,
              let outputFormat = converterOutputFormat,
              liveSocket != nil else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outCapacity) else { return }

        var error: NSError?
        var fed = false
        converter.convert(to: outputBuffer, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if error != nil { return }

        let frames = Int(outputBuffer.frameLength)
        guard frames > 0, let int16Channel = outputBuffer.int16ChannelData else { return }

        let pcmData = Data(bytes: int16Channel[0], count: frames * MemoryLayout<Int16>.size)
        sendEvent([
            "type": "input_audio_buffer.append",
            "audio": pcmData.base64EncodedString()
        ])
    }
}
