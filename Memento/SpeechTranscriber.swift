import Foundation
import AVFoundation
import Speech
import Observation

/// Live speech-to-text using Apple's on-device speech recognition.
/// Powers both note dictation and Smart Capture. Recognition runs in
/// segments that restart automatically, so long conversations keep
/// transcribing past the usual one-utterance limit.
@Observable
final class SpeechTranscriber {
    var transcript = ""
    var isRecording = false
    var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finalizedText = ""
    private var consecutiveErrors = 0

    // MARK: - Permissions

    static func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Control

    @MainActor
    func start() async {
        errorMessage = nil
        transcript = ""
        finalizedText = ""
        consecutiveErrors = 0

        guard await Self.requestPermissions() else {
            errorMessage = "Allow microphone and speech recognition access for Memento in Settings."
            return
        }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        self.recognizer = recognizer

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }

        isRecording = true
        startRecognitionSegment()
    }

    @MainActor
    func stop() {
        guard isRecording || audioEngine.isRunning else { return }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Recognition segments

    @MainActor
    private func startRecognitionSegment() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep the audio on the phone when the device supports it — more
        // private, and on-device recognition allows long recordings.
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.process(result: result, error: error)
            }
        }
    }

    @MainActor
    private func process(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            consecutiveErrors = 0
            let partial = result.bestTranscription.formattedString
            transcript = finalizedText + partial
            if result.isFinal {
                finalizedText = transcript.isEmpty ? "" : transcript + " "
                if isRecording { startRecognitionSegment() }
            }
        }

        if error != nil, isRecording {
            consecutiveErrors += 1
            finalizedText = transcript.isEmpty ? "" : transcript + " "
            if consecutiveErrors < 3 {
                startRecognitionSegment()
            } else {
                stop()
                errorMessage = "Speech recognition stopped unexpectedly. Your transcript so far was kept."
            }
        }
    }
}
