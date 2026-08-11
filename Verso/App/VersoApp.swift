import CoreSpotlight
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
    @State private var haptics = HapticEngine()
    @State private var intelligence = IntelligenceService()
    @State private var recording = RecordingSession()
    @State private var replay = ReplaySession()
    @State private var spotlight: SpotlightIndexer
    @State private var navigation = NavigationRequest.shared
    @State private var schedule: ScheduleService
    @State private var geofences: GeofenceService
    @State private var vault: VaultService

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let persistence = VersoModelContainer.makeShared()
        let authority = LocationAuthority()

        self.persistence = persistence
        _linkIndex = State(initialValue: LinkIndex(container: persistence.container))
        _schedule = State(initialValue: ScheduleService(container: persistence.container))
        _geofences = State(
            initialValue: GeofenceService(container: persistence.container, authority: authority)
        )
        _vault = State(initialValue: VaultService(container: persistence.container))
        _spotlight = State(initialValue: SpotlightIndexer(container: persistence.container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // iOS photographs the screen on the way to the background, and
                // that image is not encrypted by anything Verso does. Covering
                // it has to happen on `.inactive`, before the snapshot is
                // taken — waiting for `.background` is too late.
                .overlay {
                    if scenePhase != .active && vault.requiresPrivacyScreen {
                        PrivacyScreen()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Leaving the app closes the vault. Coming back should ask
                    // again; a vault that stays open in your pocket is a Face ID
                    // gate wearing a costume.
                    if phase == .background { vault.lock() }
                }
                .environment(vault)
                .environment(appearance)
                .environment(linkIndex)
                .environment(timers)
                .environment(userTemplates)
                .environment(haptics)
                .environment(intelligence)
                .environment(recording)
                .environment(replay)
                .environment(navigation)
                .environment(spotlight)
                // Widgets, controls and the Lock Screen all arrive as a URL.
                .onOpenURL { url in
                    switch VersoURL.destination(for: url) {
                    case .note(let id): navigation.openNote(id: id)
                    case .capture, .none: break
                    }
                }
                // Handoff from another device, and Spotlight results, resolve
                // to the same place.
                .onContinueUserActivity(VersoActivity.openNote) { activity in
                    guard let id = VersoActivity.noteID(from: activity) else { return }
                    navigation.openNote(id: id)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                          let id = UUID(uuidString: raw)
                    else { return }
                    navigation.openNote(id: id)
                }
                .environment(schedule)
                .environment(geofences)
                .environment(geofences.authority)
                .environment(\.persistenceMode, persistence.mode)
                .task {
                    // Reminders are rebuilt from the library at launch rather
                    // than trusted to have stayed in step: a note edited on
                    // another device has to take effect here too.
                    haptics.prepare()
                    await schedule.refresh()
                    await geofences.refresh()
                    // Rebuilt rather than patched: a stale Spotlight entry for
                    // a note that has since been locked is a leak, not an
                    // inconvenience.
                    await spotlight.reindex()
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
