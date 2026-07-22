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
    // Bumped by every start() and stop(). start() re-checks it after its
    // permission await: a stop (composer dismissed mid-prompt) or a second
    // start (double-click) that arrived during the wait aborts the stale
    // start before it can hot-mic an empty screen or double-tap the input.
    private var startGeneration = 0
    // True while this transcriber holds the shared audio session active
    // (ducking other apps' audio). Tracked so both stop() and start()'s
    // failure paths can release the session exactly once, whichever runs.
    private var sessionActive = false

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
        startGeneration += 1
        let generation = startGeneration
        errorMessage = nil
        transcript = ""
        finalizedText = ""
        consecutiveErrors = 0

        guard await Self.requestPermissions() else {
            errorMessage = "Allow microphone and speech recognition access for Memento in Settings."
            return
        }
        // The permission prompt can outlive the composer (or a second tap
        // can supersede this start) — never start the engine for a request
        // nobody is waiting on.
        guard generation == startGeneration else { return }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        self.recognizer = recognizer

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            sessionActive = true

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            // On Macs with no input device (Mac mini/Studio/Pro without a
            // mic) this format comes back 0 Hz / 0 channels, and installTap
            // raises an Objective-C exception that do/catch can't catch —
            // the app would abort. Permissions don't guard this: macOS
            // grants mic access independently of whether a mic exists.
            guard format.sampleRate > 0, format.channelCount > 0 else {
                errorMessage = "No microphone is available on this device — connect one and try again."
                deactivateSession()
                return
            }
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            // The session is already active (still ducking other apps) when
            // the engine is what threw — release it here: isRecording never
            // became true, so nothing else would.
            audioEngine.inputNode.removeTap(onBus: 0)
            deactivateSession()
            return
        }

        isRecording = true
        startRecognitionSegment()
    }

    @MainActor
    func stop() {
        // Always invalidate a pending start, even when nothing is running
        // yet — the guard below must not swallow that.
        startGeneration += 1
        guard isRecording || audioEngine.isRunning || sessionActive else { return }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        deactivateSession()
    }

    /// Releases the shared audio session if this transcriber activated it.
    /// Idempotent — safe from any cleanup path, releases at most once.
    @MainActor
    private func deactivateSession() {
        guard sessionActive else { return }
        sessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Recognition segments

    @MainActor
    private func startRecognitionSegment() {
        // Retire the previous segment explicitly — its callbacks are
        // already ignored (request-identity guard below), but the task
        // shouldn't keep transcribing a request nothing reads.
        task?.cancel()
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
                // A task can deliver its final result in one callback and
                // its terminal error in a later one; once a new segment has
                // replaced this request, that late error must not finalize
                // the new segment's partial and spawn a duplicate task on
                // top of it — two live tasks alternate-writing `transcript`
                // and garble the note.
                guard let self, self.request === request else { return }
                self.process(result: result, error: error)
            }
        }
    }

    @MainActor
    private func process(result: SFSpeechRecognitionResult?, error: Error?) {
        // A final result and an error can arrive in the same callback (e.g.
        // at the ~1 minute recognition limit). Track whether the result
        // branch already started the next segment so the error branch below
        // doesn't start a second one on top of it, orphaning a task.
        var alreadyRestarted = false

        if let result {
            consecutiveErrors = 0
            let partial = result.bestTranscription.formattedString
            transcript = finalizedText + partial
            if result.isFinal {
                finalizedText = transcript.isEmpty ? "" : transcript + " "
                if isRecording {
                    startRecognitionSegment()
                    alreadyRestarted = true
                }
            }
        }

        if error != nil, isRecording, !alreadyRestarted {
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
