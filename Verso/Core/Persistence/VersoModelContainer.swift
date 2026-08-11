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
    static func makeShared() -> Result {
        let cloudConfiguration = ModelConfiguration(
            "Verso",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [cloudConfiguration])
            return Result(container: container, mode: .cloudKit)
        } catch {
            logger.error("CloudKit-backed store unavailable: \(error.localizedDescription, privacy: .public)")
        }

        let localConfiguration = ModelConfiguration(
            "Verso",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )

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
