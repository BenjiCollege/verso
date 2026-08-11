import CommonCrypto
import CryptoKit
import Foundation

/// Deriving a key from a passphrase.
///
/// PBKDF2-HMAC-SHA256 via CommonCrypto, because CryptoKit has no password-based
/// KDF — HKDF expands an already-strong key and is the wrong tool for something
/// a person typed.
///
/// This exists for one reason: section 7 requires the vault key to be wrapped
/// with a passphrase-derived key so a locked note opens on another device. The
/// passphrase itself is never stored, anywhere.
enum PassphraseKDF {

    /// OWASP's floor for PBKDF2-HMAC-SHA256, and slow enough on device to be
    /// worth doing off the main thread.
    static let defaultIterations = 310_000
    static let minimumPassphraseLength = 8
    static let saltLength = 32

    static func makeSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        // A predictable salt would let one rainbow table cover every Verso user.
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            // Falling back to a weaker source silently would be worse than
            // refusing; the caller surfaces this.
            return Data(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
        }
        return Data(bytes)
    }

    static func derive(
        passphrase: String,
        salt: Data,
        iterations: Int = defaultIterations
    ) throws -> SymmetricKey {
        guard passphrase.count >= minimumPassphraseLength else {
            throw VaultError.passphraseTooShort(minimum: minimumPassphraseLength)
        }

        // Normalised so the same passphrase typed on a Mac and an iPhone, or
        // with different Unicode compositions, derives the same key.
        let normalised = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
        var derived = [UInt8](repeating: 0, count: 32)

        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                normalised.map { Int8(bitPattern: $0) },
                normalised.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress,
                salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived,
                derived.count
            )
        }

        guard status == kCCSuccess else { throw VaultError.sealFailed }
        return SymmetricKey(data: Data(derived))
    }

    /// Rough guidance while the user is typing. Deliberately not a score out of
    /// five — this is the only thing standing between a stolen device backup
    /// and the contents.
    static func strengthDescription(for passphrase: String) -> String {
        let length = passphrase.count
        let classes = [
            passphrase.contains(where: \.isLowercase),
            passphrase.contains(where: \.isUppercase),
            passphrase.contains(where: \.isNumber),
            passphrase.contains { !$0.isLetter && !$0.isNumber },
        ].count { $0 }

        return switch (length, classes) {
        case (..<minimumPassphraseLength, _):
            String(localized: "Too short")
        case (..<12, _):
            String(localized: "Short — a few words would be stronger")
        case (_, 1):
            String(localized: "Long, which matters more than complexity")
        default:
            String(localized: "Good")
        }
    }
}

/// The vault key, encrypted with a key derived from the passphrase.
///
/// This is the part that may safely sync: without the passphrase it is noise,
/// and the passphrase exists only in the user's head.
struct WrappedVaultKey: Codable, Hashable, Sendable {
    var version: Int
    var salt: Data
    var iterations: Int
    /// AES-GCM combined box over the raw vault key.
    var sealed: Data

    static let currentVersion = 1

    static func wrap(_ vaultKey: SymmetricKey, passphrase: String) throws -> WrappedVaultKey {
        let salt = PassphraseKDF.makeSalt()
        let iterations = PassphraseKDF.defaultIterations
        let derived = try PassphraseKDF.derive(passphrase: passphrase, salt: salt, iterations: iterations)

        let raw = vaultKey.withUnsafeBytes { Data($0) }
        guard let combined = try AES.GCM.seal(raw, using: derived).combined else {
            throw VaultError.sealFailed
        }

        return WrappedVaultKey(
            version: currentVersion,
            salt: salt,
            iterations: iterations,
            sealed: combined
        )
    }

    func unwrap(passphrase: String) throws -> SymmetricKey {
        guard version == Self.currentVersion else {
            throw VaultError.unsupportedVersion(version)
        }
        let derived = try PassphraseKDF.derive(passphrase: passphrase, salt: salt, iterations: iterations)

        do {
            let raw = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: derived)
            return SymmetricKey(data: raw)
        } catch {
            throw VaultError.wrongPassphrase
        }
    }
}
