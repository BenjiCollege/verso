import SwiftUI

/// What the toolbar and the link suggester talk to.
///
/// The formatting bar is a SwiftUI view and the text view is UIKit; rather than
/// threading closures through both, one observable object holds a reference to
/// whichever editor is currently first responder and forwards commands to it.
@MainActor
protocol RichTextCommandTarget: AnyObject {
    func toggle(_ style: InlineStyle)
    func startLink()
    func completeLink(title: String, noteID: UUID?)
    func dismissLinkDraft()

    /// The text view's own undo stack.
    ///
    /// `UITextView` keeps one and registers typing on it, but nothing was
    /// reachable from SwiftUI to drive it, so the only way to undo was the shake
    /// gesture — which is undiscoverable, and unusable if you have Shake to Undo
    /// turned off, which many people do precisely because it fires by accident.
    var undoManager: UndoManager? { get }
}

@MainActor
@Observable
final class TextEditingSession {

    /// The block whose editor is first responder, if any.
    private(set) var activeBlockID: UUID?

    /// Marks under the caret or across the selection, for toolbar state.
    private(set) var activeStyle: InlineStyle = []

    /// A `[[` the user has opened and not yet closed.
    private(set) var linkDraft: WikiLink.Draft?

    /// The caret in the note's coordinate space, for typewriter scrolling.
    private(set) var caretRectInPage: CGRect?

    /// The note a link under the caret points at, if any.
    private(set) var linkTarget: UUID?

    @ObservationIgnored
    private weak var target: (any RichTextCommandTarget)?

    /// `nonisolated` so the environment key's default value can be built
    /// wherever SwiftUI needs it. Every stored property has a `Sendable`
    /// default, so there is nothing here that could escape the main actor.
    nonisolated init() {}

    var isEditing: Bool { activeBlockID != nil }

    // MARK: - Editor callbacks

    func editorDidBeginEditing(blockID: UUID, target: any RichTextCommandTarget) {
        self.activeBlockID = blockID
        self.target = target
    }

    func editorDidEndEditing(blockID: UUID) {
        guard activeBlockID == blockID else { return }
        activeBlockID = nil
        activeStyle = []
        linkDraft = nil
        caretRectInPage = nil
        linkTarget = nil
        target = nil
    }

    func update(style: InlineStyle) {
        activeStyle = style
    }

    func update(linkDraft: WikiLink.Draft?) {
        self.linkDraft = linkDraft
    }

    func update(caretRectInPage: CGRect?) {
        self.caretRectInPage = caretRectInPage
    }

    func update(linkTarget: UUID?) {
        self.linkTarget = linkTarget
    }

    // MARK: - Commands

    func toggle(_ style: InlineStyle) {
        target?.toggle(style)
    }

    // MARK: - Undo

    var canUndo: Bool { target?.undoManager?.canUndo ?? false }
    var canRedo: Bool { target?.undoManager?.canRedo ?? false }

    func undo() { target?.undoManager?.undo() }
    func redo() { target?.undoManager?.redo() }

    func startLink() {
        target?.startLink()
    }

    func completeLink(title: String, noteID: UUID?) {
        target?.completeLink(title: title, noteID: noteID)
    }

    func dismissLinkDraft() {
        target?.dismissLinkDraft()
        linkDraft = nil
    }
}

extension EnvironmentValues {
    @Entry var textEditingSession: TextEditingSession = TextEditingSession()
}
