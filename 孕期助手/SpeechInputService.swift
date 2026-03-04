import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class SpeechInputService: NSObject, ObservableObject {
    enum SpeechInputError: LocalizedError {
        case recognizerUnavailable
        case permissionDenied
        case audioEngineUnavailable
        case recognitionFailed

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "语音识别暂不可用，请稍后重试。"
            case .permissionDenied:
                return "未授予麦克风或语音识别权限。"
            case .audioEngineUnavailable:
                return "录音引擎不可用，请重试。"
            case .recognitionFailed:
                return "语音识别失败，请重试。"
            }
        }
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN")) ?? SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private(set) var isRecording = false

    func requestPermissions() async -> Bool {
        let speechGranted = await requestSpeechPermission()
        let micGranted = await requestMicrophonePermission()
        return speechGranted && micGranted
    }

    func startRecognition(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) async throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechInputError.recognizerUnavailable
        }

        let granted = await requestPermissions()
        guard granted else {
            throw SpeechInputError.permissionDenied
        }

        if isRecording {
            stopRecognition()
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let inputNode = audioEngine.inputNode

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    onPartial(text)
                }
                if result.isFinal {
                    self.stopRecognition()
                    if !text.isEmpty {
                        onFinal(text)
                    }
                }
            }
            if error != nil {
                self.stopRecognition()
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stopRecognition() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
