import PencilKit
import SwiftUI

/// The drawing surface.
///
/// Apple Pencil Pro's squeeze and double-tap are handled through
/// `UIPencilInteraction`, whose preferred actions the user sets in Settings —
/// so a double-tap that they configured as "switch to eraser" does that here
/// too, rather than whatever this app would have chosen.
struct InkCanvasView: UIViewRepresentable {

    @Binding var drawing: Data
    let theme: Theme
    let isEditable: Bool
    /// Called on every change, so a recording can timestamp the strokes.
    let onChange: (PKDrawing) -> Void
    /// A tap on ink while a recording is playing seeks to when it was drawn.
    let onStrokeTapped: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // Finger as well as Pencil: a note is often opened without one to hand.
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = false
        canvas.isScrollEnabled = false

        let interaction = UIPencilInteraction()
        interaction.delegate = context.coordinator
        canvas.addInteraction(interaction)

        // Hover preview: the tool follows the Pencil before it lands, which is
        // what makes precise placement possible on a page with rules on it.
        let hover = UIHoverGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.hoverChanged(_:))
        )
        canvas.addGestureRecognizer(hover)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.tapped(_:))
        )
        tap.isEnabled = onStrokeTapped != nil
        canvas.addGestureRecognizer(tap)
        context.coordinator.tapRecogniser = tap

        context.coordinator.apply(drawing, to: canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.isUserInteractionEnabled = isEditable
        context.coordinator.tapRecogniser?.isEnabled = onStrokeTapped != nil
        context.coordinator.apply(drawing, to: canvas)
        context.coordinator.applyTool(to: canvas, theme: theme)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {

        var parent: InkCanvasView
        var tapRecogniser: UITapGestureRecognizer?

        private var lastApplied: Data?
        private var isErasing = false
        private var inkColour: UIColor?

        init(parent: InkCanvasView) {
            self.parent = parent
        }

        /// Only rewrites the canvas when the bytes actually changed — assigning
        /// a drawing mid-stroke would interrupt the stroke being drawn.
        func apply(_ data: Data, to canvas: PKCanvasView) {
            guard lastApplied != data else { return }
            lastApplied = data

            if data.isEmpty {
                canvas.drawing = PKDrawing()
            } else if let drawing = try? PKDrawing(data: data) {
                canvas.drawing = drawing
            }
        }

        /// Ink is the note's own ink. A drawing made on `foxed` paper and later
        /// read on `midnight-oil` would otherwise be invisible.
        func applyTool(to canvas: PKCanvasView, theme: Theme) {
            let colour = UIColor(theme.ink)
            guard inkColour != colour || isErasing != (canvas.tool is PKEraserTool) else { return }
            inkColour = colour
            canvas.tool = isErasing
                ? PKEraserTool(.bitmap)
                : PKInkingTool(.pen, color: colour, width: 3)
        }

        // MARK: - PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let data = canvasView.drawing.dataRepresentation()
            lastApplied = data
            parent.drawing = data
            parent.onChange(canvasView.drawing)
        }

        // MARK: - Apple Pencil Pro

        /// The modern callback, which reports which action the user configured.
        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
        ) {
            guard squeeze.phase == .ended else { return }
            perform(UIPencilInteraction.preferredSqueezeAction, on: interaction.view as? PKCanvasView)
        }

        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveTap tap: UIPencilInteraction.Tap
        ) {
            perform(UIPencilInteraction.preferredTapAction, on: interaction.view as? PKCanvasView)
        }

        /// Honouring the system preference rather than inventing a mapping is
        /// the whole point: the user already told iOS what a double-tap means.
        private func perform(_ action: UIPencilPreferredAction, on canvas: PKCanvasView?) {
            guard let canvas else { return }

            switch action {
            case .switchEraser, .switchPrevious:
                isErasing.toggle()
                inkColour = nil
                applyTool(to: canvas, theme: parent.theme)
            case .showColorPalette, .showInkAttributes, .runSystemShortcut:
                canvas.becomeFirstResponder()
            default:
                break
            }
        }

        // MARK: - Hover and tap

        @objc func hoverChanged(_ recogniser: UIHoverGestureRecognizer) {
            guard let canvas = recogniser.view as? PKCanvasView else { return }
            // A faint lift while the Pencil is overhead, so it is obvious which
            // block will take the stroke.
            let isHovering = recogniser.state == .began || recogniser.state == .changed
            UIView.animate(withDuration: 0.15) {
                canvas.alpha = isHovering ? 1.0 : 0.98
            }
        }

        @objc func tapped(_ recogniser: UITapGestureRecognizer) {
            guard let canvas = recogniser.view as? PKCanvasView,
                  let handler = parent.onStrokeTapped
            else { return }

            let point = recogniser.location(in: canvas)
            guard let index = InkTimeline.nearestStrokeIndex(to: point, in: canvas.drawing) else { return }
            handler(index)
        }
    }
}
