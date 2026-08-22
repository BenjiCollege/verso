import SwiftData
import SwiftUI

/// Duplicating and deleting a single block, with a way back.
///
/// Deleting is the only destructive thing the page offers, and it is offered
/// through a long press — a gesture people trigger by accident. So it is not
/// confirmed with a dialog, which trains you to dismiss dialogs, but undone: the
/// block is kept whole and put back exactly where it was.
@MainActor
@Observable
final class BlockActions {

    /// Everything needed to rebuild a block, kept flat so it survives the
    /// object being deleted from the context.
    struct Deleted: Equatable, Sendable {
        var id: UUID
        var typeRaw: String
        var payload: Data
        var position: Int
        var noteID: UUID
    }

    /// The last delete, if it can still be taken back.
    private(set) var recovered: Deleted?

    /// How long the offer stands. Long enough to notice and reach, short enough
    /// that it is gone before it becomes furniture.
    static let recoveryWindow: Duration = .seconds(8)

    private var expiry: Task<Void, Never>?

    func duplicate(_ block: Block, in note: Note, context: ModelContext) {
        let copy = Block(
            position: block.position + 1,
            typeRaw: block.typeRaw,
            payload: block.payload
        )
        context.insert(copy)
        note.insert(copy, at: block.position + 1)
        note.touch()
    }

    /// One place up or down.
    ///
    /// Reordering had its own sheet and nothing else, so moving a single
    /// paragraph was four steps. The sheet still earns its place for real
    /// restructuring; this is for the move you make while writing.
    ///
    /// - Returns: whether anything moved, so a caller can decline to buzz when
    ///   the block is already at the end it is being pushed towards.
    @discardableResult
    func move(_ block: Block, in note: Note, by offset: Int) -> Bool {
        let ordered = note.orderedBlocks
        guard let index = ordered.firstIndex(where: { $0.id == block.id }) else { return false }

        let destination = index + offset
        guard ordered.indices.contains(destination) else { return false }

        // `moveBlocks` takes SwiftUI's insertion-point convention, where moving
        // down means naming the index *past* the one being displaced.
        note.moveBlocks(
            fromOffsets: IndexSet(integer: index),
            toOffset: offset > 0 ? destination + 1 : destination
        )
        note.touch()
        return true
    }

    func canMove(_ block: Block, in note: Note, by offset: Int) -> Bool {
        let ordered = note.orderedBlocks
        guard let index = ordered.firstIndex(where: { $0.id == block.id }) else { return false }
        return ordered.indices.contains(index + offset)
    }

    func delete(_ block: Block, in note: Note, context: ModelContext) {
        recovered = Deleted(
            id: block.id,
            typeRaw: block.typeRaw,
            payload: block.payload,
            position: block.position,
            noteID: note.id
        )

        note.remove(block)
        context.delete(block)
        note.touch()

        expiry?.cancel()
        expiry = Task { [recoveryWindow = Self.recoveryWindow] in
            try? await Task.sleep(for: recoveryWindow)
            guard !Task.isCancelled else { return }
            recovered = nil
        }
    }

    /// Puts it back where it was, with its original id — so a link, a sync map
    /// or a version delta that referred to it still refers to it.
    func undo(in note: Note, context: ModelContext) {
        guard let deleted = recovered, deleted.noteID == note.id else { return }

        let restored = Block(
            id: deleted.id,
            position: deleted.position,
            typeRaw: deleted.typeRaw,
            payload: deleted.payload
        )
        context.insert(restored)
        note.insert(restored, at: deleted.position)
        note.touch()

        dismiss()
    }

    func dismiss() {
        expiry?.cancel()
        expiry = nil
        recovered = nil
    }
}

// MARK: - The banner

/// The offer to undo, shown over the page.
struct BlockRecoveryBanner: View {
    let onUndo: () -> Void
    let onDismiss: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion

    var body: some View {
        HStack(spacing: Layout.Space.cosy) {
            Image(systemName: "arrow.uturn.backward")
                .foregroundStyle(theme.inkSecondary)

            Text("Block deleted")
                .versoText(.chromeBody)
                .foregroundStyle(theme.ink)

            Spacer(minLength: Layout.Space.regular)

            Button("Undo", action: onUndo)
                .versoText(.chromeLabel)
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(theme.inkTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.horizontal, Layout.Space.regular)
        .padding(.vertical, Layout.Space.cosy)
        .background(theme.card, in: .rect(cornerRadius: Layout.Radius.regular))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.Radius.regular)
                .strokeBorder(theme.rule, lineWidth: Layout.hairline)
        )
        .shadow(radius: 12, y: 4)
        .padding(.horizontal, Layout.pageMargin)
        .transition(motion.transition(.settle, motion: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Block deleted"))
    }
}

// MARK: - The menu

extension View {
    /// The long-press menu on a block.
    ///
    /// On a paragraph the text view claims the long press for its own selection
    /// menu, which is correct — you cannot edit text you cannot select. The
    /// margins around the block still reach this one.
    func blockActions(
        canMoveUp: Bool,
        canMoveDown: Bool,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void,
        duplicate: @escaping () -> Void,
        delete: @escaping () -> Void
    ) -> some View {
        contextMenu {
            if canMoveUp {
                Button {
                    moveUp()
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
            }
            if canMoveDown {
                Button {
                    moveDown()
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
            }

            Button {
                duplicate()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Button(role: .destructive) {
                delete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
