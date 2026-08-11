import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import VersoKit

@Suite("Vault cipher")
struct VaultCipherTests {

    private let key = SymmetricKey(size: .bits256)
    private let plaintext = Data("The quick brown fox jumps over the lazy dog.".utf8)

    @Test("Sealing then opening returns the original bytes")
    func roundTrip() throws {
        let cipher = VaultCipher(key: key)
        let sealed = try cipher.seal(plaintext)

        #expect(sealed != plaintext)
        #expect(try cipher.open(sealed) == plaintext)
    }

    /// The whole claim of section 7: a locked note's bytes are ciphertext, not
    /// plaintext behind a prompt.
    @Test("Sealed bytes contain none of the original")
    func ciphertextLeaksNothing() throws {
        let sealed = try VaultCipher(key: key).seal(plaintext)
        #expect(sealed.range(of: plaintext) == nil)
        #expect(sealed.range(of: Data("quick".utf8)) == nil)
    }

    @Test("Sealed payloads are recognisable without trying to decrypt them")
    func sealedIsRecognisable() throws {
        let sealed = try VaultCipher(key: key).seal(plaintext)
        #expect(VaultCipher.isSealed(sealed))
        #expect(!VaultCipher.isSealed(plaintext))
        #expect(!VaultCipher.isSealed(Data()))
        #expect(!VaultCipher.isSealed(VaultCipher.magic), "the magic alone is not a payload")
    }

    /// Plaintext must pass through, or every read path would have to ask which
    /// kind of payload it was holding.
    @Test("Opening unsealed data returns it unchanged")
    func plaintextPassesThrough() throws {
        #expect(try VaultCipher(key: key).open(plaintext) == plaintext)
    }

    /// Double-sealing would leave a payload unopenable after one unlock.
    @Test("Sealing twice is a no-op")
    func sealingIsIdempotent() throws {
        let cipher = VaultCipher(key: key)
        let once = try cipher.seal(plaintext)
        #expect(try cipher.seal(once) == once)
        #expect(try cipher.open(once) == plaintext)
    }

    @Test("The wrong key does not open it")
    func wrongKeyFails() throws {
        let sealed = try VaultCipher(key: key).seal(plaintext)
        #expect(throws: VaultError.wrongKeyOrTampered) {
            _ = try VaultCipher(key: SymmetricKey(size: .bits256)).open(sealed)
        }
    }

    /// GCM authenticates. A flipped bit has to fail, not decrypt to rubbish.
    @Test("Tampered ciphertext is rejected rather than decrypted")
    func tamperingIsDetected() throws {
        var sealed = try VaultCipher(key: key).seal(plaintext)
        let index = sealed.index(sealed.startIndex, offsetBy: sealed.count - 3)
        sealed[index] ^= 0xFF

        #expect(throws: VaultError.wrongKeyOrTampered) {
            _ = try VaultCipher(key: key).open(sealed)
        }
    }

    @Test("A payload from a future format version says so instead of failing vaguely")
    func futureVersionIsNamed() throws {
        var sealed = try VaultCipher(key: key).seal(plaintext)
        sealed[sealed.startIndex + VaultCipher.magic.count] = 99

        #expect(throws: VaultError.unsupportedVersion(99)) {
            _ = try VaultCipher(key: key).open(sealed)
        }
    }

    @Test("Sealing the same bytes twice gives different ciphertext")
    func noncesAreUnique() throws {
        let cipher = VaultCipher(key: key)
        #expect(try cipher.seal(plaintext) != cipher.seal(plaintext))
    }

    @Test("Empty and large payloads both survive")
    func edgeSizes() throws {
        let cipher = VaultCipher(key: key)
        #expect(try cipher.open(cipher.seal(Data())) == Data())

        let large = Data(repeating: 0x41, count: 2_000_000)
        #expect(try cipher.open(cipher.seal(large)) == large)
    }
}

@Suite("Passphrase wrapping")
struct PassphraseKDFTests {

    /// Real iteration counts take the better part of a second each; the maths
    /// is identical at a lower count and the test suite stays usable.
    private let iterations = 1_000

    @Test("The same passphrase and salt always derive the same key")
    func derivationIsDeterministic() throws {
        let salt = PassphraseKDF.makeSalt()
        let a = try PassphraseKDF.derive(passphrase: "correct horse battery", salt: salt, iterations: iterations)
        let b = try PassphraseKDF.derive(passphrase: "correct horse battery", salt: salt, iterations: iterations)
        #expect(a == b)
    }

    /// Without a per-vault salt, one rainbow table would cover every user.
    @Test("A different salt derives a different key")
    func saltMatters() throws {
        let phrase = "correct horse battery"
        let a = try PassphraseKDF.derive(passphrase: phrase, salt: PassphraseKDF.makeSalt(), iterations: iterations)
        let b = try PassphraseKDF.derive(passphrase: phrase, salt: PassphraseKDF.makeSalt(), iterations: iterations)
        #expect(a != b)
    }

    @Test("Salts are random and long enough to be")
    func saltsAreRandom() {
        let salts = (0..<8).map { _ in PassphraseKDF.makeSalt() }
        #expect(Set(salts).count == salts.count)
        #expect(salts.allSatisfy { $0.count == PassphraseKDF.saltLength })
    }

    @Test("A short passphrase is refused")
    func shortPassphraseIsRefused() {
        #expect(throws: VaultError.passphraseTooShort(minimum: PassphraseKDF.minimumPassphraseLength)) {
            _ = try PassphraseKDF.derive(passphrase: "short", salt: PassphraseKDF.makeSalt(), iterations: 1_000)
        }
    }

    /// A passphrase typed on two devices with different Unicode compositions
    /// must derive the same key, or the vault opens on one and not the other.
    @Test("Unicode composition does not change the key")
    func normalisation() throws {
        let salt = PassphraseKDF.makeSalt()
        let composed = "café passphrase"
        let decomposed = composed.decomposedStringWithCanonicalMapping

        #expect(composed.unicodeScalars.count != decomposed.unicodeScalars.count, "the inputs must actually differ")
        #expect(
            try PassphraseKDF.derive(passphrase: composed, salt: salt, iterations: iterations)
                == PassphraseKDF.derive(passphrase: decomposed, salt: salt, iterations: iterations)
        )
    }

    /// Section 7: the vault key is wrapped with a passphrase-derived key so
    /// locked notes open on other devices.
    @Test("The vault key survives being wrapped and unwrapped")
    func wrapRoundTrip() throws {
        let vaultKey = SymmetricKey(size: .bits256)
        let wrapped = try WrappedVaultKey.wrap(vaultKey, passphrase: "correct horse battery")
        // Carried in the record rather than assumed, so raising the default
        // later does not lock anybody out of a note wrapped before the change.
        #expect(wrapped.iterations == PassphraseKDF.defaultIterations)

        let recovered = try wrapped.unwrap(passphrase: "correct horse battery")
        #expect(recovered == vaultKey)

        // And the recovered key opens what the original sealed.
        let payload = Data("secret".utf8)
        #expect(try VaultCipher(key: recovered).open(VaultCipher(key: vaultKey).seal(payload)) == payload)
    }

    @Test("The wrong passphrase does not unwrap it")
    func wrongPassphraseFails() throws {
        let wrapped = try WrappedVaultKey.wrap(SymmetricKey(size: .bits256), passphrase: "correct horse battery")
        #expect(throws: VaultError.wrongPassphrase) {
            _ = try wrapped.unwrap(passphrase: "incorrect horse battery")
        }
    }

    /// This blob syncs through iCloud Keychain, so it must reveal nothing.
    @Test("The wrapped blob contains no plaintext key material")
    func wrappedBlobRevealsNothing() throws {
        let vaultKey = SymmetricKey(size: .bits256)
        let raw = vaultKey.withUnsafeBytes { Data($0) }
        let wrapped = try WrappedVaultKey.wrap(vaultKey, passphrase: "correct horse battery")

        #expect(wrapped.sealed.range(of: raw) == nil)
        let encoded = try JSONEncoder().encode(wrapped)
        #expect(encoded.range(of: raw) == nil)
    }

    @Test("Strength guidance is honest about short passphrases")
    func strengthGuidance() {
        #expect(PassphraseKDF.strengthDescription(for: "abc").contains("short") ||
                PassphraseKDF.strengthDescription(for: "abc").contains("Too"))
        #expect(!PassphraseKDF.strengthDescription(for: "correct horse battery staple").isEmpty)
    }
}

/// Serialised because `VaultKeyring` is process-wide by design — one test
/// unlocking it while another expects it closed would be a race in the test
/// suite, not in the app.
@Suite("Vault keyring and policy", .serialized)
@MainActor
struct VaultKeyringTests {

    private func withKeyring<T>(_ body: () throws -> T) rethrows -> T {
        defer { VaultKeyring.shared.lock() }
        return try body()
    }

    @Test("A closed vault cannot seal or open")
    func closedVaultRefuses() {
        VaultKeyring.shared.lock()

        #expect(throws: VaultError.noKey) { _ = try VaultKeyring.shared.seal(Data("x".utf8)) }
        #expect(!VaultKeyring.shared.isUnlocked)
    }

    @Test("An open vault seals and opens")
    func openVaultWorks() throws {
        try withKeyring {
            VaultKeyring.shared.unlock(with: SymmetricKey(size: .bits256))
            let payload = Data("secret".utf8)
            let sealed = try VaultKeyring.shared.seal(payload)

            #expect(VaultCipher.isSealed(sealed))
            #expect(try VaultKeyring.shared.open(sealed) == payload)
        }
    }

    /// Locking forgets the key; it does not touch the ciphertext.
    @Test("Locking makes sealed payloads unreadable again")
    func lockingClosesTheDoor() throws {
        let payload = Data("secret".utf8)
        VaultKeyring.shared.unlock(with: SymmetricKey(size: .bits256))
        let sealed = try VaultKeyring.shared.seal(payload)

        VaultKeyring.shared.lock()
        #expect(throws: VaultError.noKey) { _ = try VaultKeyring.shared.open(sealed) }
        #expect(VaultKeyring.shared.openIfPossible(sealed) == nil)
    }

    @Test("Plaintext still passes through a closed vault")
    func plaintextIsAlwaysReadable() throws {
        VaultKeyring.shared.lock()
        let payload = Data("not secret".utf8)
        #expect(try VaultKeyring.shared.open(payload) == payload)
    }

    // MARK: - Blocks

    @Test("A block in a locked note stores ciphertext")
    func lockedBlockStoresCiphertext() throws {
        try withKeyring {
            VaultKeyring.shared.unlock(with: SymmetricKey(size: .bits256))

            let context = ModelContext(try VersoModelContainer.makeInMemory())
            let note = Note(title: "Private")
            note.isLocked = true
            context.insert(note)

            let block = try Block(TextPayload(plain: "placeholder"))
            context.insert(block)
            note.append(block)

            try block.store(TextPayload(plain: "the actual secret"))

            #expect(block.isSealed)
            #expect(block.payload.range(of: Data("the actual secret".utf8)) == nil)
            #expect(try block.decoded(as: TextPayload.self).plain == "the actual secret")
        }
    }

    @Test("A block in an unlocked note stores plaintext")
    func unlockedBlockStoresPlaintext() throws {
        try withKeyring {
            VaultKeyring.shared.unlock(with: SymmetricKey(size: .bits256))

            let context = ModelContext(try VersoModelContainer.makeInMemory())
            let note = Note(title: "Open")
            context.insert(note)

            let block = try Block(TextPayload(plain: "x"))
            context.insert(block)
            note.append(block)
            try block.store(TextPayload(plain: "ordinary"))

            #expect(!block.isSealed)
        }
    }

    /// Previews and titling must never throw, and a locked note has nothing to
    /// show — not even while the vault is open, since a list is somewhere
    /// somebody else can read over your shoulder.
    @Test("A locked note reveals nothing in a list")
    func lockedNotesArePrivateInLists() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = Note(title: "Diary")
        context.insert(note)
        let block = try Block(TextPayload(plain: "something personal"))
        context.insert(block)
        note.append(block)

        #expect(VaultPolicy.listPreview(for: note).contains("something personal"))

        note.isLocked = true
        #expect(VaultPolicy.listTitle(for: note) != "Diary")
        #expect(VaultPolicy.listPreview(for: note).isEmpty)
    }

    /// Section 7 names four places a locked or hidden note must not appear.
    @Test("Locked, hidden and trashed notes are excluded from indexing")
    func indexingExclusions() {
        #expect(VaultPolicy.isEligibleForIndexing(Note(title: "Plain")))

        let locked = Note(); locked.isLocked = true
        let hidden = Note(); hidden.isHidden = true
        let trashed = Note(); trashed.isTrashed = true

        for note in [locked, hidden, trashed] {
            #expect(!VaultPolicy.isEligibleForIndexing(note))
        }
    }

    @Test("A locked note cannot be shared, even with the vault open")
    func lockedNotesCannotBeShared() {
        let note = Note(title: "Private")
        #expect(VaultPolicy.isEligibleForSharing(note))
        note.isLocked = true
        #expect(!VaultPolicy.isEligibleForSharing(note))
    }

    @Test("The privacy screen covers the snapshot only when there is something to cover")
    func privacyScreenRules() {
        #expect(VaultPolicy.requiresPrivacyScreen(isViewingLockedNote: true, isVaultUnlocked: true))
        #expect(!VaultPolicy.requiresPrivacyScreen(isViewingLockedNote: false, isVaultUnlocked: true))
        // With the vault closed there is nothing on screen but ciphertext.
        #expect(!VaultPolicy.requiresPrivacyScreen(isViewingLockedNote: true, isVaultUnlocked: false))
    }
}
