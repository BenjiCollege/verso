import Foundation
import SwiftData

/// The unit of authorship. A note is an ordered array of typed blocks and
/// nothing more — it carries no knowledge of what those blocks mean.
///
/// SwiftData models are deliberately not `Sendable`: each one is confined to
/// the `ModelContext` that vended it. The project therefore leaves default
/// actor isolation at `nonisolated` and puts `@MainActor` on the UI-facing
/// stores instead, rather than pretending model objects are main-thread-bound.
@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var blocks: [Block]? = []            // ordered by Block.position
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var templateID: String?
    var themeID: String?                 // nil = inherit app default
    var stockID: String?
    var revealStyleID: String?
    var isLocked: Bool = false
    var isHidden: Bool = false
    var isPinned: Bool = false
    var isTrashed: Bool = false
    var trashedAt: Date?
    var folder: Folder?
    var tags: [Tag]? = []

    @Relationship(deleteRule: .cascade, inverse: \Version.note)
    var versions: [Version]? = []

    @Relationship(deleteRule: .cascade, inverse: \AudioAsset.note)
    var audio: [AudioAsset]? = []

    init(
        id: UUID = UUID(),
        title: String = "",
        templateID: String? = nil,
        themeID: String? = nil,
        stockID: String? = nil,
        revealStyleID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.templateID = templateID
        self.themeID = themeID
        self.stockID = stockID
        self.revealStyleID = revealStyleID
        self.createdAt = createdAt
        self.modifiedAt = createdAt
    }
}

extension Note {
    /// Blocks in document order. The relationship itself is an unordered set as
    /// far as SwiftData is concerned; `position` is the authority.
    var orderedBlocks: [Block] {
        (blocks ?? []).sorted { $0.position < $1.position }
    }

    /// Rewrites `position` to a dense 0..<n sequence. Call after any structural
    /// edit so positions never drift or collide.
    func normalizeBlockPositions() {
        for (index, block) in orderedBlocks.enumerated() where block.position != index {
            block.position = index
        }
    }

    func append(_ block: Block) {
        block.position = (blocks ?? []).count
        block.note = self
        blocks = (blocks ?? []) + [block]
    }

    func insert(_ block: Block, at index: Int) {
        var ordered = orderedBlocks
        let clamped = max(0, min(index, ordered.count))
        block.note = self
        ordered.insert(block, at: clamped)
        blocks = ordered
        normalizeBlockPositions()
    }

    func remove(_ block: Block) {
        blocks = orderedBlocks.filter { $0.id != block.id }
        normalizeBlockPositions()
    }

    func moveBlocks(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ordered = orderedBlocks
        ordered.move(fromOffsets: source, toOffset: destination)
        blocks = ordered
        normalizeBlockPositions()
    }

    func touch(_ date: Date = Date()) {
        modifiedAt = date
    }
}
