import Foundation
import UIKit
import Vision

/// Reading the words out of a picture.
///
/// A capability, not a feature: "what does this image say" is the same question
/// whether the picture is a receipt, a whiteboard or a page of a book, and
/// nothing here knows which it is. What the words *mean* is somebody else's
/// problem — `ReceiptReader` is one such somebody.
///
/// On-device, like everything else that reads what the user wrote. `Vision`
/// does this locally with no network at any point, which is the only way it
/// could exist in this app at all.
enum TextRecognition {

    enum RecognitionError: LocalizedError {
        case unreadableImage

        var errorDescription: String? {
            String(localized: "That image couldn't be read.")
        }
    }

    /// The lines of text in an image, in reading order.
    ///
    /// Lines rather than one joined string, because position carries meaning in
    /// anything printed: a receipt's total is on its own line, and joining
    /// first would destroy the only structure the paper had.
    static func lines(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { throw RecognitionError.unreadableImage }

        return try await withCheckedThrowingContinuation { continuation in
            // The request and the handler are built *inside* the closure on
            // purpose. Neither is `Sendable` — Vision's types predate strict
            // concurrency — so constructing them out here and capturing them
            // is the error Swift 6 is right to refuse. Built in place, they
            // are created and consumed on one thread and never cross.
            //
            // `CGImage` is the one thing that crosses, and needs no annotation
            // to do it — it is `Sendable` in this SDK, being immutable once
            // made.

            // Off the main actor. Recognition on a full-resolution scan takes
            // long enough to drop frames if it runs where the UI does.
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                // `.accurate` rather than `.fast`: a receipt is small, badly
                // printed and read once. The extra milliseconds are free at
                // this scale, and a misread total is worse than a slow one.
                request.recognitionLevel = .accurate
                // Printed receipts are not prose, and the corrector "fixes"
                // prices into words it knows. £4.50 becoming "450" once is
                // enough to turn this off.
                request.usesLanguageCorrection = false

                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let lines = (request.results ?? [])
                    // Vision ranks candidates by confidence; the first is the
                    // one it believes.
                    .compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                continuation.resume(returning: lines)
            }
        }
    }

    /// Every page's lines, concatenated in page order.
    static func lines(in images: [UIImage]) async throws -> [String] {
        var all: [String] = []
        for image in images {
            all.append(contentsOf: try await lines(in: image))
        }
        return all
    }
}
