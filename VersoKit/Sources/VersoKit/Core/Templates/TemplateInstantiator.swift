import Foundation
import SwiftData

/// Turns a `Template` into a `Note`.
///
/// This file contains no template identifiers and no `switch` on block type.
/// It walks the spec, asks `BlockRegistry` to validate and canonicalise each
/// payload, and stops at the first failure so a broken template surfaces
/// immediately rather than producing a half-built note.
enum TemplateInstantiator {

    /// Substituted into `Template.titleFormat`. Formatting, not domain
    /// knowledge — a template can say `{weekday}` but not `{workout}`.
    enum TitleToken: String, CaseIterable, Sendable {
        case date = "{date}"
        case weekday = "{weekday}"
        case time = "{time}"

        func value(for date: Date, locale: Locale) -> String {
            switch self {
            case .date:
                date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
            case .weekday:
                date.formatted(.dateTime.weekday(.wide).locale(locale))
            case .time:
                date.formatted(.dateTime.hour().minute().locale(locale))
            }
        }
    }

    static func title(from format: String?, date: Date, locale: Locale = .current) -> String {
        guard let format else { return "" }
        return TitleToken.allCases.reduce(format) { partial, token in
            partial.replacingOccurrences(of: token.rawValue, with: token.value(for: date, locale: locale))
        }
    }

    /// Builds the blocks for a template without touching a `ModelContext`, so
    /// the whole thing can be validated — and tested — before anything is
    /// inserted into the store.
    static func makeBlocks(
        from template: Template,
        using registry: BlockRegistry = .shared
    ) throws -> [Block] {
        try template.blocks.enumerated().map { index, spec in
            guard let type = spec.blockType else {
                throw TemplateError.unknownBlockType(templateID: template.id, raw: spec.type)
            }
            guard registry.isImplemented(type) else {
                throw TemplateError.unsupportedBlockType(templateID: template.id, type: type)
            }
            do {
                let payload = try registry.transcode(spec.payload, as: type)
                return Block(position: index, typeRaw: type.rawValue, payload: payload)
            } catch {
                throw TemplateError.malformedPayload(
                    templateID: template.id,
                    index: index,
                    type: spec.type,
                    underlying: error.localizedDescription
                )
            }
        }
    }

    /// Creates and inserts a note. The note is only inserted once every block
    /// has been built, so a failure leaves the store untouched.
    @discardableResult
    static func makeNote(
        from template: Template,
        in context: ModelContext,
        date: Date = Date(),
        locale: Locale = .current,
        registry: BlockRegistry = .shared
    ) throws -> Note {
        let blocks = try makeBlocks(from: template, using: registry)

        let note = Note(
            title: title(from: template.titleFormat, date: date, locale: locale),
            templateID: template.id,
            themeID: template.themeID,
            stockID: template.stockID,
            revealStyleID: template.revealStyleID,
            createdAt: date
        )

        context.insert(note)
        for block in blocks {
            context.insert(block)
            note.append(block)
        }
        note.normalizeBlockPositions()

        return note
    }
}
