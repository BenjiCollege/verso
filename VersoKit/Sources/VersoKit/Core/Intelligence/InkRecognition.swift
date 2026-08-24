import Foundation
import PencilKit
import UIKit

/// Reading handwriting.
///
/// A drawing used to contribute the single word "Sketch" to search, which meant
/// that in an app built around writing on a page, the writing was the one thing
/// that could not be found. Worse than absent: searching for "sketch" surfaced
/// every handwritten note, and searching for a word actually on the page
/// surfaced none of them.
///
/// This turns a `PKDrawing` into whatever words are in it. The text is a search
/// key and nothing more — it is never shown as though the user had typed it,
/// because recognition is a guess and the ink is the record.
enum InkRecognition {

    /// Longest edge of the rasterised drawing handed to Vision.
    ///
    /// Recognition wants resolution and a full page of ink at 2× is larger than
    /// it needs. Capping keeps a long note from rendering a bitmap measured in
    /// tens of megabytes on the way to reading six words.
    private static let renderLimit: CGFloat = 2_000

    /// The words in a drawing, or an empty string if there are none to find.
    ///
    /// Never throws. Handwriting recognition failing is not an error the user
    /// did anything about — it means this drawing is a diagram, or a scribble,
    /// or genuinely illegible, and all three are ordinary. The caller keeps
    /// whatever it had.
    static func text(in drawing: PKDrawing) async -> String {
        guard let image = highContrastImage(of: drawing) else { return "" }
        guard let lines = try? await TextRecognition.lines(in: image, correcting: true) else { return "" }
        return lines.joined(separator: "\n")
    }

    /// The drawing as black ink on white paper, whatever colour it was drawn in.
    ///
    /// This matters more than it sounds. Ink follows the note's theme, so a page
    /// written on a dark stock is *light* ink — rendered onto white it would be
    /// very nearly invisible, and recognition would quietly return nothing at
    /// all for every note the user wrote at night.
    ///
    /// Rather than inspect stroke colours (and `PKDrawing` cannot be rebuilt
    /// from recoloured strokes on this SDK anyway), the ink is flattened with
    /// blend modes: `sourceAtop` repaints whatever was drawn in black while
    /// keeping its antialiasing, and `destinationOver` slides white in behind.
    /// The result is colour-independent by construction.
    private static func highContrastImage(of drawing: PKDrawing) -> UIImage? {
        let bounds = drawing.bounds
        guard bounds.width > 1, bounds.height > 1,
              bounds.width.isFinite, bounds.height.isFinite
        else { return nil }

        // A little margin. Vision is measurably worse at a glyph flush against
        // the edge of the image, and a drawing's bounds are exactly that.
        let padded = bounds.insetBy(dx: -16, dy: -16)
        let scale = min(renderLimit / max(padded.width, padded.height), 3)
        guard scale > 0 else { return nil }

        let ink = drawing.image(from: padded, scale: scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: ink.size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: ink.size)
            ink.draw(in: rect)

            context.cgContext.setBlendMode(.sourceAtop)
            UIColor.black.setFill()
            context.fill(rect)

            context.cgContext.setBlendMode(.destinationOver)
            UIColor.white.setFill()
            context.fill(rect)
        }
    }
}
