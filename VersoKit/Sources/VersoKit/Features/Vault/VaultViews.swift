import SwiftUI

/// Creating a vault, or opening one.
struct VaultGateView: View {
    @Environment(VaultService.self) private var vault
    @Environment(HapticEngine.self) private var haptics
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var passphrase = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                switch vault.state {
                case .notSetUp: setUpSection
                case .needsPassphrase: passphraseSection(isFirstTimeOnThisDevice: true)
                case .locked: unlockSection
                case .unlocked: unlockedSection
                }

                if let error = vault.lastError {
                    Section { Text(error).foregroundStyle(theme.accent) }
                }
            }
            .navigationTitle("Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .disabled(vault.isWorking)
            .onChange(of: vault.state) { _, state in
                if state == .unlocked { haptics.play(.vaultClasp) }
            }
        }
    }

    // MARK: - Sections

    private var setUpSection: some View {
        Group {
            Section {
                SecureField("Passphrase", text: $passphrase)
                    .textContentType(.newPassword)
                SecureField("Repeat it", text: $confirmation)
                    .textContentType(.newPassword)

                if !passphrase.isEmpty {
                    Text(PassphraseKDF.strengthDescription(for: passphrase))
                        .versoText(.metadata)
                        .foregroundStyle(theme.inkSecondary)
                }
            } header: {
                Text("Choose a passphrase")
            } footer: {
                Text("A few unrelated words beats a short complicated one. This passphrase is never stored anywhere — not on your device, not in iCloud, not with us. If you lose it, the notes in your vault are gone.")
            }

            Section {
                Button("Create Vault") {
                    Task { await vault.setUp(passphrase: passphrase) }
                }
                .disabled(!isPassphraseAcceptable)
            } footer: {
                if vault.biometry.isAvailable {
                    Text("After this you'll unlock with \(vault.biometryName). The passphrase is what opens your vault on another device.")
                } else {
                    Text("This device has no biometrics set up, so you'll be asked for the passphrase each time.")
                }
            }
        }
    }

    private func passphraseSection(isFirstTimeOnThisDevice: Bool) -> some View {
        Section {
            SecureField("Passphrase", text: $passphrase)
                .textContentType(.password)
            Button("Unlock") {
                Task { await vault.unlockWithPassphrase(passphrase) }
            }
            .disabled(passphrase.isEmpty)
        } header: {
            Text("Enter your passphrase")
        } footer: {
            Text(isFirstTimeOnThisDevice
                 ? "Your vault was set up on another device. Enter its passphrase once, and \(vault.biometryName) will open it here from then on."
                 : "")
        }
    }

    private var unlockSection: some View {
        Group {
            if vault.biometry.isAvailable {
                Section {
                    Button {
                        Task { await vault.unlockWithBiometrics() }
                    } label: {
                        Label("Unlock with \(vault.biometryName)", systemImage: "faceid")
                    }
                }
            }
            passphraseSection(isFirstTimeOnThisDevice: false)
        }
    }

    private var unlockedSection: some View {
        Group {
            Section {
                Label("Vault is open", systemImage: "lock.open")
                    .foregroundStyle(theme.accent)
                Button("Lock Now") { vault.lock() }
            } footer: {
                Text("Locked notes are encrypted on disk and in iCloud. Verso holds the key only while the vault is open.")
            }
        }
    }

    private var isPassphraseAcceptable: Bool {
        passphrase.count >= PassphraseKDF.minimumPassphraseLength && passphrase == confirmation
    }
}

/// Covers the screen when the app is about to be snapshotted.
///
/// Section 7 lists the app-switcher snapshot alongside Spotlight and widgets,
/// and it is the one people forget: iOS photographs the screen on the way to
/// the background, and that image is not encrypted by anything Verso does.
struct PrivacyScreen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.stock
            VStack(spacing: Layout.Space.cosy) {
                Image(systemName: "lock.fill")
                    .font(.system(size: Layout.Space.airy))
                    .foregroundStyle(theme.gilt)
                Text("Verso")
                    .versoText(.title)
                    .foregroundStyle(theme.inkSecondary)
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .accessibilityHidden(true)
    }
}

/// What a locked note looks like from the library.
struct LockedNoteView: View {
    let note: Note

    @Environment(VaultService.self) private var vault
    @Environment(\.theme) private var theme

    @State private var isShowingGate = false

    var body: some View {
        ContentUnavailableView {
            Label("Locked", systemImage: "lock.fill")
        } description: {
            Text("This note is encrypted. Open the vault to read it.")
        } actions: {
            Button("Open Vault") { isShowingGate = true }
                .buttonStyle(.borderedProminent)
        }
        .background(theme.canvas.ignoresSafeArea())
        .sheet(isPresented: $isShowingGate) {
            VaultGateView()
        }
        .task { vault.isViewingLockedNote = true }
        .onDisappear { vault.isViewingLockedNote = false }
    }
}
