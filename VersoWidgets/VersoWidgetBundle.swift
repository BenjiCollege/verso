import SwiftUI
import WidgetKit

@main
struct VersoWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecentNotesWidget()
        QuickCaptureWidget()
        VersoCaptureControl()
    }
}
