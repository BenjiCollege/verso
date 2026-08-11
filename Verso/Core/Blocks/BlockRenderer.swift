import SwiftUI

/// The single mapping from a block type to a view.
///
/// This is the one permitted `switch` over `BlockType`, and it exists in
/// exactly one file. Decoding still goes through `BlockRegistry`; this only
/// chooses which editor to show. A block type the build cannot render falls
/// through to `UnsupportedBlockView` rather than vanishing from the note.
struct BlockRenderer: View {
    let block: Block

    var body: some View {
        switch block.type {
        case .text:
            TextBlockView(block: block)
        case .heading:
            HeadingBlockView(block: block)
        case .checklist:
            ChecklistBlockView(block: block)
        case .list:
            ListBlockView(block: block)
        case .divider:
            DividerBlockView(block: block)
        case .metric:
            MetricBlockView(block: block)
        case .timer:
            TimerBlockView(block: block)
        case .formula:
            FormulaBlockView(block: block)
        case .progress:
            ProgressBlockView(block: block)
        case .rating:
            RatingBlockView(block: block)
        case .table:
            TableBlockView(block: block)
        case .schedule:
            ScheduleBlockView(block: block)
        case .place:
            PlaceBlockView(block: block)
        case .sketch:
            SketchBlockView(block: block)
        case .audio:
            AudioBlockView(block: block)
        case .attachment:
            AttachmentBlockView(block: block)
        case .some(let type):
            UnsupportedBlockView(typeName: String(localized: type.displayName), systemImage: type.systemImage)
        case nil:
            UnsupportedBlockView(typeName: block.typeRaw, systemImage: "questionmark.square.dashed")
        }
    }
}
