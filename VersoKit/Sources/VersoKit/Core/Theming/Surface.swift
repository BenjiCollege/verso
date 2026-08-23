import SwiftUI

// MARK: - Elevation tokens

extension Theme {

    /// The surface a card sits on.
    ///
    /// Elevation has to be built from the palette rather than added to it: a
    /// theme file declares seven colours and a card is not one of them, so a
    /// new key would mean every theme — including the ones people make — needing
    /// a value for something they never chose.
    ///
    /// The direction flips with appearance, which is the whole trick. Lifting
    /// means *lighter* on dark paper and the canvas going a shade down on light
    /// paper; mixing toward ink does both, because ink is dark on light themes
    /// and light on dark ones.
    var canvas: Color {
        appearance == .dark
            ? palette.stock.color
            : palette.stock.mixed(with: palette.ink, amount: 0.05).color
    }

    /// A card's own fill. Always the paper the theme actually names, on light
    /// themes — so the thing you read off is the stock, and the canvas is what
    /// gives way.
    var card: Color {
        appearance == .dark
            ? palette.stock.mixed(with: palette.ink, amount: 0.07).color
            : palette.stock.color
    }

    /// The hairline round a card. Softer than `rule`, which is for ruled lines
    /// on a page and would read as a box drawn in ink.
    var cardBorder: Color {
        palette.rule.mixed(with: palette.stock, amount: 0.55).color
    }
}

// MARK: - The card

/// The one card shape.
///
/// Cards are for *chrome* — the library, the gallery, settings, the trash.
/// Never for the page. A paragraph wrapped in a card is what every notes app
/// looks like, and the page is the one surface here that doesn't.
private struct VersoCard: ViewModifier {
    let padding: CGFloat
    let radius: CGFloat

    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(theme.cardBorder, lineWidth: Layout.hairline)
            )
    }
}

extension View {
    /// Wraps content as a card. The only way view code makes one.
    func versoCard(
        padding: CGFloat = Layout.Space.cosy,
        radius: CGFloat = Layout.Radius.regular
    ) -> some View {
        modifier(VersoCard(padding: padding, radius: radius))
    }
}

// MARK: - Section headings

/// The quiet label above a group of cards.
///
/// Deliberately not a `Section` header: those come with the system's own
/// styling and its own idea of margins, and a list built from cards has to own
/// its rhythm or the spacing drifts section by section.
struct SectionLabel: View {
    let title: LocalizedStringResource
    /// A count, usually. Sits opposite the title rather than beside it, so the
    /// eye can find either without reading both.
    var detail: String?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Text(title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Layout.Space.regular)
            if let detail {
                // One line, always. A detail is a count or a short name, and
                // letting it wrap turns a two-word theme name into two lines
                // that collide with the title beside it at large text sizes.
                Text(detail)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .versoText(.metadata)
        .foregroundStyle(theme.inkTertiary)
        .padding(.horizontal, Layout.Space.snug)
        .padding(.top, Layout.Space.snug)
    }
}

// MARK: - Pills

/// A tag, or anything else that reads as one word about a thing.
struct VersoPill: View {
    let title: String
    var systemImage: String?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Layout.Space.tight) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(title)
        }
        .versoText(.metadata)
        .foregroundStyle(theme.inkSecondary)
        .padding(.horizontal, Layout.Space.snug)
        .padding(.vertical, Layout.Space.hair)
        .background(theme.inset, in: .rect(cornerRadius: Layout.Radius.capsule))
    }
}

// MARK: - Relative time

extension Date {
    /// "2h ago", "Yesterday" — how long ago, not when.
    ///
    /// A list is scanned, not read. An absolute timestamp makes you do the
    /// arithmetic; this does it for you, and falls back to a date once "ago"
    /// stops being a useful answer.
    var relativeDescription: String {
        let now = Date()
        let elapsed = now.timeIntervalSince(self)

        if elapsed < 60 { return String(localized: "Just now") }
        if elapsed < 7 * 24 * 3600 {
            // A format style rather than a shared `RelativeDateTimeFormatter`:
            // that class is not `Sendable`, so a static one is shared mutable
            // state. This is a value, built and discarded per call, and costs
            // nothing worth caching.
            return formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        }
        return formatted(date: .abbreviated, time: .omitted)
    }
}
