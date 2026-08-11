import Foundation
import OSLog
import SwiftData

/// Builds the app's single `ModelContainer`.
///
/// Every rule in section 4 of CLAUDE.md that CloudKit imposes on the schema —
/// no `.unique`, defaults or optionals everywhere, optional inverse-declared
/// relationships, `.externalStorage` for blobs — is enforced in the model
/// files themselves. `SchemaValidityTests` asserts them so a violation fails
/// the test suite rather than the first sync.
enum VersoModelContainer {

    static let cloudKitContainerIdentifier = "iCloud.com.verso.notes"

    static let logger = Logger(subsystem: "com.verso.notes", category: "persistence")

    /// The models that make up the store. Order is irrelevant but stability is
    /// not — adding one here is a schema change and needs a migration plan.
    static let schema = Schema([
        Note.self,
        Block.self,
        MetricEntry.self,
        Version.self,
        AudioAsset.self,
        Folder.self,
        Tag.self,
    ])

    /// How the store ended up being created. Surfaced in Settings so a user
    /// whose notes are silently not syncing can find out why.
    enum Mode: Equatable, Sendable {
        case cloudKit
        case localOnly(reason: String)
    }

    struct Result: Sendable {
        let container: ModelContainer
        let mode: Mode
    }

    /// Attempts a CloudKit-backed store and falls back to a local-only store if
    /// that fails. A missing or full iCloud account does *not* land here —
    /// SwiftData still builds the container and simply stops syncing — but a
    /// misconfigured entitlement or unreadable store file does.
    /// The app group the widget and the intent extensions read through.
    ///
    /// Both run in their own processes, so the store has to live somewhere all
    /// three can reach. Declared in `Verso.entitlements`.
    static let appGroupIdentifier = "group.com.verso.notes"

    /// Whether this process can actually reach the app group.
    ///
    /// Asked rather than assumed because SwiftData does not *throw* when a
    /// configuration names a group container the process has no entitlement
    /// for — it calls `fatalError` from inside `ModelContainer.init`, so none
    /// of the fallbacks below ever get the chance to run. `containerURL(for…)`
    /// returns nil in exactly that case and is the only survivable way to ask.
    ///
    /// In a correctly signed build this is always true. It is false in an
    /// unsigned build — CI's simulator run, chiefly — where a hard crash at
    /// launch would be a much worse answer than a store on the local device.
    /// `scripts/verify-entitlements.sh` is what catches the case that matters,
    /// a *release* build that lost the entitlement; this is not a substitute
    /// for it, which is why it logs at error level rather than passing quietly.
    static let isAppGroupAvailable: Bool = {
        guard FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil
        else {
            logger.error("""
                App group \(appGroupIdentifier, privacy: .public) is unreachable. \
                Falling back to a store this process alone can see: widgets and \
                intents will not observe these notes.
                """)
            return false
        }
        return true
    }()

    /// The one true configuration. Used by the app, the widgets and App Intents
    /// alike, so there is no way for them to end up looking at different stores.
    static var sharedConfiguration: ModelConfiguration {
        configuration(syncing: true)
    }

    private static func configuration(syncing: Bool) -> ModelConfiguration {
        ModelConfiguration(
            "Verso",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: isAppGroupAvailable ? .identifier(appGroupIdentifier) : .none,
            cloudKitDatabase: syncing ? .private(cloudKitContainerIdentifier) : .none
        )
    }

    static func makeShared() -> Result {
        // No app group means no entitlements at all, and so no iCloud container
        // either. Attempting CloudKit here would only be a slower way to arrive
        // at the same local store.
        if isAppGroupAvailable {
            do {
                let container = try ModelContainer(for: schema, configurations: [sharedConfiguration])
                return Result(container: container, mode: .cloudKit)
            } catch {
                logger.error("CloudKit-backed store unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }

        let localConfiguration = configuration(syncing: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [localConfiguration])
            return Result(
                container: container,
                mode: .localOnly(reason: String(localized: "iCloud sync is unavailable. Your notes are saved on this device."))
            )
        } catch {
            logger.fault("Local store unavailable: \(error.localizedDescription, privacy: .public)")
        }

        // Last resort: an in-memory store. The app stays usable and read-only
        // work is not lost mid-session, but nothing survives relaunch. The
        // banner this drives is deliberately alarming.
        do {
            let container = try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
            return Result(
                container: container,
                mode: .localOnly(reason: String(localized: "Storage is unavailable. Notes made now will not be saved."))
            )
        } catch {
            fatalError("Unable to create any ModelContainer: \(error)")
        }
    }

    static let inMemoryConfiguration = ModelConfiguration(
        "VersoMemory",
        schema: schema,
        isStoredInMemoryOnly: true,
        allowsSave: true,
        cloudKitDatabase: .none
    )

    /// For tests and SwiftUI previews. Never touches iCloud or disk.
    static func makeInMemory() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
    }
}
