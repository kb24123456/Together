import AVFAudio
import AVFoundation
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class QuickCaptureSpeechRecognizer {
    enum State: Equatable {
        case idle
        case authorizing
        case listening
        case unavailable
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    private(set) var errorMessage: String?
    private(set) var audioLevel: CGFloat = 0
    private(set) var isVoiceDetected = false

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var baseText = ""
    private var isStoppingIntentionally = false
    private var speechActivityHoldFrames = 0
    private var noiseFloor: Float = 0
    private var calibrationFramesRemaining = 0

    var isListening: Bool {
        state == .listening
    }

    var isActivelyCapturing: Bool {
        state == .authorizing || state == .listening
    }

    func beginAuthorization() {
        clearError()
        state = .authorizing
    }

    func syncDraftText(_ text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        baseText = normalizedText
        transcript = normalizedText
    }

    func resetDraft() {
        baseText = ""
        transcript = ""
        audioLevel = 0
        isVoiceDetected = false
        speechActivityHoldFrames = 0
        noiseFloor = 0
        calibrationFramesRemaining = 0
        errorMessage = nil
        if state != .listening && state != .authorizing {
            state = .idle
        }
    }

    func toggleListening(currentText: String) async {
        if isListening {
            stopListening()
        } else {
            await startListening(currentText: currentText)
        }
    }

    func stopListening() {
        isStoppingIntentionally = true
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .idle
        audioLevel = 0
        isVoiceDetected = false
        speechActivityHoldFrames = 0
        noiseFloor = 0
        calibrationFramesRemaining = 0
    }

    func clearError() {
        errorMessage = nil
    }

    private func startListening(currentText: String) async {
        isStoppingIntentionally = false

        guard await requestPermissions() else {
            state = .unavailable
            return
        }

        guard let recognizer = makeRecognizer(), recognizer.isAvailable else {
            errorMessage = "当前设备或语言环境暂不可用语音输入。"
            state = .unavailable
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak request, weak self] buffer, _ in
                request?.append(buffer)
                guard let self else { return }
                let analysis = self.analyzeVoiceLevel(from: buffer)
                Task { @MainActor in
                    guard self.state == .listening else { return }
                    if analysis.detectedSpeech {
                        self.speechActivityHoldFrames = 4
                    } else if self.speechActivityHoldFrames > 0 {
                        self.speechActivityHoldFrames -= 1
                    }

                    let hasDetectedSpeech = self.speechActivityHoldFrames > 0
                    self.isVoiceDetected = hasDetectedSpeech

                    if hasDetectedSpeech {
                        self.audioLevel = (self.audioLevel * 0.42) + (analysis.level * 0.58)
                    } else {
                        self.audioLevel = 0
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()

            baseText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            transcript = baseText
            speechRecognizer = recognizer
            recognitionRequest = request
            state = .listening
            audioLevel = 0
            isVoiceDetected = false
            speechActivityHoldFrames = 0
            noiseFloor = 0
            calibrationFramesRemaining = 10

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in
                    if let result {
                        let spokenText = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.transcript = self.merge(base: self.baseText, spoken: spokenText)

                        if result.isFinal {
                            self.stopListening()
                        }
                    }

                    if let error {
                        if self.shouldIgnore(error: error) {
                            self.finishCancelledSession()
                            return
                        }
                        self.errorMessage = error.localizedDescription
                        self.stopListening()
                        self.state = .unavailable
                    }
                }
            }
        } catch {
            errorMessage = "语音输入启动失败，请稍后再试。"
            stopListening()
            state = .unavailable
        }
    }

    private func makeRecognizer() -> SFSpeechRecognizer? {
        let preferredLocaleIdentifier = Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier
        return SFSpeechRecognizer(locale: Locale(identifier: preferredLocaleIdentifier))
            ?? SFSpeechRecognizer(locale: Locale.autoupdatingCurrent)
    }

    private func requestPermissions() async -> Bool {
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let microphoneGranted: Bool
        switch microphoneStatus {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            microphoneGranted = await requestMicrophoneAuthorization()
        case .denied, .restricted:
            microphoneGranted = false
        @unknown default:
            microphoneGranted = false
        }

        guard microphoneGranted else {
            errorMessage = "请允许 Together 使用麦克风。"
            return false
        }

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let speechGranted: Bool
        switch speechStatus {
        case .authorized:
            speechGranted = true
        case .notDetermined:
            speechGranted = await requestSpeechAuthorization()
        case .denied, .restricted:
            speechGranted = false
        @unknown default:
            speechGranted = false
        }

        guard speechGranted else {
            errorMessage = "请允许 Together 使用语音识别。"
            return false
        }

        return true
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func merge(base: String, spoken: String) -> String {
        guard !spoken.isEmpty else { return base }
        guard !base.isEmpty else { return spoken }

        let needsSpace =
            base.last?.isASCII == true &&
            spoken.first?.isASCII == true &&
            base.last?.isWhitespace == false

        return needsSpace ? "\(base) \(spoken)" : base + spoken
    }

    private func shouldIgnore(error: Error) -> Bool {
        if isStoppingIntentionally {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 203 {
            return true
        }

        let message = nsError.localizedDescription.lowercased()
        return message.contains("request was canceled") || message.contains("cancelled")
    }

    private func finishCancelledSession() {
        recognitionTask = nil
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        errorMessage = nil
        state = .idle
        audioLevel = 0
        isVoiceDetected = false
        speechActivityHoldFrames = 0
        noiseFloor = 0
        calibrationFramesRemaining = 0
        isStoppingIntentionally = false
    }

    private func analyzeVoiceLevel(from buffer: AVAudioPCMBuffer) -> (level: CGFloat, detectedSpeech: Bool) {
        guard let channelData = buffer.floatChannelData?[0] else { return (0, false) }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return (0, false) }

        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = channelData[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))

        if calibrationFramesRemaining > 0 {
            if noiseFloor == 0 {
                noiseFloor = rms
            } else {
                noiseFloor = (noiseFloor * 0.82) + (rms * 0.18)
            }
            calibrationFramesRemaining -= 1
            return (0, false)
        }

        let effectiveFloor = max(noiseFloor, 0.0012)
        let ratio = rms / effectiveFloor
        let exceededFloor = ratio > 2.6 && rms > effectiveFloor + 0.0035

        if !exceededFloor {
            noiseFloor = (noiseFloor * 0.94) + (rms * 0.06)
            return (0, false)
        }

        let normalized = min(max((ratio - 2.6) / 3.0, 0), 1)
        let emphasized = pow(normalized, 0.7)
        return (CGFloat(0.72 + emphasized * 0.28), true)
    }
}
