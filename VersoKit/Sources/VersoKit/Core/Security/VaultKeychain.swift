import CryptoKit
import Foundation
import LocalAuthentication
import OSLog
import Security

/// Where the vault key lives.
///
/// Two items, deliberately:
///
/// - **Local.** The raw key, `WhenUnlockedThisDeviceOnly` and behind a
///   `SecAccessControl` requiring `.biometryCurrentSet`. It never leaves the
///   device, never appears in a backup, and is destroyed by the system if the
///   enrolled fingerprints or faces change — so a coerced enrolment does not
///   inherit the vault.
/// - **Synchronizable.** The *passphrase-wrapped* key, which iCloud Keychain
///   carries between the user's devices end-to-end encrypted. That is how a
///   locked note opens on another device, per section 7. It syncs safely
///   because without the passphrase it is noise — and biometry-bound items
///   cannot sync at all, which is why there have to be two.
enum VaultKeychain {

    static let logger = Logger(subsystem: "com.verso.notes", category: "vault")

    private static let service = "com.verso.notes.vault"
    private static let localAccount = "vault-key"
    private static let wrappedAccount = "vault-key-wrapped"

    // MARK: - Local, biometry-bound

    static func storeLocalKey(_ key: SymmetricKey) throws {
        deleteLocalKey()

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw VaultError.biometricsUnavailable
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: localAccount,
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
            kSecAttrAccessControl as String: access,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychainFailure(status) }
    }

    /// Reads the key, prompting for biometrics.
    ///
    /// Blocking: `SecItemCopyMatching` puts up the system prompt and waits, so
    /// this must never be called on the main actor. `VaultService` runs it on a
    /// detached task.
    static func loadLocalKey(reason: String) throws -> SymmetricKey {
        let context = LAContext()
        context.localizedReason = reason
        // No "Enter Password" escape hatch: the device passcode is not the
        // vault passphrase, and offering it would imply otherwise.
        context.localizedFallbackTitle = ""

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: localAccount,
            kSecReturnData as String: true,
            // The reason travels on the `LAContext` above. `kSecUseOperationPrompt`
            // was the pre-iOS 14 way to say the same thing and is deprecated;
            // passing both would just be two spellings of one string.
            kSecUseAuthenticationContext as String: context,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw VaultError.noKey }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            throw VaultError.notSetUp
        case errSecUserCanceled, errSecAuthFailed:
            throw VaultError.biometricsFailed
        default:
            throw VaultError.keychainFailure(status)
        }
    }

    /// Whether a key exists — *without* putting a Face ID prompt in front of
    /// someone who has only opened the app.
    ///
    /// `LAContext.interactionNotAllowed` is the iOS 14 replacement for
    /// `kSecUseAuthenticationUI: fail`, and means the same thing: a lookup that
    /// would need the user answers `errSecInteractionNotAllowed` instead of
    /// asking. That status is the *success* case here — it says the item is
    /// there and guarded. Only `errSecItemNotFound` means no key.
    static func hasLocalKey() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: localAccount,
            kSecUseAuthenticationContext as String: context,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    @discardableResult
    static func deleteLocalKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: localAccount,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Synchronizable, passphrase-wrapped

    static func storeWrapped(_ wrapped: WrappedVaultKey) throws {
        deleteWrapped()

        let data = try JSONEncoder().encode(wrapped)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: wrappedAccount,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychainFailure(status) }
    }

    static func loadWrapped() -> WrappedVaultKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: wrappedAccount,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }

        return try? JSONDecoder().decode(WrappedVaultKey.self, from: data)
    }

    @discardableResult
    static func deleteWrapped() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: wrappedAccount,
            kSecAttrSynchronizable as String: true,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Capability

    static func biometryAvailability() -> (isAvailable: Bool, type: LABiometryType) {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return (available, context.biometryType)
    }
}
