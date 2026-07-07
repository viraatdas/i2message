import Foundation
import Vision

/// Produces a short, human-readable description of an image attachment.
/// Implementations must stay fully local: no image bytes or derived text may
/// leave the machine, matching the app's privacy model.
public protocol ImageDescribing: Sendable {
    func describe(_ attachment: MessageAttachment) async -> String?
}

/// Local image understanding backed by Apple's on-device Vision framework.
/// Combines scene/object classification with fast text recognition (OCR) so
/// screenshots and photos both get useful summaries.
public actor VisionImageDescriptionService: ImageDescribing {
    private var cache: [AttachmentID: String] = [:]
    private var knownEmpty: Set<AttachmentID> = []

    public init() {}

    public func describe(_ attachment: MessageAttachment) async -> String? {
        guard attachment.kind == .image else {
            return nil
        }
        if let cached = cache[attachment.id] {
            return cached
        }
        guard !knownEmpty.contains(attachment.id),
              let fileURL = attachment.fileURL,
              FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return nil
        }

        let description = Self.describeImage(at: fileURL)
        if let description {
            cache[attachment.id] = description
        } else {
            knownEmpty.insert(attachment.id)
        }
        return description
    }

    private static func describeImage(at fileURL: URL) -> String? {
        let handler = VNImageRequestHandler(url: fileURL, options: [:])
        let classification = VNClassifyImageRequest()
        let textRecognition = VNRecognizeTextRequest()
        textRecognition.recognitionLevel = .fast
        textRecognition.usesLanguageCorrection = false

        do {
            try handler.perform([classification, textRecognition])
        } catch {
            return nil
        }

        let labels = (classification.results ?? [])
            .filter { $0.confidence >= 0.55 }
            .prefix(3)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }

        let recognizedText = (textRecognition.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if !labels.isEmpty {
            parts.append("Looks like \(labels.joined(separator: ", "))")
        }
        if !recognizedText.isEmpty {
            let clipped = recognizedText.count > 90
                ? String(recognizedText.prefix(90)) + "…"
                : recognizedText
            parts.append("Reads “\(clipped)”")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
