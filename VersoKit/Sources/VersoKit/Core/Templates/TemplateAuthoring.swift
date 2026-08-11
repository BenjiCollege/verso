import Foundation
import UniformTypeIdentifiers

/// Turning a note back into a template.
///
/// The exact inverse of `TemplateInstantiator`: it walks the blocks and asks
/// `BlockRegistry` to render each payload as inline JSON. There is no switch on
/// block type here either, which is what makes "save as template" work for a
/// block type added after this file was written.
enum TemplateAuthoring {

    static func makeTemplate(
        from note: Note,
        name: String,
        summary: String? = nil,
        category: String? = nil,
        systemImage: String = "doc.text",
        keepContents: Bool,
        id: String = "user." + UUID().uuidString,
        registry: BlockRegistry = .shared
    ) throws -> Template {
        let blocks = try note.orderedBlocks.compactMap { block -> Template.BlockSpec? in
            guard let type = block.type, registry.isImplemented(type) else { return nil }
            let payload = keepContents
                ? try registry.json(block.payload, as: type)
                : try registry.templateJSON(block.payload, as: type)
            return Template.BlockSpec(type: type.rawValue, payload: payload)
        }

        var template = Template(
            id: id,
            name: name,
            summary: summary?.isEmpty == true ? nil : summary,
            systemImage: systemImage,
            category: category,
            themeID: note.themeID,
            stockID: note.stockID,
            revealStyleID: note.revealStyleID,
            // The note's own title becomes the default, but only if it says
            // something — "Untitled" is not worth inheriting.
            titleFormat: note.title.isEmpty ? nil : note.title,
            blocks: blocks
        )
        template.isUserAuthored = true
        return template
    }

    /// Suggested name when saving. The note's title if it has one.
    static func suggestedName(for note: Note) -> String {
        note.title.isEmpty ? String(localized: "My Template") : note.title
    }
}

extension UTType {
    /// Declared in `Info.plist` as an exported type so a `.versotemplate` file
    /// opens in Verso from Files, Mail or AirDrop. Sharing a template is a file
    /// changing hands — there is no server involved and never will be.
    static let versoTemplate = UTType(exportedAs: "com.verso.notes.template", conformingTo: .json)
}
