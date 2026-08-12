import CoreSpotlight
import WidgetKit
import SwiftData
import SwiftUI

/// The whole app, as one scene.
///
/// This is the app half of `VersoKit`'s public boundary — the other half is the
/// three widgets. Everything else in the package is internal, so what the app
/// target can reach is a decision rather than an accident of what happened to
/// be visible.
///
/// The `@main` declaration itself has to live in the app target; this is
/// everything it would otherwise have contained.
public struct VersoScene: Scene {

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
    @State private var customThemes = CustomThemeStore()
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

    public init() {
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

    public var body: some Scene {
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
                    // Leaving the app starts the vault's clock rather than
                    // closing it outright. Long enough away and it locks; a
                    // glance at something else and it does not. The privacy
                    // screen covers the gap either way, so nothing is on show
                    // in the app switcher during the grace.
                    switch phase {
                    case .active: vault.applicationDidBecomeActive()
                    case .inactive, .background: vault.applicationWillResign()
                    @unknown default: vault.lock()
                    }

                    // The widget's own timeline refreshes half-hourly, which is
                    // the right budget for a clock and the wrong one for notes:
                    // it meant the Home Screen showed what you wrote up to half
                    // an hour ago. Leaving the app is exactly when the widget
                    // starts mattering and the app stops, so it is the moment
                    // worth spending a reload on.
                    if phase != .active { WidgetCenter.shared.reloadAllTimelines() }
                }
                .environment(vault)
                .environment(appearance)
                .environment(linkIndex)
                .environment(timers)
                .environment(userTemplates)
                .environment(customThemes)
                .environment(haptics)
                .environment(intelligence)
                .environment(recording)
                .environment(replay)
                .environment(navigation)
                .environment(spotlight)
                // Widgets, controls and the Lock Screen all arrive as a URL.
                .onOpenURL { url in
                    // A `.versotemplate` opened from Files, Mail or AirDrop
                    // arrives here as a file URL rather than a verso:// one.
                    // `Info.plist` declares Verso the owner of the type, so
                    // falling through to `VersoURL` — which resolves a file URL
                    // to nothing — meant the system handing the app a file it
                    // then silently dropped.
                    if url.isFileURL {
                        guard url.pathExtension == UserTemplateStore.fileExtension,
                              let template = userTemplates.importTemplate(from: url)
                        else { return }
                        navigation.templateArrived(named: template.name)
                        return
                    }

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
