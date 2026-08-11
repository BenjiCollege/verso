import AppIntents
import SwiftUI
import WidgetKit

/// The Control Centre control, which is also what the Action Button and the
/// Lock Screen offer.
///
/// One control, one job. A control that needs a decision made before it does
/// anything is a control nobody adds.
public struct VersoCaptureControl: ControlWidget {

    public init() {}

    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "VersoCapture") {
            ControlWidgetButton(action: StartRecordingIntent()) {
                Label("Record a Note", systemImage: "mic")
            }
        }
        .displayName("Record a Note")
        .description("Opens Verso and starts recording straight away.")
    }
}
