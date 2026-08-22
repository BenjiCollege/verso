import SwiftUI

/// The live theme and stock switcher. Selecting either re-themes the whole app
/// immediately — `AppearanceStore` is observed at the root, so there is nothing
/// to reload and no restart.
struct SettingsView: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.persistenceMode) private var persistenceMode
    @Environment(\.themeCatalog) private var catalog
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @Environment(CustomThemeStore.self) private var customThemes

    @State private var isAdjustingReading = false
    /// The theme being made or changed. Non-nil presents the editor.
    @State private var editing: Theme?
    @Environment(\.dismiss) private var dismiss
    @Environment(VaultService.self) private var vault
    @Environment(IntelligenceService.self) private var intelligence

    @Environment(\.modelContext) private var context

    @State private var isShowingVault = false
    @State private var usage = AudioStore.Usage(syncedBytes: 0, localOnlyBytes: 0, recordingCount: 0)

    private var vaultSummary: String {
        switch vault.state {
        case .notSetUp: String(localized: "Not set up")
        case .needsPassphrase: String(localized: "Needs your passphrase")
        case .locked: String(localized: "Locked")
        case .unlocked: String(localized: "Open")
        }
    }

    var body: some View {
        @Bindable var appearance = appearance

        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Use theme", selection: $appearance.mode) {
                        ForEach(AppearanceStore.Mode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(appearance.mode == .followSystem
                        ? "Follows Light and Dark Mode. Pick a theme built for the other and Verso keeps it always."
                        : "Stays in this theme whatever iOS does.")
                        .versoText(.chromeCaption)
                        .foregroundStyle(theme.inkSecondary)
                }

                Section {
                    ForEach(availableThemes) { candidate in
                        themeRow(candidate)
                            .swipeActions(edge: .trailing) {
                                if candidate.isCustom {
                                    Button(role: .destructive) {
                                        customThemes.delete(id: candidate.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        editing = candidate
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                }
                            }
                    }

                    Button {
                        // From the theme in force, not from a blank page: seven
                        // colours chosen from nothing is a design job.
                        editing = customThemes.draft(basedOn: theme)
                    } label: {
                        Label("Make a theme", systemImage: "plus")
                    }
                } header: {
                    Text("Theme")
                } footer: {
                    Text("Themes you make stay on this device.")
                }

                Section("Paper") {
                    ForEach(catalog.stocks) { candidate in
                        stockRow(candidate)
                    }
                }

                Section {
                    Button {
                        isAdjustingReading = true
                    } label: {
                        LabeledContent("Text size and spacing") {
                            Text(appearance.typeface.displayName)
                                .foregroundStyle(theme.inkSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Also reachable while reading.")
                }

                Section("Editing") {
                    Toggle(isOn: $appearance.isTypewriterEnabled) {
                        Text("Typewriter Scroll")
                    }
                    Text("Holds the line you're writing in one place.")
                        .versoText(.chromeCaption)
                        .foregroundStyle(theme.inkSecondary)

                    Toggle(isOn: $appearance.isFocusModeEnabled) {
                        Text("Focus Mode")
                    }
                    Text("Dims everything but the paragraph you're in.")
                        .versoText(.chromeCaption)
                        .foregroundStyle(theme.inkSecondary)

                    Toggle(isOn: $appearance.isAutocorrectEnabled) {
                        Text("Autocorrect")
                    }

                    Toggle(isOn: $appearance.isHapticsEnabled) {
                        Text("Haptics")
                    }
                    Text("The clasp, the checkmark, the fore-edge.")
                        .versoText(.chromeCaption)
                        .foregroundStyle(theme.inkSecondary)
                }

                Section {
                    Toggle(isOn: $appearance.keepAudioOnDevice) {
                        Text("Keep new recordings on this device")
                    }

                    LabeledContent("In iCloud") {
                        Text(usage.syncedDescription).foregroundStyle(theme.inkSecondary)
                    }
                    LabeledContent("On this device only") {
                        Text(usage.localOnlyDescription).foregroundStyle(theme.inkSecondary)
                    }
                } header: {
                    Text("Recordings")
                } footer: {
                    Text("\(usage.recordingCount) recordings. Device-only ones can't be recovered if you lose this phone.")
                }

                Section("Vault") {
                    Button {
                        isShowingVault = true
                    } label: {
                        LabeledContent("Locked notes") {
                            Text(vaultSummary).foregroundStyle(theme.inkSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("iCloud") {
                    LabeledContent("Sync") {
                        Text(persistenceMode.summary)
                            .foregroundStyle(theme.inkSecondary)
                    }
                    if case .localOnly(let reason) = persistenceMode {
                        Text(reason)
                            .versoText(.chromeCaption)
                            .foregroundStyle(theme.inkSecondary)
                    }
                }

                Section {
                    LabeledContent("Suggestions") {
                        Text(intelligence.isUsingOnDeviceModel
                             ? String(localized: "On-device model")
                             : String(localized: "Built-in"))
                            .foregroundStyle(theme.inkSecondary)
                    }
                    if let explanation = intelligence.availability.explanation {
                        Text(explanation)
                            .versoText(.chromeCaption)
                            .foregroundStyle(theme.inkSecondary)
                    }
                } header: {
                    Text("Intelligence")
                } footer: {
                    Text("Worked out on this device. Nothing you write is sent anywhere.")
                }

                Section("Privacy") {
                    Text("No server, no analytics. Your notes sync through your own iCloud.")
                        .versoText(.chromeCaption)
                        .foregroundStyle(theme.inkSecondary)
                }
            }
            // Rows on the card colour, the form on the canvas, so Settings is
            // built from the same two surfaces as the library rather than from
            // whatever grey the system had to hand.
            .listRowBackground(theme.card)
            .scrollContentBackground(.hidden)
            .background(theme.canvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { draft in
                ThemeEditorView(draft: draft) { saved in
                    guard customThemes.save(saved) else { return }
                    // Selecting it is the point of having made it.
                    appearance.selectTheme(
                        saved.id,
                        systemColorScheme: colorScheme,
                        catalog: catalog.adding(customThemes.themes + [saved])
                    )
                }
            }
            .sheet(isPresented: $isAdjustingReading) {
                ReadingControlsSheet()
                    .presentationDetents([.height(320)])
            }
            .sheet(isPresented: $isShowingVault) {
                VaultGateView()
            }
            .task {
                usage = AudioStore.usage(in: context)
            }
        }
    }

    // MARK: - Theme

    /// All of them, always.
    ///
    /// Following the system used to hide every theme built for the other
    /// appearance, which made half the library invisible for no reason a reader
    /// could see. Choosing a dark theme in daylight is a legitimate thing to
    /// want; `selectTheme` reads it as choosing the look and stops following the
    /// system, and the app follows the paper from there.
    private var availableThemes: [Theme] { catalog.themes }

    private func themeRow(_ candidate: Theme) -> some View {
        let isSelected = appearance.selectedThemeID(systemColorScheme: colorScheme) == candidate.id

        return Button {
            appearance.selectTheme(candidate.id, systemColorScheme: colorScheme, catalog: catalog)
        } label: {
            HStack(spacing: Layout.Space.cosy) {
                ThemeSwatch(theme: candidate)
                Text(candidate.name)
                    .versoText(.chromeBody)
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Stock

    private func stockRow(_ candidate: Stock) -> some View {
        let isSelected = appearance.stockID == candidate.id

        return Button {
            appearance.stockID = candidate.id
        } label: {
            HStack(spacing: Layout.Space.cosy) {
                StockSwatch(stock: candidate, theme: theme)
                Text(candidate.name)
                    .versoText(.chromeBody)
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Page colour, a stroke of ink, and the accent — enough to tell six themes
/// apart at a glance without a screenshot.
/// The paper-and-ink pill that stands for a theme. Shared by Settings and the
/// per-note picker, which is why it is not file-private.
struct ThemeSwatch: View {
    let theme: Theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Layout.Radius.tight)
                .fill(theme.stock)

            VStack(alignment: .leading, spacing: Layout.Space.hair) {
                Capsule().fill(theme.ink).frame(width: Layout.Space.loose, height: Layout.hairline * 4)
                Capsule().fill(theme.inkSecondary).frame(width: Layout.Space.regular, height: Layout.hairline * 4)
            }

            Circle()
                .fill(theme.accent)
                .frame(width: Layout.Space.snug, height: Layout.Space.snug)
                .offset(x: Layout.Space.regular, y: Layout.Space.snug)
        }
        .frame(width: Layout.Space.vast, height: Layout.Space.airy)
        .overlay {
            RoundedRectangle(cornerRadius: Layout.Radius.tight)
                .strokeBorder(theme.rule, lineWidth: Layout.hairline)
        }
        .accessibilityHidden(true)
    }
}

/// The stock's own pattern, drawn by the same view the page uses.
private struct StockSwatch: View {
    let stock: Stock
    let theme: Theme

    var body: some View {
        StockPattern(stock: stock, theme: theme, lineHeight: Layout.Space.snug)
            .background(theme.stock)
            .frame(width: Layout.Space.vast, height: Layout.Space.airy)
            .clipShape(.rect(cornerRadius: Layout.Radius.tight))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.Radius.tight)
                    .strokeBorder(theme.rule, lineWidth: Layout.hairline)
            }
            .accessibilityHidden(true)
    }
}

extension VersoModelContainer.Mode {
    var summary: String {
        switch self {
        case .cloudKit: String(localized: "On")
        case .localOnly: String(localized: "This device only")
        }
    }
}
