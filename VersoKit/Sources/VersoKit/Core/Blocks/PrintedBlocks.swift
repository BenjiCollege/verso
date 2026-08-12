import PencilKit
import SwiftUI

/// How a block is drawn.
enum BlockPresentation: Sendable {
    /// The editor: gestures, focus, live services.
    case interactive
    /// A flat drawing of the same content, for export.
    case printed
}

// MARK: - Printed blocks

/// Blocks drawn flat, for PDF and image export.
///
/// Two separate things rule out reusing the editors, and both are silent in
/// different ways.
///
/// `ImageRenderer` cannot draw a `UIViewRepresentable` at all — Apple's
/// documentation is explicit — so a paragraph, which is TextKit 2 inside a
/// `UITextView`, would export as a blank space with no error anywhere.
///
/// And eight of the editors read environment objects: the recording session,
/// the timer service, the geofence service, the haptic engine. An export has no
/// reason to build any of those, and a missing `@Environment` observable is a
/// *trap*, not a nil. That is what crashed the app on PDF share — a note
/// holding a checklist, a paragraph or a timer was enough, which is nearly all
/// of them.
///
/// So these decode the payload and draw it. No gestures, no state, and nothing
/// read from the environment but the theme.
enum Printed {

    struct TextBlock: View {
        let block: Block
        @Environment(\.theme) private var theme

        var body: some View {
            let payload = try? block.decoded(as: TextPayload.self)
            // `attributed` already falls back to `plain` when the archive is
            // unreadable, so a corrupt run exports as legible text.
            Text(payload?.attributed ?? "")
                .versoText(.body)
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct ChecklistBlock: View {
        let block: Block
        @Environment(\.theme) private var theme

        var body: some View {
            let payload = try? block.decoded(as: ChecklistPayload.self)
            VStack(alignment: .leading, spacing: Layout.Space.tight) {
                ForEach(payload?.items ?? []) { item in
                    HStack(alignment: .firstTextBaseline, spacing: Layout.Space.tight) {
                        Image(systemName: item.checked ? "checkmark.square" : "square")
                            .foregroundStyle(item.checked ? theme.accent : theme.inkSecondary)
                        Text(item.label)
                            .versoText(.body)
                            .strikethrough(item.checked, color: theme.inkSecondary)
                            .foregroundStyle(item.checked ? theme.inkSecondary : theme.ink)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct MetricBlock: View {
        let block: Block
        @Environment(\.theme) private var theme

        var body: some View {
            let payload = try? block.decoded(as: MetricPayload.self)
            LabelledValue(
                label: payload?.label ?? "",
                value: payload.flatMap(\.value).map {
                    $0.formatted(.number.precision(.fractionLength(0...2)))
                } ?? "—",
                unit: payload?.unit ?? ""
            )
            .environment(\.theme, theme)
        }
    }

    struct TimerBlock: View {
        let block: Block

        var body: some View {
            let payload = try? block.decoded(as: TimerPayload.self)
            LabelledValue(
                label: payload?.label ?? "",
                value: payload?.duration.timerClockText ?? "",
                unit: ""
            )
        }
    }

    struct ScheduleBlock: View {
        let block: Block

        var body: some View {
            let payload = try? block.decoded(as: SchedulePayload.self)
            LabelledValue(
                label: payload?.label ?? "",
                value: payload?.dueAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "",
                unit: ""
            )
        }
    }

    struct PlaceBlock: View {
        let block: Block
        @Environment(\.theme) private var theme

        var body: some View {
            let payload = try? block.decoded(as: PlacePayload.self)
            HStack(alignment: .firstTextBaseline, spacing: Layout.Space.tight) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(theme.accent)
                Text(payload?.name ?? "")
                    .versoText(.body)
                    .foregroundStyle(theme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The drawing, rasterised. `PKCanvasView` is a `UIView`, so the live one
    /// would export as nothing at all.
    struct SketchBlock: View {
        let block: Block
        @Environment(\.theme) private var theme

        var body: some View {
            let payload = try? block.decoded(as: SketchPayload.self)
            let height = payload.map { CGFloat($0.height) } ?? 200

            Group {
                if let image = rasterised(payload) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func rasterised(_ payload: SketchPayload?) -> UIImage? {
            guard let payload, !payload.drawing.isEmpty,
                  let drawing = try? PKDrawing(data: payload.drawing)
            else { return nil }

            let bounds = drawing.bounds
            guard bounds.width > 0, bounds.height > 0, bounds.width.isFinite, bounds.height.isFinite
            else { return nil }
            return drawing.image(from: bounds, scale: 2)
        }
    }

    struct AudioBlock: View {
        let block: Block
        @Environment(\.theme) private var theme

        var body: some View {
            // The recording itself cannot travel in a PDF, so the block prints
            // as a note that one exists rather than as a dead player.
            HStack(alignment: .firstTextBaseline, spacing: Layout.Space.tight) {
                Image(systemName: "waveform")
                    .foregroundStyle(theme.accent)
                Text("Audio recording")
                    .versoText(.footnote)
                    .foregroundStyle(theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The shape the value-carrying blocks share: a name and what it holds.
    private struct LabelledValue: View {
        let label: String
        let value: String
        let unit: String

        @Environment(\.theme) private var theme

        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .versoText(.body)
                    .foregroundStyle(theme.ink)
                Spacer(minLength: Layout.Space.regular)
                Text(unit.isEmpty ? value : "\(value) \(unit)")
                    .versoText(.body)
                    .foregroundStyle(theme.inkSecondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
