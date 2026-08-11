import SwiftUI

/// A paragraph.
///
/// Phase 1 edits plain text through a SwiftUI `TextField`. Phase 2 replaces the
/// field with a TextKit 2 `UITextView`, which is what typewriter scroll,
/// per-fragment rule rendering and per-glyph reveal require. Until then, an
/// edit rebuilds the archive from the plain string — there is no formatting UI
/// yet, so there are no attributes to lose.
struct TextBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<TextPayload>) in
            TextField(
                "Body text",
                text: Binding(
                    get: { payload.wrappedValue.plain },
                    set: { payload.wrappedValue = TextPayload(plain: $0) }
                ),
                prompt: Text("Write…").foregroundStyle(theme.inkTertiary),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .versoText(.body)
            .foregroundStyle(theme.ink)
            .accessibilityLabel(Text("Text block"))
        }
    }
}
