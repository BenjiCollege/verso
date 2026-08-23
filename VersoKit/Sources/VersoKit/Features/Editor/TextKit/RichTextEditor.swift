import SwiftUI
import UIKit

/// The TextKit 2 editor for one `text` block.
///
/// Everything the note-level chrome needs — the caret rect, the marks under the
/// caret, an open `[[` — is reported through `TextEditingSession` rather than
/// through a pile of closures, so adding a command later is a method on the
/// session and not another parameter here.
struct RichTextEditor: UIViewRepresentable {

    let blockID: UUID
    @Binding var payload: TextPayload

    let theme: Theme
    let stock: Stock
    let bodySize: CGFloat
    /// The reader's face and leading. `bodySize` already carries their text
    /// scale; these two reach the prose through `AttributedText`.
    let reading: ReadingPreferences
    let session: TextEditingSession
    /// Dims paragraphs other than the caret's. Applied as rendering attributes,
    /// which is display-only: no re-layout, and nothing written to the note.
    let isFocusModeActive: Bool
    let isCaretSuppressed: Bool
    /// The preference, applied to the one text view it can possibly mean.
    var isAutocorrectEnabled: Bool = true
    /// Converts a caret rect from the text view's space into the page's.
    let caretRectInPage: (CGRect) -> CGRect
    /// Reports the caret's character offset, for the audio sync map.
    var onCaretMoved: ((Int) -> Void)?

    func makeCoordinator() -> RichTextCoordinator {
        RichTextCoordinator(parent: self)
    }

    func makeUIView(context: Context) -> VersoTextView {
        let textView = VersoTextView.make()
        textView.delegate = context.coordinator
        textView.textLayoutManager?.delegate = context.coordinator.layoutDelegate
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)

        context.coordinator.attach(textView)
        applyInputPreferences(to: textView)
        context.coordinator.applyRendering(to: textView, animated: false)
        return textView
    }

    /// Autocorrect and its companions travel together: someone who turns
    /// correction off did not ask to keep automatic capitals fixing their
    /// lowercase deliberate.
    private func applyInputPreferences(to textView: VersoTextView) {
        let mode: UITextAutocorrectionType = isAutocorrectEnabled ? .yes : .no
        guard textView.autocorrectionType != mode else { return }
        textView.autocorrectionType = mode
        textView.spellCheckingType = isAutocorrectEnabled ? .yes : .no
        textView.autocapitalizationType = isAutocorrectEnabled ? .sentences : .none
        // The keyboard caches these, so it has to be told to read them again —
        // otherwise the change lands on the next paragraph and not this one.
        if textView.isFirstResponder { textView.reloadInputViews() }
    }

    func updateUIView(_ textView: VersoTextView, context: Context) {
        context.coordinator.parent = self
        textView.isCaretSuppressed = isCaretSuppressed
        applyInputPreferences(to: textView)
        context.coordinator.applyRendering(to: textView, animated: true)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: VersoTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        // An empty paragraph still has to be tall enough to tap.
        let minimum = Typography.contentLineHeight(forSize: bodySize, reading: reading)
        return CGSize(width: width, height: max(fitted.height, minimum))
    }

    static func dismantleUIView(_ textView: VersoTextView, coordinator: RichTextCoordinator) {
        coordinator.commitPendingEdit()
    }
}

@MainActor
final class RichTextCoordinator: NSObject, UITextViewDelegate, RichTextCommandTarget {

    var parent: RichTextEditor
    let layoutDelegate = PageLayoutDelegate()

    private weak var textView: VersoTextView?
    /// Set while the coordinator itself is rewriting the storage, so the
    /// delegate callbacks that rewrite trigger don't recurse.
    private var isApplyingProgrammaticEdit = false
    private var pendingCommit: Task<Void, Never>?
    private var lastAppliedRendering: RenderingKey?
    /// Marks that apply to the next character typed at an empty selection.
    private var pendingTypingStyle: InlineStyle = []

    private struct RenderingKey: Equatable {
        let themeID: String
        let stockID: String
        let bodySize: CGFloat
        let grain: Double
        /// Face and leading, so changing either re-renders. Everything the
        /// rendered text depends on has to be in this key — anything left out
        /// is a control that appears to do nothing.
        let typeface: ContentTypeface
        let lineSpacingScale: Double
    }

    init(parent: RichTextEditor) {
        self.parent = parent
    }

    func attach(_ textView: VersoTextView) {
        self.textView = textView
        setStorage(parent.payload.attributedNS, in: textView, preservingSelection: false)
    }

    // MARK: - Presentation

    /// Re-inks the text and the ruled paper for the current theme, Dynamic Type
    /// size and stock. Cheap and idempotent: it bails unless something it
    /// actually depends on changed.
    func applyRendering(to textView: VersoTextView, animated: Bool) {
        let key = RenderingKey(
            themeID: parent.theme.id,
            stockID: parent.stock.id,
            bodySize: parent.bodySize,
            grain: parent.theme.grain,
            typeface: parent.reading.typeface,
            lineSpacingScale: parent.reading.lineSpacingScale
        )

        let ruleChanged = layoutDelegate.snapshot.containerWidth != textView.textContainer.size.width
        guard key != lastAppliedRendering || ruleChanged else {
            applyFocusDimming(to: textView)
            return
        }
        lastAppliedRendering = key

        // Re-rendering rebuilds the storage from the payload, so anything typed
        // inside the commit window has to be banked first — otherwise a Dynamic
        // Type change mid-sentence would swallow the last few characters.
        commitPendingEdit()

        layoutDelegate.snapshot = PageRenderingSnapshot(
            rule: parent.stock.pattern == .horizontalRules || parent.stock.pattern == .grid
                ? parent.theme.palette.rule
                : nil,
            lineWidth: parent.stock.lineWidth,
            opacity: parent.stock.opacity,
            showsBaselineGuides: parent.stock.showsBaselineGuides,
            containerWidth: textView.textContainer.size.width
        )

        setStorage(parent.payload.attributedNS, in: textView, preservingSelection: true)
        if let layoutManager = textView.textLayoutManager {
            // Fragments carry the snapshot they were built with, so a stock or
            // theme change has to rebuild them.
            layoutManager.invalidateLayout(for: layoutManager.documentRange)
        }
        applyFocusDimming(to: textView)
    }

    /// Writes semantic text into the view, rendered for the current theme.
    private func setStorage(_ semantic: NSAttributedString, in textView: VersoTextView, preservingSelection: Bool) {
        isApplyingProgrammaticEdit = true
        defer { isApplyingProgrammaticEdit = false }

        let selection = preservingSelection ? textView.selectedRange : nil
        textView.attributedText = AttributedText.rendered(
            semantic,
            theme: parent.theme,
            bodySize: parent.bodySize,
            reading: parent.reading
        )
        textView.typingAttributes = AttributedText.typingAttributes(
            style: pendingTypingStyle,
            theme: parent.theme,
            bodySize: parent.bodySize,
            reading: parent.reading
        )
        if let selection, selection.upperBound <= textView.attributedText.length {
            textView.selectedRange = selection
        }
    }

    /// Focus Mode. Rendering attributes are display-only — they never enter the
    /// storage, so nothing here can end up archived into the note.
    private func applyFocusDimming(to textView: VersoTextView) {
        guard let layoutManager = textView.textLayoutManager else { return }
        let document = layoutManager.documentRange
        layoutManager.invalidateRenderingAttributes(for: document)

        guard parent.isFocusModeActive, textView.isFirstResponder else { return }

        let text = textView.text as NSString
        let paragraph = text.paragraphRange(for: textView.selectedRange)
        let dimmed = UIColor(parent.theme.inkTertiary)

        for range in [
            NSRange(location: 0, length: paragraph.location),
            NSRange(
                location: paragraph.upperBound,
                length: max(0, text.length - paragraph.upperBound)
            ),
        ] where range.length > 0 {
            guard let textRange = layoutManager.textRange(for: range) else { continue }
            layoutManager.setRenderingAttributes([.foregroundColor: dimmed], for: textRange)
        }
    }

    // MARK: - Commit

    /// Text is committed on a short idle rather than on every keystroke:
    /// archiving an `NSAttributedString` per character would be needless work
    /// on the main thread and needless CloudKit churn.
    private func scheduleCommit() {
        pendingCommit?.cancel()
        pendingCommit = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.commitPendingEdit()
        }
    }

    func commitPendingEdit() {
        pendingCommit?.cancel()
        pendingCommit = nil
        guard let textView else { return }
        parent.payload = TextPayload(semantic: AttributedText.semantic(textView.attributedText))
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        guard !isApplyingProgrammaticEdit else { return }
        scheduleCommit()
        reportState(textView)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isApplyingProgrammaticEdit else { return }
        if let versoTextView = textView as? VersoTextView {
            applyFocusDimming(to: versoTextView)
        }
        reportState(textView)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        parent.session.editorDidBeginEditing(blockID: parent.blockID, target: self)
        reportState(textView)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        commitPendingEdit()
        parent.session.editorDidEndEditing(blockID: parent.blockID)
        if let versoTextView = textView as? VersoTextView {
            applyFocusDimming(to: versoTextView)
        }
    }

    // MARK: - Reporting

    private func reportState(_ textView: UITextView) {
        let selection = textView.selectedRange
        let style = selection.length > 0
            ? AttributedText.style(of: textView.attributedText, in: selection)
            : pendingTypingStyle
        parent.session.update(style: style)
        parent.session.update(linkDraft: WikiLink.draft(in: textView.text, caret: selection.location))

        // An editable text view places the caret on tap rather than following a
        // link, which is correct — you cannot edit text you cannot click into.
        // So a link under the caret becomes an explicit action in the
        // formatting bar instead of a tap target.
        parent.session.update(
            linkTarget: AttributedText.noteLink(
                of: textView.attributedText,
                at: min(selection.location, max(0, textView.attributedText.length - 1))
            )
        )

        if let versoTextView = textView as? VersoTextView, let caret = versoTextView.currentCaretRect {
            parent.session.update(caretRectInPage: parent.caretRectInPage(caret))
        }

        // Feeds the sync map while a recording is running. Sampled here rather
        // than on every keystroke because the caret moving is what a listener
        // is following — and the recorder coalesces these anyway.
        parent.onCaretMoved?(selection.location)
    }

    // MARK: - RichTextCommandTarget

    var undoManager: UndoManager? { textView?.undoManager }

    func toggle(_ style: InlineStyle) {
        guard let textView else { return }
        let selection = textView.selectedRange

        guard selection.length > 0 else {
            // No selection: arm the mark for whatever is typed next.
            pendingTypingStyle.formSymmetricDifference(style)
            textView.typingAttributes = AttributedText.typingAttributes(
                style: pendingTypingStyle,
                theme: parent.theme,
                bodySize: parent.bodySize,
                reading: parent.reading
            )
            parent.session.update(style: pendingTypingStyle)
            return
        }

        let semantic = AttributedText.semantic(textView.attributedText)
        let isOn = AttributedText.style(of: semantic, in: selection).contains(style)
        let updated = AttributedText.setting(style, enabled: !isOn, in: selection, of: semantic)

        setStorage(updated, in: textView, preservingSelection: true)
        parent.payload = TextPayload(semantic: updated)
        parent.session.update(style: AttributedText.style(of: updated, in: selection))
    }

    /// Opens a link by typing the delimiter for the user. Only `[[` is
    /// inserted — the closing pair is written by `completeLink`, so there is
    /// never a stray `]]` left behind if the draft is abandoned.
    func startLink() {
        guard let textView else { return }
        textView.insertText(WikiLink.openingDelimiter)
        reportState(textView)
        scheduleCommit()
    }

    func completeLink(title: String, noteID: UUID?) {
        guard let textView, let draft = WikiLink.draft(in: textView.text, caret: textView.selectedRange.location) else {
            return
        }

        let markup = WikiLink.markup(for: title)
        let semantic = NSMutableAttributedString(attributedString: AttributedText.semantic(textView.attributedText))
        guard draft.range.upperBound <= semantic.length else { return }

        var attributes: [NSAttributedString.Key: Any] = [:]
        if let noteID {
            attributes[VersoTextAttribute.noteLink] = noteID.uuidString
        }
        semantic.replaceCharacters(
            in: draft.range,
            with: NSAttributedString(string: markup, attributes: attributes)
        )

        setStorage(semantic, in: textView, preservingSelection: false)
        textView.selectedRange = NSRange(location: draft.range.location + (markup as NSString).length, length: 0)
        parent.payload = TextPayload(semantic: semantic)
        parent.session.update(linkDraft: nil)
    }

    func dismissLinkDraft() {
        parent.session.update(linkDraft: nil)
    }
}

// MARK: - Payload bridging

extension TextPayload {
    /// The archived text as `NSAttributedString`, which is what the text view
    /// and every `AttributedText` helper work in.
    var attributedNS: NSAttributedString {
        guard !archive.isEmpty,
              let restored = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: archive)
        else {
            return NSAttributedString(string: plain)
        }
        return restored
    }

    /// Builds a payload from semantic text, refreshing the plain mirror.
    init(semantic: NSAttributedString) {
        let stripped = AttributedText.semantic(semantic)
        self.init(
            archive: (try? NSKeyedArchiver.archivedData(withRootObject: stripped, requiringSecureCoding: true)) ?? Data(),
            plain: stripped.string
        )
    }
}
