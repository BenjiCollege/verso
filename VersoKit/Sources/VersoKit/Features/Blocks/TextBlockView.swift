import SwiftUI

/// A paragraph, edited in TextKit 2.
///
/// The text view does not scroll — it sizes to its content inside the note's
/// single scroll view. That is what makes typewriter scroll a property of the
/// note rather than of one paragraph, and it is why this view has to report its
/// own frame in the page's coordinate space so a caret rect can be translated
/// outward.
struct TextBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.stock) private var stock
    @Environment(\.textEditingSession) private var session
    @Environment(\.editorFocusMode) private var isFocusModeActive
    @Environment(\.caretSuppressed) private var isCaretSuppressed
    @Environment(RecordingSession.self) private var recording
    @Environment(AppearanceStore.self) private var appearance

    @Environment(\.readingPreferences) private var reading

    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = Typography.Role.body.pointSize

    /// The reader's scale, applied here as well as in `versoText`.
    ///
    /// A paragraph is TextKit 2 inside a `UITextView`, so it never passes
    /// through the SwiftUI text modifier that honours this — which meant the
    /// text size control moved every heading and caption in the app and left
    /// the actual writing alone.
    private var scaledBodySize: CGFloat { bodySize * reading.textScale }

    @State private var frameInPage: CGRect = .zero

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<TextPayload>) in
            RichTextEditor(
                blockID: block.id,
                payload: payload,
                theme: theme,
                stock: stock,
                bodySize: scaledBodySize,
                session: session,
                isFocusModeActive: isFocusModeActive,
                isCaretSuppressed: isCaretSuppressed,
                isAutocorrectEnabled: appearance.isAutocorrectEnabled,
                caretRectInPage: { caret in
                    caret.offsetBy(dx: frameInPage.minX, dy: frameInPage.minY)
                },
                onCaretMoved: { offset in
                    recording.sampleCaret(blockID: block.id, characterOffset: offset)
                }
            )
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(NoteEditorView.pageCoordinateSpace))
            } action: { newValue in
                frameInPage = newValue
            }
            .accessibilityLabel(Text("Text block"))
        }
    }
}

extension EnvironmentValues {
    /// Focus Mode dims everything but the paragraph being written.
    @Entry var editorFocusMode: Bool = false

    /// Hides the caret while the page is moving under it.
    @Entry var caretSuppressed: Bool = false
}
