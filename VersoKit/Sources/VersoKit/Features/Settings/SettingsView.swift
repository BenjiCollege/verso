import SwiftUI

/// The live theme and stock switcher. Selecting either re-themes the whole app
/// immediately — `AppearanceStore` is observed at the root, so there is nothing
/// to reload and no restart.
///
/// Built from cards on a canvas rather than from a `Form`. Settings was the one
/// screen still wearing the system's grouped list while the library, the
/// gallery and the trash had all moved to cards, and the difference showed: the
/// greys were the system's, the insets were the system's, and the theme being
/// chosen was previewed in a swatch the size of a postage stamp.
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Layout.Space.loose) {
                    appearanceGroup(appearance: appearance)
                    themeGroup
                    paperGroup
                    readingGroup
                    writingGroup(appearance: appearance)
                    recordingsGroup(appearance: appearance)
                    privacyGroup
                    footer
                }
                .padding(.horizontal, Layout.Space.regular)
                .padding(.top, Layout.Space.snug)
                .padding(.bottom, Layout.Space.airy)
            }
            .background(theme.canvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
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

    // MARK: - Appearance

    private func appearanceGroup(appearance: AppearanceStore) -> some View {
        @Bindable var appearance = appearance

        return VStack(alignment: .leading, spacing: Layout.Space.snug) {
            SectionLabel(title: "Appearance")

            VStack(alignment: .leading, spacing: Layout.Space.cosy) {
                Picker("Use theme", selection: $appearance.mode) {
                    ForEach(AppearanceStore.Mode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(appearance.mode == .followSystem
                     ? "Follows Light and Dark Mode. Pick a theme built for the other and Verso keeps it always."
                     : "Stays in this theme whatever iOS does.")
                    .versoText(.chromeCaption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .versoCard()
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

    private var selectedThemeID: String {
        appearance.selectedThemeID(systemColorScheme: colorScheme)
    }

    private var themeGroup: some View {
        VStack(alignment: .leading, spacing: Layout.Space.snug) {
            SectionLabel(title: "Theme", detail: appearance.themeName(in: catalog, colorScheme: colorScheme))

            SettingsShelf {
                ForEach(availableThemes) { candidate in
                    themeTile(candidate)
                }
                makeThemeTile
            }

            Text("Themes you make stay on this device.")
                .versoText(.chromeCaption)
                .foregroundStyle(theme.inkTertiary)
                .padding(.horizontal, Layout.Space.snug)
        }
    }

    private func themeTile(_ candidate: Theme) -> some View {
        let isSelected = selectedThemeID == candidate.id

        return Button {
            appearance.selectTheme(candidate.id, systemColorScheme: colorScheme, catalog: catalog)
        } label: {
            ThemeTile(candidate: candidate, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        // A shelf has no swipe actions, so the two things you can do to a theme
        // you made live in the context menu — and as VoiceOver actions, because
        // a context menu is a long press nobody discovers by listening.
        .contextMenu {
            if candidate.isCustom {
                Button { editing = candidate } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    customThemes.delete(id: candidate.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(candidate.name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityActions {
            if candidate.isCustom {
                Button("Edit") { editing = candidate }
                Button("Delete") { customThemes.delete(id: candidate.id) }
            }
        }
    }

    private var makeThemeTile: some View {
        Button {
            // From the theme in force, not from a blank page: seven colours
            // chosen from nothing is a design job.
            editing = customThemes.draft(basedOn: theme)
        } label: {
            VStack(alignment: .leading, spacing: Layout.Space.snug) {
                RoundedRectangle(cornerRadius: Layout.Radius.regular)
                    .strokeBorder(
                        theme.cardBorder,
                        style: StrokeStyle(lineWidth: Layout.hairline * 2, dash: [5, 4])
                    )
                    .frame(width: Layout.Space.vast * 2.25, height: Layout.Space.vast * 1.75)
                    .overlay {
                        VStack(spacing: Layout.Space.snug) {
                            Image(systemName: "plus")
                                .font(.title3.weight(.light))
                            Text("Make a theme")
                                .versoText(.chromeCaption)
                        }
                        .foregroundStyle(theme.inkSecondary)
                    }

                Text(" ")
                    .versoText(.chromeLabel)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Make a theme"))
    }

    // MARK: - Paper

    private var paperGroup: some View {
        VStack(alignment: .leading, spacing: Layout.Space.snug) {
            SectionLabel(
                title: "Paper",
                detail: catalog.resolveStock(selectedID: appearance.stockID).name
            )

            SettingsShelf {
                ForEach(catalog.stocks) { candidate in
                    Button {
                        appearance.stockID = candidate.id
                    } label: {
                        StockTile(candidate: candidate, isSelected: appearance.stockID == candidate.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(candidate.name))
                    .accessibilityAddTraits(
                        appearance.stockID == candidate.id ? [.isButton, .isSelected] : .isButton
                    )
                }
            }
        }
    }

    // MARK: - Reading

    private var readingGroup: some View {
        SettingsGroup(title: "Reading", footnote: "Also reachable while reading.") {
            SettingsLink(
                title: "Text size and spacing",
                value: String(localized: appearance.typeface.displayName)
            ) {
                isAdjustingReading = true
            }
        }
    }

    // MARK: - Writing

    private func writingGroup(appearance: AppearanceStore) -> some View {
        @Bindable var appearance = appearance

        return SettingsGroup(title: "Writing") {
            SettingsToggle(
                title: "Typewriter Scroll",
                caption: Text("Holds the line you're writing in one place."),
                isOn: $appearance.isTypewriterEnabled
            )
            SettingsDivider()
            SettingsToggle(
                title: "Focus Mode",
                caption: Text("Dims everything but the paragraph you're in."),
                isOn: $appearance.isFocusModeEnabled
            )
            SettingsDivider()
            SettingsToggle(title: "Autocorrect", isOn: $appearance.isAutocorrectEnabled)
            SettingsDivider()
            SettingsToggle(
                title: "Haptics",
                caption: Text("The clasp, the checkmark, the fore-edge."),
                isOn: $appearance.isHapticsEnabled
            )
        }
    }

    // MARK: - Recordings

    private func recordingsGroup(appearance: AppearanceStore) -> some View {
        @Bindable var appearance = appearance

        return SettingsGroup(title: "Recordings") {
            SettingsToggle(
                title: "Keep new recordings on this device",
                caption: Text("Device-only recordings can't be recovered if you lose this phone."),
                isOn: $appearance.keepAudioOnDevice
            )
            SettingsDivider()
            SettingsRow(title: "In iCloud") { SettingsValue(text: usage.syncedDescription) }
            SettingsDivider()
            SettingsRow(title: "On this device only") { SettingsValue(text: usage.localOnlyDescription) }
        }
    }

    // MARK: - Privacy and status

    /// The vault, sync and intelligence read as one thing — what this app does
    /// with what you write — so they are one group rather than three of one row.
    private var privacyGroup: some View {
        SettingsGroup(
            title: "Privacy",
            footnote: "No server, no analytics. Everything is worked out on this device, and your notes sync only through your own iCloud."
        ) {
            SettingsLink(title: "Locked notes", value: vaultSummary) {
                isShowingVault = true
            }
            SettingsDivider()
            SettingsRow(title: "iCloud Sync", caption: syncCaption) {
                SettingsValue(text: persistenceMode.summary)
            }
            SettingsDivider()
            SettingsRow(
                title: "Suggestions",
                caption: intelligence.availability.explanation.map { Text(verbatim: $0) }
            ) {
                SettingsValue(
                    text: intelligence.isUsingOnDeviceModel
                        ? String(localized: "On-device model")
                        : String(localized: "Built-in")
                )
            }
        }
    }

    /// `verbatim`, because the reason is a runtime string that is already
    /// localised — not a key to look one up with.
    private var syncCaption: Text? {
        guard case .localOnly(let reason) = persistenceMode else { return nil }
        return Text(verbatim: reason)
    }

    private var footer: some View {
        // Read once. `body` runs often and this was reaching into the Info
        // dictionary twice on every pass to render eight characters.
        let version = Bundle.main.marketingVersion
        return Text(verbatim: "Verso \(version)")
            .versoText(.metadata)
            .foregroundStyle(theme.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Layout.Space.snug)
            .accessibilityLabel(Text("Verso version \(version)"))
    }
}

// MARK: - Helpers

extension AppearanceStore {
    /// The name of the theme in force, for the label beside the section title.
    func themeName(in catalog: ThemeCatalog, colorScheme: ColorScheme) -> String {
        catalog.theme(id: selectedThemeID(systemColorScheme: colorScheme))?.name ?? ""
    }
}

extension Bundle {
    var marketingVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
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

extension VersoModelContainer.Mode {
    var summary: String {
        switch self {
        case .cloudKit: String(localized: "On")
        case .localOnly: String(localized: "This device only")
        }
    }
}
