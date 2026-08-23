import SwiftUI

// MARK: - Grouped rows

/// A group of settings rows on one card.
///
/// Settings used to be a `Form`, which is why it was the one screen that did
/// not look like the rest of the app: the library, the gallery and the trash
/// are all cards on a canvas, and a `Form` is the system's grouped list with
/// the system's own insets, separators and greys. Matching them by hand meant
/// fighting it row by row.
///
/// This is the same card the rest of the chrome uses, with the rows drawn into
/// it. Dividers are inset past the leading padding so they read as separating
/// rows rather than boxing them.
struct SettingsGroup<Content: View>: View {
    var title: LocalizedStringResource?
    var footnote: LocalizedStringResource?
    @ViewBuilder var content: Content

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.snug) {
            if let title {
                SectionLabel(title: title)
            }

            VStack(spacing: 0) { content }
                .versoCard(padding: 0)

            if let footnote {
                Text(footnote)
                    .versoText(.chromeCaption)
                    .foregroundStyle(theme.inkTertiary)
                    .padding(.horizontal, Layout.Space.snug)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The hairline between two rows in a group.
struct SettingsDivider: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.cardBorder)
            .frame(height: Layout.hairline)
            .padding(.leading, Layout.Space.regular)
            .accessibilityHidden(true)
    }
}

/// A label, an optional value, and an optional second line explaining it.
///
/// The explanation belongs *inside* the row rather than under it. As separate
/// rows the captions read as list items of their own — VoiceOver announced them
/// that way too, so a four-switch section was eight elements.
struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringResource
    /// A `Text`, not a `LocalizedStringResource`.
    ///
    /// Some captions are literals and some are runtime strings that arrived
    /// already localised — a sync failure reason, the language model's own
    /// explanation. Typing this as `LocalizedStringResource` forced the runtime
    /// ones through `init(stringLiteral:)`, which treats the value as a *key*
    /// to look up rather than as the text to show. It happens to fall back to
    /// the string itself, so it looked fine, but a caption that collided with a
    /// real key would have silently displayed something else.
    var caption: Text?
    @ViewBuilder var trailing: Trailing

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.Space.regular) {
            VStack(alignment: .leading, spacing: Layout.Space.tight) {
                Text(title)
                    .versoText(.chromeBody)
                    .foregroundStyle(theme.ink)
                if let caption {
                    caption
                        .versoText(.chromeCaption)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, Layout.Space.regular)
        .padding(.vertical, Layout.Space.cosy)
        .frame(minHeight: Layout.minimumHitTarget)
    }
}

/// The value on the right of a row.
struct SettingsValue: View {
    let text: String

    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .versoText(.chromeLabel)
            .foregroundStyle(theme.inkSecondary)
    }
}

/// A row that opens something.
struct SettingsLink: View {
    let title: LocalizedStringResource
    var value: String?
    var caption: Text?
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            SettingsRow(title: title, caption: caption) {
                HStack(spacing: Layout.Space.snug) {
                    if let value { SettingsValue(text: value) }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A switch and what it does.
struct SettingsToggle: View {
    let title: LocalizedStringResource
    var caption: Text?
    @Binding var isOn: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        SettingsRow(title: title, caption: caption) {
            // The real label, hidden visually rather than omitted. `Toggle("")`
            // is an unnamed control: the combined row saved it here, but any
            // future use outside one would have shipped a switch VoiceOver
            // could not name.
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(theme.accent)
        }
        .accessibilityElement(children: .combine)
    }
}
