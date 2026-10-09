import Foundation
import Observation
import Speech
import AVFoundation

@MainActor @Observable
final class WardrobeSpeech {
    var transcript = ""
    private(set) var busy = false
    private(set) var recording = false
    private(set) var problem: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let audio = AVAudioEngine()
    @ObservationIgnored private var tapped = false
    @ObservationIgnored private var activeSession = false
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var timer: Task<Void, Never>?

    static func reviewed(_ transcript: String, baseline: String, current: String, owner: Bool, byteLimit: Int) throws -> String {
        guard owner, baseline == current else { throw WardrobeWriteError("The input or account changed. Record a fresh description.") }
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, transcript.utf8.count <= byteLimit else { throw WardrobeWriteError("Review a shorter, nonempty transcript before using it.") }
        return transcript
    }
    func start(byteLimit: Int, stillOwner: @escaping () -> Bool) async {
        stop(clear: true)
        let ticket = generation
        guard stillOwner(), let recognizer = SFSpeechRecognizer(locale: .current), recognizer.supportsOnDeviceRecognition else {
            problem = "On-device speech is unavailable for this language. Type the description instead."; return
        }
        busy = true
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard ticket == generation, stillOwner(), !Task.isCancelled else { return }
        guard authorization == .authorized else { stop(); problem = "Speech permission is needed to record. You can type instead."; return }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard ticket == generation, stillOwner(), !Task.isCancelled else { return }
        guard microphone, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            stop(); problem = "Microphone or on-device speech is unavailable. Type the description instead."; return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true); activeSession = true
            let input = audio.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw WardrobeWriteError("No microphone input is available.") }
            let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
            self.recognizer = recognizer
            bufferRequest.requiresOnDeviceRecognition = true
            bufferRequest.shouldReportPartialResults = true
            request = bufferRequest
            recognition = recognizer.recognitionTask(with: bufferRequest) { [weak self] result, error in
                let words = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true
                let failure = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, ticket == self.generation else { return }
                    guard stillOwner() else { self.stop(clear: true); return }
                    if let words {
                        guard words.utf8.count <= byteLimit else { self.stop(); self.problem = "Recording reached the text limit. Review the captured text or type a shorter description."; return }
                        self.transcript = words
                    }
                    if finished || failure != nil {
                        self.stop()
                        if let failure { self.problem = "On-device recognition stopped: \(failure). Review any captured text or type instead." }
                    }
                }
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in bufferRequest.append(buffer) }
            tapped = true
            audio.prepare(); try audio.start(); recording = true
            timer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, ticket == self.generation else { return }
                self.stop(); self.problem = "Recording stopped after 30 seconds. Review the transcript before using it."
            }
        } catch { stop(); problem = "Could not start on-device recording. \(error.localizedDescription) Type instead." }
    }
    func stop(clear: Bool = false) {
        generation += 1; timer?.cancel(); timer = nil
        audio.stop()
        if tapped { audio.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil; recognizer = nil
        if activeSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); activeSession = false }
        busy = false; recording = false
        if clear { transcript = ""; problem = nil }
    }
}
