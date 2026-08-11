import CryptoKit
import Foundation

/// The cipher, reachable from wherever a block payload is read or written.
///
/// Encryption has to happen *before* the bytes reach SwiftData, and payloads
/// are read and written from `Block` — a model with no way to be handed a
/// service. Threading a cipher through every call site would put the burden on
/// every future caller to remember it, which is exactly how a plaintext leak
/// gets written.
///
/// So: one process-wide holder. `@unchecked Sendable` because the stored key is
/// guarded by a lock rather than by the compiler — every access goes through
/// `withKey`, and the key itself is a value type that is copied out.
final class VaultKeyring: @unchecked Sendable {

    static let shared = VaultKeyring()

    /// Named `mutex` rather than `lock`, because `lock()` is also the method
    /// that forgets the key — and `lock.lock()` inside `func lock()` is an
    /// invalid redeclaration, not a clever pun.
    private let mutex = NSLock()
    private var key: SymmetricKey?

    private init() {}

    var isUnlocked: Bool {
        mutex.lock()
        defer { mutex.unlock() }
        return key != nil
    }

    func unlock(with key: SymmetricKey) {
        mutex.lock()
        defer { mutex.unlock() }
        self.key = key
    }

    /// Forgets the key. The ciphertext stays exactly where it was.
    func lock() {
        mutex.lock()
        defer { mutex.unlock() }
        key = nil
    }

    private func withKey<T>(_ body: (SymmetricKey) throws -> T) throws -> T {
        mutex.lock()
        let current = key
        mutex.unlock()

        guard let current else { throw VaultError.noKey }
        return try body(current)
    }

    /// Encrypts, if the vault is open. Called on the way into the store.
    func seal(_ data: Data) throws -> Data {
        try withKey { try VaultCipher(key: $0).seal(data) }
    }

    /// Decrypts, if the payload is sealed and the vault is open.
    ///
    /// Plaintext passes straight through, so callers never have to ask which
    /// kind they are holding — and a sealed payload with the vault closed
    /// throws rather than returning something plausible.
    func open(_ data: Data) throws -> Data {
        guard VaultCipher.isSealed(data) else { return data }
        return try withKey { try VaultCipher(key: $0).open(data) }
    }

    /// Best-effort, for the read paths that must never throw — previews,
    /// titling, the fore-edge. A locked note simply has nothing to show.
    func openIfPossible(_ data: Data) -> Data? {
        try? open(data)
    }
}

/// What may leave the app.
///
/// Section 7: locked and hidden notes are excluded from `CSSearchableIndex`,
/// widgets, share previews, and the app-switcher snapshot. One place decides,
/// so the answer cannot drift between four of them.
enum VaultPolicy {

    /// Spotlight, widgets, Siri suggestions — anything that surfaces a note
    /// outside the app.
    static func isEligibleForIndexing(_ note: Note) -> Bool {
        !note.isLocked && !note.isHidden && !note.isTrashed
    }

    /// Export and share. A locked note cannot be shared even while the vault
    /// is open: the point of locking it was to keep it in.
    static func isEligibleForSharing(_ note: Note) -> Bool {
        !note.isLocked
    }

    /// Whether the app-switcher snapshot has to be covered.
    static func requiresPrivacyScreen(isViewingLockedNote: Bool, isVaultUnlocked: Bool) -> Bool {
        isViewingLockedNote && isVaultUnlocked
    }

    /// What a locked note is allowed to say about itself in a list.
    static func listTitle(for note: Note) -> String {
        note.isLocked ? String(localized: "Locked note") : note.title
    }

    static func listPreview(for note: Note, registry: BlockRegistry = .shared) -> String {
        guard !note.isLocked else { return "" }
        for block in note.orderedBlocks {
            let text = registry.plainText(for: block).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text.replacingOccurrences(of: "\n", with: " · ") }
        }
        return ""
    }
}
