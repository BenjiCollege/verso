import AppIntents
import SwiftUI
import VersoKit
import WidgetKit

/// The extension target holds `@main` and nothing else.
///
/// The widgets themselves live in `VersoKit`, which is also what gives them the
/// store, the vault policy and the intents — the same code the app runs, rather
/// than a second copy that can drift.
@main
struct VersoWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecentNotesWidget()
        QuickCaptureWidget()
        VersoCaptureControl()
        TimerLiveActivityWidget()
    }
}

/// The Control Centre button runs `StartRecordingIntent`, which lives in the
/// package — so the extension has to say it includes the package's intents for
/// the same reason the app does.
struct VersoWidgetsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [VersoKitPackage.self]
    }
}
