import SwiftUI

/// Bridges a stored `Block` and a typed payload editor.
///
/// Decoding happens once, when the view is created; every mutation through the
/// binding re-encodes and stamps the note's modification date. Views built on
/// this never touch `Block.payload` or `BlockCoding` themselves.
struct BlockPayloadEditor<P: BlockPayload, Content: View>: View {

    private let block: Block
    private let content: (Binding<P>) -> Content

    @State private var payload: P

    init(block: Block, @ViewBuilder content: @escaping (Binding<P>) -> Content) {
        self.block = block
        self.content = content
        // A payload that fails to decode is replaced with a default rather than
        // rendering nothing — the block stays visible and editable, and the
        // unreadable bytes are only overwritten if the user actually edits.
        _payload = State(initialValue: (try? block.decoded(as: P.self)) ?? P.makeDefault())
    }

    var body: some View {
        content($payload)
            .onChange(of: payload) { _, newValue in
                try? block.store(newValue)
                block.note?.touch()
            }
    }
}
