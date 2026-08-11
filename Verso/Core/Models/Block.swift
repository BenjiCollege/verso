import Foundation
import SwiftData

/// A single positioned, typed unit of content.
///
/// The persisted shape is deliberately opaque: a type discriminator plus an
/// externally-stored blob. Everything that knows how to read that blob lives
/// behind `BlockRegistry`, which is how the storage layer stays content-agnostic.
@Model
final class Block {
    var id: UUID = UUID()
    var position: Int = 0
    var typeRaw: String = "text"                             // BlockType.rawValue
    @Attribute(.externalStorage) var payload: Data = Data()  // Codable per type
    var note: Note?

    init(id: UUID = UUID(), position: Int = 0, typeRaw: String = "text", payload: Data = Data()) {
        self.id = id
        self.position = position
        self.typeRaw = typeRaw
        self.payload = payload
    }
}

extension Block {
    /// `nil` when the store holds a block written by a newer build of the app.
    /// Callers must render something rather than crash — see `BlockRenderer`.
    var type: BlockType? {
        BlockType(rawValue: typeRaw)
    }

    convenience init<P: BlockPayload>(_ payload: P, position: Int = 0) throws {
        self.init(
            position: position,
            typeRaw: P.blockType.rawValue,
            payload: try BlockCoding.encode(payload)
        )
    }

    /// Decodes into a known concrete payload type.
    func decoded<P: BlockPayload>(as _: P.Type = P.self) throws -> P {
        guard typeRaw == P.blockType.rawValue else {
            throw BlockRegistryError.typeMismatch(expected: P.blockType.rawValue, found: typeRaw)
        }
        return try BlockCoding.decode(P.self, from: payload)
    }

    /// Decodes through the registry when the concrete type isn't known statically.
    func decodedPayload() throws -> any BlockPayload {
        guard let type else { throw BlockRegistryError.unknownType(typeRaw) }
        return try BlockRegistry.shared.decode(payload, as: type)
    }

    func store<P: BlockPayload>(_ payload: P) throws {
        typeRaw = P.blockType.rawValue
        self.payload = try BlockCoding.encode(payload)
    }
}
