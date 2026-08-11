import Foundation

/// A note, frozen.
///
/// Structural rather than a blob of the whole store: knowing which blocks
/// changed is what lets a version be stored as a delta, and what lets the
/// fore-edge morph content backwards rather than swapping one page for another.
struct NoteSnapshot: Codable, Hashable, Sendable {

    struct BlockSnapshot: Codable, Hashable, Sendable, Identifiable {
        var id: UUID
        var position: Int
        var type: String
        var payload: Data

        init(id: UUID, position: Int, type: String, payload: Data) {
            self.id = id
            self.position = position
            self.type = type
            self.payload = payload
        }
    }

    var title: String
    var themeID: String?
    var stockID: String?
    var revealStyleID: String?
    var blocks: [BlockSnapshot]

    init(
        title: String = "",
        themeID: String? = nil,
        stockID: String? = nil,
        revealStyleID: String? = nil,
        blocks: [BlockSnapshot] = []
    ) {
        self.title = title
        self.themeID = themeID
        self.stockID = stockID
        self.revealStyleID = revealStyleID
        self.blocks = blocks.sorted { $0.position < $1.position }
    }

    init(_ note: Note) {
        self.init(
            title: note.title,
            themeID: note.themeID,
            stockID: note.stockID,
            revealStyleID: note.revealStyleID,
            blocks: note.orderedBlocks.enumerated().map { index, block in
                BlockSnapshot(id: block.id, position: index, type: block.typeRaw, payload: block.payload)
            }
        )
    }

    /// Rough size of the note, used to decide whether an edit was worth
    /// recording and to set the fore-edge's density.
    var characterCount: Int {
        title.count + blocks.reduce(0) { $0 + $1.payload.count }
    }

    var readableLength: Int {
        title.count + blocks.reduce(0) { partial, block in
            guard let type = BlockType(rawValue: block.type) else { return partial }
            return partial + ((try? BlockRegistry.shared.plainText(block.payload, as: type))?.count ?? 0)
        }
    }
}

/// What changed between two snapshots.
///
/// Only the blocks that actually moved or changed are carried, which is what
/// makes a version of a twenty-thousand-word note cost a few hundred bytes
/// rather than a few hundred kilobytes.
struct NoteDelta: Codable, Hashable, Sendable {
    /// `nil` means unchanged. A changed-to-nil field is carried as
    /// `.some(nil)`, which is why these are doubly optional.
    var title: String?
    var themeID: String??
    var stockID: String??
    var revealStyleID: String??

    var removed: [UUID]
    /// Added or modified blocks, carrying their whole payload.
    var changed: [NoteSnapshot.BlockSnapshot]
    /// Present only when the order changed.
    var order: [UUID]?

    var isEmpty: Bool {
        title == nil && themeID == nil && stockID == nil && revealStyleID == nil
            && removed.isEmpty && changed.isEmpty && order == nil
    }

    static func between(_ old: NoteSnapshot, and new: NoteSnapshot) -> NoteDelta {
        let oldBlocks = Dictionary(uniqueKeysWithValues: old.blocks.map { ($0.id, $0) })
        let newBlocks = Dictionary(uniqueKeysWithValues: new.blocks.map { ($0.id, $0) })

        let changed = new.blocks.filter { block in
            guard let previous = oldBlocks[block.id] else { return true }
            return previous.type != block.type || previous.payload != block.payload
        }

        let oldOrder = old.blocks.map(\.id)
        let newOrder = new.blocks.map(\.id)

        return NoteDelta(
            title: old.title == new.title ? nil : new.title,
            themeID: old.themeID == new.themeID ? nil : .some(new.themeID),
            stockID: old.stockID == new.stockID ? nil : .some(new.stockID),
            revealStyleID: old.revealStyleID == new.revealStyleID ? nil : .some(new.revealStyleID),
            removed: oldBlocks.keys.filter { newBlocks[$0] == nil }.sorted { $0.uuidString < $1.uuidString },
            changed: changed,
            order: oldOrder == newOrder ? nil : newOrder
        )
    }

    /// Rewinds a snapshot by one step. Deltas are stored *backwards* — from the
    /// newer state to the older one — because reconstructing recent history is
    /// the common case, and history is walked from now into the past.
    func applied(to snapshot: NoteSnapshot) -> NoteSnapshot {
        var result = snapshot

        if let title { result.title = title }
        if let themeID { result.themeID = themeID }
        if let stockID { result.stockID = stockID }
        if let revealStyleID { result.revealStyleID = revealStyleID }

        var blocks = Dictionary(uniqueKeysWithValues: result.blocks.map { ($0.id, $0) })
        for id in removed { blocks[id] = nil }
        for block in changed { blocks[block.id] = block }

        if let order {
            result.blocks = order.enumerated().compactMap { index, id in
                guard var block = blocks[id] else { return nil }
                block.position = index
                return block
            }
        } else {
            result.blocks = result.blocks
                .compactMap { blocks[$0.id] }
                .enumerated()
                .map { index, block in
                    var block = block
                    block.position = index
                    return block
                }
            // Blocks the delta introduced that were not in the previous order
            // go on the end, in id order so the result is deterministic.
            let placed = Set(result.blocks.map(\.id))
            let extras = changed.filter { !placed.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
            for var extra in extras {
                extra.position = result.blocks.count
                result.blocks.append(extra)
            }
        }

        return result
    }
}

/// Encoding, with the compression that makes keeping a hundred versions
/// reasonable.
enum SnapshotCoding {

    static func encode(_ snapshot: NoteSnapshot) throws -> Data {
        try compress(BlockCoding.encode(snapshot))
    }

    static func decodeSnapshot(_ data: Data) throws -> NoteSnapshot {
        try BlockCoding.decode(NoteSnapshot.self, from: decompress(data))
    }

    static func encode(_ delta: NoteDelta) throws -> Data {
        try compress(BlockCoding.encode(delta))
    }

    static func decodeDelta(_ data: Data) throws -> NoteDelta {
        try BlockCoding.decode(NoteDelta.self, from: decompress(data))
    }

    /// zlib, via Foundation. Snapshots are JSON, which compresses to a fraction
    /// of its size, and they go to CloudKit as assets.
    static func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return data }
        return try (data as NSData).compressed(using: .zlib) as Data
    }

    static func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return data }
        return try (data as NSData).decompressed(using: .zlib) as Data
    }
}
