import SwiftData
import SwiftUI

@main
struct VersoApp: App {

    /// Built once, at launch. `makeShared` never throws — it degrades from
    /// CloudKit to local-only to in-memory and reports which, so a user with no
    /// iCloud account or a full one still gets a working app.
    private let persistence: VersoModelContainer.Result

    @State private var appearance = AppearanceStore()
    @State private var linkIndex: LinkIndex

    /// Running timers are app state, not note state: a rest timer counting down
    /// on your phone must not start counting on your iPad.
    @State private var timers = RestTimerService()
    @State private var userTemplates = UserTemplateStore()
    @State private var schedule: ScheduleService
    @State private var geofences: GeofenceService

    init() {
        let persistence = VersoModelContainer.makeShared()
        let authority = LocationAuthority()

        self.persistence = persistence
        _linkIndex = State(initialValue: LinkIndex(container: persistence.container))
        _schedule = State(initialValue: ScheduleService(container: persistence.container))
        _geofences = State(
            initialValue: GeofenceService(container: persistence.container, authority: authority)
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appearance)
                .environment(linkIndex)
                .environment(timers)
                .environment(userTemplates)
                .environment(schedule)
                .environment(geofences)
                .environment(geofences.authority)
                .environment(\.persistenceMode, persistence.mode)
                .task {
                    // Reminders are rebuilt from the library at launch rather
                    // than trusted to have stayed in step: a note edited on
                    // another device has to take effect here too.
                    await schedule.refresh()
                    await geofences.refresh()
                }
        }
        .modelContainer(persistence.container)
    }
}

extension EnvironmentValues {
    /// How the store was actually created, so Settings can tell the truth about
    /// syncing instead of implying it works.
    @Entry var persistenceMode: VersoModelContainer.Mode = .cloudKit
}
