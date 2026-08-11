import CoreGraphics
import Foundation

/// A rectangle in page space, 0...1 on both axes.
///
/// Normalised so an annotation made on an iPad at one zoom level lands in the
/// same place on a phone at another. Storing points would tie every highlight
/// to the screen it was made on.
struct NormalisedRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// From a rect in a page's own coordinate space.
    init(_ rect: CGRect, in pageSize: CGSize) {
        guard pageSize.width > 0, pageSize.height > 0 else {
            self.init(x: 0, y: 0, width: 0, height: 0)
            return
        }
        self.init(
            x: Double(rect.minX / pageSize.width),
            y: Double(rect.minY / pageSize.height),
            width: Double(rect.width / pageSize.width),
            height: Double(rect.height / pageSize.height)
        )
    }

    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    var isMeaningful: Bool { width > 0.001 && height > 0.001 }
}

/// What a user has added on top of a document.
///
/// Two layers, per section 7: ink and highlights. Kept apart because they
/// export differently — a highlight is a PDF annotation another app can select
/// and delete, whereas ink is a path.
struct DocumentAnnotations: Codable, Hashable, Sendable {

    /// Named rather than stored as a colour, so annotations re-ink when the
    /// theme changes — the same rule the rest of the app follows.
    enum HighlightColor: String, Codable, CaseIterable, Sendable {
        case accent
        case gilt
        case ink

        var displayName: LocalizedStringResource {
            switch self {
            case .accent: "Accent"
            case .gilt: "Gilt"
            case .ink: "Ink"
            }
        }
    }

    struct Highlight: Codable, Hashable, Sendable, Identifiable {
        var id: UUID
        var page: Int
        /// One rect per line of text. A highlight across a paragraph break is
        /// several rectangles, not one that swallows the margin.
        var rects: [NormalisedRect]
        var color: HighlightColor
        /// What was highlighted, kept for search and export.
        var text: String

        init(
            id: UUID = UUID(),
            page: Int,
            rects: [NormalisedRect],
            color: HighlightColor = .accent,
            text: String = ""
        ) {
            self.id = id
            self.page = page
            self.rects = rects
            self.color = color
            self.text = text
        }
    }

    /// A `PKDrawing` archive per page, in normalised page space.
    struct PageInk: Codable, Hashable, Sendable, Identifiable {
        var id: Int { page }
        var page: Int
        var drawing: Data

        init(page: Int, drawing: Data) {
            self.page = page
            self.drawing = drawing
        }
    }

    /// An array rather than a dictionary keyed by page: `[Int: Data]` encodes
    /// to a flat alternating array in JSON, which is unreadable in a file
    /// somebody may one day have to inspect.
    var ink: [PageInk]
    var highlights: [Highlight]

    init(ink: [PageInk] = [], highlights: [Highlight] = []) {
        self.ink = ink
        self.highlights = highlights
    }

    var isEmpty: Bool { ink.allSatisfy(\.drawing.isEmpty) && highlights.isEmpty }

    func drawing(onPage page: Int) -> Data? {
        ink.first { $0.page == page }?.drawing
    }

    func highlights(onPage page: Int) -> [Highlight] {
        highlights.filter { $0.page == page }
    }

    mutating func setDrawing(_ data: Data, onPage page: Int) {
        if let index = ink.firstIndex(where: { $0.page == page }) {
            if data.isEmpty {
                ink.remove(at: index)
            } else {
                ink[index].drawing = data
            }
        } else if !data.isEmpty {
            ink.append(PageInk(page: page, drawing: data))
            ink.sort { $0.page < $1.page }
        }
    }

    mutating func add(_ highlight: Highlight) {
        guard highlight.rects.contains(where: \.isMeaningful) else { return }
        highlights.append(highlight)
    }

    mutating func removeHighlight(id: UUID) {
        highlights.removeAll { $0.id == id }
    }

    /// Every page carrying something, for the thumbnail strip's markers.
    var annotatedPages: Set<Int> {
        Set(ink.filter { !$0.drawing.isEmpty }.map(\.page) + highlights.map(\.page))
    }

    /// Highlighted passages in reading order, for export and for search.
    var highlightedText: [String] {
        highlights
            .sorted { ($0.page, $0.rects.first?.y ?? 0) < ($1.page, $1.rects.first?.y ?? 0) }
            .map(\.text)
            .filter { !$0.isEmpty }
    }
}
