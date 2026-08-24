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
            .accessibilityValue(Text(accessibilityValue(for: payload.wrappedValue)))
            // Read the handwriting once the pen has been still for a moment.
            //
            // Keyed on the drawing, so a new stroke cancels the pending read
            // and starts the wait again: recognising per stroke would run
            // Vision over the whole page on every flick of the pencil, and the
            // answer would be thrown away a tenth of a second later anyway.
            //
            // Replay is excluded — the canvas is showing the past, and the
            // drawing it displays is not the one the block owns.
            .task(id: payload.wrappedValue.drawing) {
                guard !replay.isReplaying(blockID: block.id) else { return }
                await recogniseHandwriting(in: payload)
            }
        }
    }

    /// How long the pen must be still before the page is read.
    private static let recognitionDelay = Duration.milliseconds(1_200)

    /// Reads the ink and stores the words on the payload.
    ///
    /// Cancellation is the debounce: `task(id:)` tears this down the instant
    /// another stroke lands, so the sleep is what makes a fast scribble cost
    /// one recognition instead of forty.
    private func recogniseHandwriting(in payload: Binding<SketchPayload>) async {
        let data = payload.wrappedValue.drawing
        guard !data.isEmpty else {
            // Erased back to nothing: drop the stale words with the ink, or the
            // note stays findable by handwriting that is no longer on the page.
            if !payload.wrappedValue.recognisedText.isEmpty {
                payload.wrappedValue.recognisedText = ""
            }
            return
        }

        try? await Task.sleep(for: Self.recognitionDelay)
        guard !Task.isCancelled, let drawing = try? PKDrawing(data: data) else { return }

        let text = await InkRecognition.text(in: drawing)
        guard !Task.isCancelled else { return }

        // Only write when it actually changed. A sketch is saved through a
        // binding onto the model, and rewriting the same string would dirty the
        // note — and with it its modified date, and with that its place in the
        // library — every time somebody merely looked at the page.
        if payload.wrappedValue.recognisedText != text {
            payload.wrappedValue.recognisedText = text
        }
    }

    private func accessibilityValue(for payload: SketchPayload) -> LocalizedStringResource {
        if payload.isEmpty { return "Empty" }
        // VoiceOver gets the recognised words when there are any: a canvas that
        // announces only "has a drawing" tells somebody who cannot see it
        // nothing at all about what is on the page.
        guard payload.recognisedText.isEmpty else {
            return "Handwriting: \(payload.recognisedText)"
        }
        return "Has a drawing"
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
