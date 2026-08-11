import CryptoKit
import Foundation

/// AES-GCM over a block payload.
///
/// Section 7 is explicit that this is not a Face ID gate over plaintext: a
/// locked note's bytes are ciphertext on disk and in iCloud, and the key is not
/// in the store with them.
struct VaultCipher: Sendable {

    /// Four bytes that say "this is sealed", so recognising an encrypted
    /// payload is a prefix comparison rather than an attempted decryption.
    /// The version byte is what makes rotating the scheme possible later
    /// without guessing at old data.
    static let magic = Data("VSL".utf8)
    static let version: UInt8 = 1
    static var headerLength: Int { magic.count + 1 }

    let key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }

    static func isSealed(_ data: Data) -> Bool {
        data.count > headerLength && data.prefix(magic.count) == magic
    }

    func seal(_ data: Data) throws -> Data {
        // Sealing an already-sealed payload would double-encrypt it and leave
        // it unopenable after one unlock.
        guard !Self.isSealed(data) else { return data }

        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else { throw VaultError.sealFailed }

        var result = Self.magic
        result.append(Self.version)
        result.append(combined)
        return result
    }

    func open(_ data: Data) throws -> Data {
        // Pass-through, so an unlocked note's plaintext survives a round trip
        // and callers never have to ask which kind they are holding.
        guard Self.isSealed(data) else { return data }

        let versionByte = data[data.startIndex + Self.magic.count]
        guard versionByte == Self.version else {
            throw VaultError.unsupportedVersion(Int(versionByte))
        }

        let body = data.dropFirst(Self.headerLength)
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: body), using: key)
        } catch {
            // A wrong key and tampered bytes are indistinguishable here, and
            // that is the correct behaviour — GCM authenticates.
            throw VaultError.wrongKeyOrTampered
        }
    }
}

enum VaultError: LocalizedError, Equatable {
    case sealFailed
    case wrongKeyOrTampered
    case unsupportedVersion(Int)
    case noKey
    case biometricsUnavailable
    case biometricsFailed
    case wrongPassphrase
    case passphraseTooShort(minimum: Int)
    case keychainFailure(OSStatus)
    case notSetUp

    var errorDescription: String? {
        switch self {
        case .sealFailed:
            String(localized: "Couldn't encrypt that.")
        case .wrongKeyOrTampered:
            String(localized: "This note couldn't be opened. The key is wrong, or the data has been altered.")
        case .unsupportedVersion(let version):
            String(localized: "This note was locked by a newer version of Verso (format \(version)).")
        case .noKey:
            String(localized: "The vault is locked.")
        case .biometricsUnavailable:
            String(localized: "Face ID or Touch ID isn't set up on this device. Use your passphrase.")
        case .biometricsFailed:
            String(localized: "Couldn't verify it was you.")
        case .wrongPassphrase:
            String(localized: "That passphrase doesn't open the vault.")
        case .passphraseTooShort(let minimum):
            String(localized: "Use at least \(minimum) characters.")
        case .keychainFailure(let status):
            String(localized: "The keychain refused the request (\(status)).")
        case .notSetUp:
            String(localized: "No vault has been set up yet.")
        }
    }
}
