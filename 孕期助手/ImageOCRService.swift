import Foundation
import UIKit
import Vision

enum ImageOCRService {
    enum OCRError: LocalizedError {
        case emptyResult
        case unsupportedImage

        var errorDescription: String? {
            switch self {
            case .emptyResult:
                return "未识别到可读文本，请重试或手动输入。"
            case .unsupportedImage:
                return "图片格式不支持，建议重新拍照。"
            }
        }
    }

    static func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.unsupportedImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }

                let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    continuation.resume(throwing: OCRError.emptyResult)
                } else {
                    continuation.resume(returning: text)
                }
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
