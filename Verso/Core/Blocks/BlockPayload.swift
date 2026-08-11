import Foundation

/// The contract every block payload satisfies.
///
/// Payloads are value types. They never reach for a `ModelContext`, never know
/// which note they belong to, and never branch on a template identifier.
protocol BlockPayload: Codable, Sendable, Equatable {
    /// The discriminator written to `Block.typeRaw`.
    static var blockType: BlockType { get }

    /// The payload a freshly inserted block of this type starts with.
    static func makeDefault() -> Self

    /// Plain-text projection, used for list previews, note titling and — later —
    /// Spotlight and semantic indexing. Blocks with no text return "".
    var plainTextRepresentation: String { get }

    /// The payload as it should appear when this note is saved as a template:
    /// structure kept, one person's data dropped. A checklist keeps its groups
    /// and loses its ticks; a metric keeps its series and loses its reading.
    ///
    /// The default keeps everything, which is right for headings, dividers and
    /// anything else that is already structure.
    func resetForTemplate() -> Self
}

extension BlockPayload {
    var plainTextRepresentation: String { "" }

    func resetForTemplate() -> Self { self }
}

enum BlockRegistryError: LocalizedError, Equatable {
    case unknownType(String)
    case unimplementedType(BlockType)
    case typeMismatch(expected: String, found: String)

    var errorDescription: String? {
        switch self {
        case .unknownType(let raw):
            String(localized: "This note contains a “\(raw)” block that this version of Verso doesn't recognize.")
        case .unimplementedType(let type):
            String(localized: "\(String(localized: type.displayName)) blocks aren't supported in this version of Verso yet.")
        case .typeMismatch(let expected, let found):
            String(localized: "Expected a \(expected) block but found \(found).")
        }
    }
}

/// The single canonical JSON coder for block payloads.
///
/// Sorted keys and a fixed date strategy make the encoded bytes deterministic,
/// which is what lets `BlockPayloadRoundTripTests` compare `Data` directly and
/// what will let Phase 6 diff two versions byte-wise.
///
/// The coders are built per call rather than cached in a `static let`:
/// `JSONEncoder` is a class and is not `Sendable`, and a shared mutable one
/// would be a data race under strict concurrency.
enum BlockCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf",
            negativeInfinity: "-inf",
            nan: "nan"
        )
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf",
            negativeInfinity: "-inf",
            nan: "nan"
        )
        return decoder
    }

    static func encode<P: Encodable>(_ payload: P) throws -> Data {
        try makeEncoder().encode(payload)
    }

    static func decode<P: Decodable>(_ type: P.Type, from data: Data) throws -> P {
        try makeDecoder().decode(type, from: data)
    }
}
