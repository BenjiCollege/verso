import AVFoundation
import Foundation
import OSLog
import Speech

/// Dictating a note.
///
/// Transcription is on-device only. Section 1 says no server, and
/// `SFSpeechRecognizer` will happily send audio to Apple's servers unless told
/// not to — `requiresOnDeviceRecognition` is the line that keeps that promise,
/// and if the device cannot do it locally the feature reports itself as
/// unavailable rather than quietly going online.
@MainActor
@Observable
final class SpeechTranscription {

    nonisolated static let logger = Logger(subsystem: "com.verso.notes", category: "speech")

    enum State: Equatable, Sendable {
        case idle
        case unavailable(String)
        case listening
        case finishing
    }

    private(set) var state: State = .idle
    /// Updated live while listening, so there is something to look at.
    private(set) var transcript = ""

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    var isListening: Bool { state == .listening }

    /// Whether to offer dictation at all.
    ///
    /// Section 7: hide unavailable affordances entirely. A microphone button
    /// that always fails is worse than no microphone button.
    var isSupported: Bool {
        guard let recognizer = SFSpeechRecognizer() else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            state = .unavailable(String(localized: "Verso hasn't been given permission to use speech recognition."))
            return false
        }

        let microphone = await AVAudioApplication.requestRecordPermission()
        guard microphone else {
            state = .unavailable(String(localized: "Verso hasn't been given permission to use the microphone."))
            return false
        }
        return true
    }

    // MARK: - Listening

    func start() async {
        guard state != .listening else { return }
        transcript = ""

        guard await requestPermission() else { return }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            state = .unavailable(String(localized: "Speech recognition isn't available right now."))
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            // Refusing is the right answer: the alternative is sending the
            // user's voice to a server, which this app does not do.
            state = .unavailable(String(localized: "This device can't transcribe without sending audio to a server, so Verso won't. You can type instead."))
            return
        }

        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()
            state = .listening

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || result?.isFinal == true {
                        self.finish()
                    }
                }
            }
        } catch {
            Self.logger.error("Could not start listening: \(error.localizedDescription, privacy: .public)")
            state = .unavailable(error.localizedDescription)
            teardown()
        }
    }

    /// Stops listening and returns whatever was heard.
    @discardableResult
    func stop() -> String {
        guard state == .listening else { return transcript }
        state = .finishing
        request?.endAudio()
        teardown()
        state = .idle
        return transcript
    }

    private func finish() {
        teardown()
        if state != .idle { state = .idle }
    }

    private func teardown() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
