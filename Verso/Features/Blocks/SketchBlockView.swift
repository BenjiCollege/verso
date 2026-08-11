import PencilKit
import SwiftUI

struct SketchBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(RecordingSession.self) private var recording
    @Environment(ReplaySession.self) private var replay

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<SketchPayload>) in
            InkCanvasView(
                drawing: replayedDrawing(payload) ?? payload.drawing,
                theme: theme,
                isEditable: !replay.isReplaying(blockID: block.id),
                onChange: { drawing in
                    payload.wrappedValue.height = InkTimeline.preferredHeight(for: drawing)
                    recording.sampleInk(blockID: block.id, drawing: drawing)
                    if recording.isRecording, payload.wrappedValue.recordedWith == nil {
                        payload.wrappedValue.recordedWith = recording.noteID
                    }
                },
                onStrokeTapped: replay.isPlaying ? { index in
                    replay.seek(toStrokeIndex: index, in: block.id)
                } : nil
            )
            .frame(height: payload.wrappedValue.height)
            .background(theme.inset.opacity(0.35), in: .rect(cornerRadius: Layout.Radius.tight))
            .overlay {
                if payload.wrappedValue.isEmpty && !replay.isPlaying {
                    Text("Draw here")
                        .versoText(.metadata)
                        .foregroundStyle(theme.inkTertiary)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Sketch"))
            .accessibilityValue(Text(payload.wrappedValue.isEmpty ? "Empty" : "Has a drawing"))
        }
    }

    /// While a recording plays, the canvas shows only what had been drawn by
    /// that point — section 7's "replay redraws content as it was written".
    ///
    /// The binding is read-only during replay: the canvas is showing the past,
    /// and letting somebody draw on the past would write it into the present.
    private func replayedDrawing(_ payload: Binding<SketchPayload>) -> Binding<Data>? {
        guard replay.isReplaying(blockID: block.id),
              let full = try? PKDrawing(data: payload.wrappedValue.drawing)
        else { return nil }

        let visible = replay.map.strokeIndices(visibleAt: replay.time, in: block.id)
        let limited = InkTimeline.drawing(full, limitedTo: visible).dataRepresentation()

        return Binding(get: { limited }, set: { _ in })
    }
}
