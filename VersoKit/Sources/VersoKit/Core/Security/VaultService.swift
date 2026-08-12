import CryptoKit
import Foundation
import LocalAuthentication
import OSLog
import SwiftData

/// The vault, as the app sees it.
@MainActor
@Observable
final class VaultService {

    nonisolated static let logger = Logger(subsystem: "com.verso.notes", category: "vault")

    enum State: Equatable, Sendable {
        /// No vault has been created on this device or any other.
        case notSetUp
        /// A vault exists but this device has no local key yet — a second
        /// device, before its first passphrase entry.
        case needsPassphrase
        case locked
        case unlocked
    }

    private(set) var state: State = .notSetUp
    private(set) var isWorking = false
    private(set) var lastError: String?

    /// Set while a locked note is on screen, so the app-switcher snapshot can
    /// be covered before it is taken.
    var isViewingLockedNote = false

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        refreshState()
    }

    // MARK: - State

    func refreshState() {
        if VaultKeyring.shared.isUnlocked {
            state = .unlocked
        } else if VaultKeychain.hasLocalKey() {
            state = .locked
        } else if VaultKeychain.loadWrapped() != nil {
            state = .needsPassphrase
        } else {
            state = .notSetUp
        }
    }

    var biometry: (isAvailable: Bool, type: LABiometryType) {
        VaultKeychain.biometryAvailability()
    }

    var biometryName: String {
        switch biometry.type {
        case .faceID: String(localized: "Face ID")
        case .touchID: String(localized: "Touch ID")
        case .opticID: String(localized: "Optic ID")
        default: String(localized: "biometrics")
        }
    }

    var requiresPrivacyScreen: Bool {
        VaultPolicy.requiresPrivacyScreen(
            isViewingLockedNote: isViewingLockedNote,
            isVaultUnlocked: state == .unlocked
        )
    }

    // MARK: - Setup

    /// Creates a vault.
    ///
    /// The key is generated here and immediately wrapped with the passphrase.
    /// Both halves are stored before anything is reported as successful — a
    /// vault whose key exists only on one device, with no passphrase copy,
    /// would be one lost phone away from unrecoverable.
    func setUp(passphrase: String) async {
        await perform {
            let key = SymmetricKey(size: .bits256)
            let wrapped = try WrappedVaultKey.wrap(key, passphrase: passphrase)

            try VaultKeychain.storeWrapped(wrapped)
            do {
                try VaultKeychain.storeLocalKey(key)
            } catch {
                // No biometrics on this device is not a failure: the passphrase
                // still opens it, every time.
                Self.logger.notice("Vault created without a biometric key: \(error.localizedDescription, privacy: .public)")
            }

            VaultKeyring.shared.unlock(with: key)
        }
    }

    // MARK: - Unlocking

    func unlockWithBiometrics() async {
        await perform {
            let reason = String(localized: "Open your locked notes")
            // The keychain read puts up the system prompt and blocks until the
            // user answers it, so it cannot run on the main actor.
            let key = try await Task.detached(priority: .userInitiated) {
                try VaultKeychain.loadLocalKey(reason: reason)
            }.value
            VaultKeyring.shared.unlock(with: key)
        }
    }

    /// Opens the vault with the passphrase, and adopts it on this device.
    ///
    /// Storing the local key afterwards is what turns a second device from
    /// "type the passphrase every time" into "Face ID from now on".
    func unlockWithPassphrase(_ passphrase: String) async {
        await perform {
            guard let wrapped = VaultKeychain.loadWrapped() else { throw VaultError.notSetUp }

            let key = try await Task.detached(priority: .userInitiated) {
                try wrapped.unwrap(passphrase: passphrase)
            }.value

            VaultKeyring.shared.unlock(with: key)
            try? VaultKeychain.storeLocalKey(key)
        }
    }

    func lock() {
        VaultKeyring.shared.lock()
        isViewingLockedNote = false
        leftAt = nil
        refreshState()
    }

    // MARK: - Leaving and coming back

    /// How long the vault survives the app going away.
    ///
    /// Locking the instant the app backgrounds is correct against someone
    /// picking up the phone, and wrong against every other reason you leave:
    /// checking a date, copying an address, answering a message. A Face ID
    /// prompt for each of those is how a feature gets turned off, and a vault
    /// nobody turns on protects nothing.
    ///
    /// A minute is short enough that the phone has not changed hands and long
    /// enough to cover an errand. It is deliberately not a setting — a security
    /// window is not something to make people guess at.
    static let graceWindow: TimeInterval = 60

    private var leftAt: Date?

    /// Called when the app stops being frontmost. The vault stays open, on the
    /// clock.
    func applicationWillResign(now: Date = Date()) {
        guard VaultKeyring.shared.isUnlocked else { return }
        leftAt = now
    }

    /// Called on return. Locks if the app was away longer than the grace, and
    /// the privacy screen has covered the gap either way.
    func applicationDidBecomeActive(now: Date = Date()) {
        guard let leftAt else { return }
        if now.timeIntervalSince(leftAt) > Self.graceWindow {
            lock()
        } else {
            self.leftAt = nil
        }
    }

    // MARK: - Notes

    /// Locks a note: every block payload is encrypted in place.
    ///
    /// Ordered so the ciphertext is written before `isLocked` is set. If this
    /// were interrupted the note would still be readable, which is the safe way
    /// round — the alternative is a note flagged locked whose contents are
    /// plaintext.
    func lockNote(_ note: Note) throws {
        guard VaultKeyring.shared.isUnlocked else { throw VaultError.noKey }

        for block in note.orderedBlocks where !block.isSealed {
            block.payload = try VaultKeyring.shared.seal(block.payload)
        }
        note.isLocked = true
        note.touch()

        // History is the note too. A version holding yesterday's plaintext
        // would make locking cosmetic.
        for version in note.versions ?? [] where !VaultCipher.isSealed(version.snapshot) {
            version.snapshot = try VaultKeyring.shared.seal(version.snapshot)
        }
    }

    func unlockNote(_ note: Note) throws {
        guard VaultKeyring.shared.isUnlocked else { throw VaultError.noKey }

        note.isLocked = false
        for block in note.orderedBlocks where block.isSealed {
            block.payload = try VaultKeyring.shared.open(block.payload)
        }
        for version in note.versions ?? [] where VaultCipher.isSealed(version.snapshot) {
            version.snapshot = try VaultKeyring.shared.open(version.snapshot)
        }
        note.touch()
    }

    /// Removes the vault and everything in it.
    ///
    /// Deliberately does *not* try to decrypt the notes first: if the user is
    /// doing this because they forgot the passphrase, there is nothing to
    /// decrypt with, and pretending otherwise would lose the data twice.
    func destroyVault() {
        VaultKeychain.deleteLocalKey()
        VaultKeychain.deleteWrapped()
        VaultKeyring.shared.lock()
        refreshState()
    }

    // MARK: - Private

    private func perform(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        lastError = nil
        defer {
            isWorking = false
            refreshState()
        }

        do {
            try await work()
        } catch let error as VaultError {
            lastError = error.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }
}
