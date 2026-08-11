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
    @Environment(\.dismiss) private var dismiss
    @Environment(VaultService.self) private var vault

    @State private var isShowingVault = false

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

                    if appearance.mode == .followSystem {
                        Text("Verso uses a light theme in Light Mode and a dark theme in Dark Mode. You're choosing the \(colorScheme == .dark ? "dark" : "light") one.")
                            .versoText(.chromeCaption)
                            .foregroundStyle(theme.inkSecondary)
                    }
                }

                Section("Theme") {
                    ForEach(availableThemes) { candidate in
                        themeRow(candidate)
                    }
                }

                Section("Paper") {
                    ForEach(catalog.stocks) { candidate in
                        stockRow(candidate)
                    }
                }

                Section("Editing") {
                    Toggle(isOn: $appearance.isTypewriterEnabled) {
                        Text("Typewriter Scroll")
                    }
                    Text("Keeps the line you're writing at a fixed place on screen instead of letting it drift to the bottom.")
                        .versoText(.chromeCaption)
                        .foregroundStyle(theme.inkSecondary)
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

                Section("Privacy") {
                    Text("Verso has no server and no analytics. Your notes sync through your own iCloud account and nowhere else.")
                        .versoText(.chromeCaption)
                        .foregroundStyle(theme.inkSecondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingVault) {
                VaultGateView()
            }
        }
    }

    // MARK: - Theme

    /// Pinning a theme offers all of them; following the system offers only the
    /// ones built for the appearance currently in force.
    private var availableThemes: [Theme] {
        switch appearance.mode {
        case .pinned:
            catalog.themes
        case .followSystem:
            catalog.themes(for: colorScheme == .dark ? .dark : .light)
        }
    }

    private func themeRow(_ candidate: Theme) -> some View {
        let isSelected = appearance.selectedThemeID(systemColorScheme: colorScheme) == candidate.id

        return Button {
            appearance.selectTheme(candidate.id, systemColorScheme: colorScheme)
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
private struct ThemeSwatch: View {
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
