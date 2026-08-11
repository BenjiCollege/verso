import Foundation

/// The one place in the app that maps a `BlockType` to a concrete payload type.
///
/// Nothing else may `switch` over `BlockType` to decode. If you find yourself
/// writing that switch in a view file, route it through here instead — the
/// registry is what lets persistence, templates, export and search all stay
/// content-agnostic, and it is the seam a new block type is added at.
struct BlockRegistry: Sendable {

    struct Entry: Sendable {
        let type: BlockType

        /// Decodes stored bytes into an existential payload.
        let decode: @Sendable (Data) throws -> any BlockPayload

        /// The payload a newly inserted block starts with, already encoded.
        let makeDefaultData: @Sendable () throws -> Data

        /// Validates and canonicalises a payload written as inline JSON in a
        /// template file, by round-tripping it through the real payload type.
        /// A template with a malformed payload fails loudly at load time rather
        /// than silently producing an empty block.
        let transcode: @Sendable (JSONValue) throws -> Data

        /// Plain-text projection without the caller needing the concrete type.
        let plainText: @Sendable (Data) throws -> String
    }

    private let entries: [BlockType: Entry]

    private init(entries: [Entry]) {
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.type, $0) })
    }

    /// Builds the entry for a payload type. Adding a block type to the app is
    /// this one line plus the payload struct — nothing else changes.
    private static func entry<P: BlockPayload>(_ type: P.Type) -> Entry {
        Entry(
            type: P.blockType,
            decode: { data in try BlockCoding.decode(P.self, from: data) },
            makeDefaultData: { try BlockCoding.encode(P.makeDefault()) },
            transcode: { json in
                let payload = try json.decode(as: P.self, using: BlockCoding.makeDecoder())
                return try BlockCoding.encode(payload)
            },
            plainText: { data in try BlockCoding.decode(P.self, from: data).plainTextRepresentation }
        )
    }

    /// Phase 1 implements five block types. The rest are declared in
    /// `BlockType` but deliberately absent here until their phase lands.
    static let shared = BlockRegistry(entries: [
        entry(TextPayload.self),
        entry(HeadingPayload.self),
        entry(ChecklistPayload.self),
        entry(ListPayload.self),
        entry(DividerPayload.self),
    ])

    // MARK: - Lookup

    /// Block types this build can decode and render, in `BlockType` declaration
    /// order so the inserter menu is stable.
    var implementedTypes: [BlockType] {
        BlockType.allCases.filter { entries[$0] != nil }
    }

    func isImplemented(_ type: BlockType) -> Bool {
        entries[type] != nil
    }

    func entry(for type: BlockType) throws -> Entry {
        guard let entry = entries[type] else {
            throw BlockRegistryError.unimplementedType(type)
        }
        return entry
    }

    // MARK: - Operations

    func decode(_ data: Data, as type: BlockType) throws -> any BlockPayload {
        try entry(for: type).decode(data)
    }

    func makeDefaultData(for type: BlockType) throws -> Data {
        try entry(for: type).makeDefaultData()
    }

    func transcode(_ json: JSONValue, as type: BlockType) throws -> Data {
        try entry(for: type).transcode(json)
    }

    func plainText(_ data: Data, as type: BlockType) throws -> String {
        try entry(for: type).plainText(data)
    }

    /// Best-effort plain text for a stored block. Returns "" for anything this
    /// build can't read, because previews and titling must never throw.
    func plainText(for block: Block) -> String {
        guard let type = block.type, let entry = entries[type] else { return "" }
        return (try? entry.plainText(block.payload)) ?? ""
    }

    /// Creates a detached block of the given type carrying its default payload.
    func makeBlock(of type: BlockType, position: Int = 0) throws -> Block {
        Block(position: position, typeRaw: type.rawValue, payload: try makeDefaultData(for: type))
    }
}
