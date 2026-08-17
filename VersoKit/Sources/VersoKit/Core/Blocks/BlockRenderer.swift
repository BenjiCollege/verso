import SwiftUI

/// The single mapping from a block type to a view.
///
/// This is the one permitted `switch` over `BlockType`, and it exists in
/// exactly one file. Decoding still goes through `BlockRegistry`; this only
/// chooses which editor to show. A block type the build cannot render falls
/// through to `UnsupportedBlockView` rather than vanishing from the note.
///
/// The `presentation` chooses between the editor and a flat drawing of the same
/// block for export. Only the types that need it differ — see `Printed` for why
/// reusing the editors crashed PDF export rather than merely looking wrong.
struct BlockRenderer: View {
    let block: Block
    var presentation: BlockPresentation = .interactive

    private var isPrinted: Bool { presentation == .printed }

    var body: some View {
        switch block.type {
        case .text:
            if isPrinted { Printed.TextBlock(block: block) } else { TextBlockView(block: block) }
        case .image:
            if isPrinted { Printed.ImageBlock(block: block) } else { ImageBlockView(block: block) }
        case .heading:
            HeadingBlockView(block: block)
        case .checklist:
            if isPrinted { Printed.ChecklistBlock(block: block) } else { ChecklistBlockView(block: block) }
        case .list:
            ListBlockView(block: block)
        case .divider:
            DividerBlockView(block: block)
        case .metric:
            if isPrinted { Printed.MetricBlock(block: block) } else { MetricBlockView(block: block) }
        case .timer:
            if isPrinted { Printed.TimerBlock(block: block) } else { TimerBlockView(block: block) }
        case .formula:
            FormulaBlockView(block: block)
        case .progress:
            ProgressBlockView(block: block)
        case .rating:
            RatingBlockView(block: block)
        case .table:
            TableBlockView(block: block)
        case .schedule:
            if isPrinted { Printed.ScheduleBlock(block: block) } else { ScheduleBlockView(block: block) }
        case .place:
            if isPrinted { Printed.PlaceBlock(block: block) } else { PlaceBlockView(block: block) }
        case .sketch:
            if isPrinted { Printed.SketchBlock(block: block) } else { SketchBlockView(block: block) }
        case .audio:
            if isPrinted { Printed.AudioBlock(block: block) } else { AudioBlockView(block: block) }
        case .attachment:
            AttachmentBlockView(block: block)
        case .some(let type):
            UnsupportedBlockView(typeName: String(localized: type.displayName), systemImage: type.systemImage)
        case nil:
            UnsupportedBlockView(typeName: block.typeRaw, systemImage: "questionmark.square.dashed")
        }
    }
}
