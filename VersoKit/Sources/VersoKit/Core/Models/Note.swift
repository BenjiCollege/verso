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

    @Relationship(deleteRule: .cascade, inverse: \ImageAsset.note)
    var images: [ImageAsset]? = []

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

    /// Rewrites `position` to a dense 0..<n sequence over a known order.
    ///
    /// Takes the order rather than reading `orderedBlocks`, which sorts by the
    /// very positions being rewritten. After a move that would sort the new
    /// arrangement straight back into the old one, and the edit would vanish.
    private func assignPositions(_ ordered: [Block]) {
        for (index, block) in ordered.enumerated() where block.position != index {
            block.position = index
        }
    }

    /// Closes any gaps or collisions in the existing order. For repairing drift
    /// — two devices inserting at the same index, say — not for applying an
    /// edit: it can only preserve the order `position` already describes.
    func normalizeBlockPositions() {
        assignPositions(orderedBlocks)
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
        assignPositions(ordered)
    }

    func remove(_ block: Block) {
        let ordered = orderedBlocks.filter { $0.id != block.id }
        blocks = ordered
        assignPositions(ordered)
    }

    /// Reorders in place. Written out rather than using SwiftUI's
    /// `move(fromOffsets:toOffset:)` so the model layer doesn't import SwiftUI.
    func moveBlocks(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ordered = orderedBlocks
        let moved = source.sorted().map { ordered[$0] }
        // Removing high-to-low keeps the remaining indices valid.
        for index in source.sorted(by: >) {
            ordered.remove(at: index)
        }
        let insertionPoint = destination - source.filter { $0 < destination }.count
        ordered.insert(contentsOf: moved, at: max(0, min(insertionPoint, ordered.count)))
        blocks = ordered
        assignPositions(ordered)
    }

    /// A copy of this note, blocks and all.
    ///
    /// What is deliberately left behind: version history, which belongs to the
    /// note that lived it; recordings, whose bytes are the largest thing here
    /// and which a copy has no claim on; and the trashed and pinned flags,
    /// which describe where a note sits rather than what it is.
    ///
    /// Blocks are copied by their bytes, so a block of a locked note stays
    /// ciphertext and the copy opens with the same vault — a duplicate is never
    /// a way to get a locked note out from behind the clasp.
    @discardableResult
    func duplicated(into context: ModelContext, titleSuffix: String) -> Note {
        let copy = Note(title: title.isEmpty ? titleSuffix : "\(title) \(titleSuffix)")
        copy.templateID = templateID
        copy.themeID = themeID
        copy.stockID = stockID
        copy.revealStyleID = revealStyleID
        copy.isLocked = isLocked
        copy.isHidden = isHidden
        copy.folder = folder
        copy.tags = tags
        context.insert(copy)

        // Pictures are copied with their ids intact, so the blocks that point
        // at them still do. Without this the copy's images would resolve
        // against the original note and vanish the moment it was deleted.
        for asset in images ?? [] {
            let assetCopy = ImageAsset(id: asset.id, createdAt: asset.createdAt, data: asset.data)
            context.insert(assetCopy)
            assetCopy.note = copy
            copy.images = (copy.images ?? []) + [assetCopy]
        }

        for block in orderedBlocks {
            let blockCopy = Block(
                position: block.position,
                typeRaw: block.typeRaw,
                payload: block.payload
            )
            context.insert(blockCopy)
            copy.append(blockCopy)
        }
        return copy
    }

    func touch(_ date: Date = Date()) {
        modifiedAt = date
    }
}
