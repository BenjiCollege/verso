import SwiftData
import SwiftUI

@main
struct VersoApp: App {

    /// Built once, at launch. `makeShared` never throws — it degrades from
    /// CloudKit to local-only to in-memory and reports which, so a user with no
    /// iCloud account or a full one still gets a working app.
    private let persistence = VersoModelContainer.makeShared()

    @State private var appearance = AppearanceStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appearance)
                .environment(\.persistenceMode, persistence.mode)
        }
        .modelContainer(persistence.container)
    }
}

extension EnvironmentValues {
    /// How the store was actually created, so Settings can tell the truth about
    /// syncing instead of implying it works.
    @Entry var persistenceMode: VersoModelContainer.Mode = .cloudKit
}
