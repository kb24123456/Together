import UIKit
import Vision

enum OCRTextRecognitionError: LocalizedError {
    case missingCGImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .missingCGImage:
            "无法读取图片内容。"
        case .noTextFound:
            "没有识别到可导入的文字。"
        }
    }
}

actor OCRTextRecognizer {
    func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRTextRecognitionError.missingCGImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let lines = observations.compactMap { observation in
                        observation.topCandidates(1).first?.string
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .filter { $0.isEmpty == false }

                    let text = lines.joined(separator: "\n")
                    if text.isEmpty {
                        continuation.resume(throwing: OCRTextRecognitionError.noTextFound)
                    } else {
                        continuation.resume(returning: text)
                    }
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

                let handler = VNImageRequestHandler(
                    cgImage: cgImage,
                    orientation: CGImagePropertyOrientation(image.imageOrientation),
                    options: [:]
                )

                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
