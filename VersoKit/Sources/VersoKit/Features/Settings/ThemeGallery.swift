import SwiftUI

/// A theme, shown as a page rather than as a swatch.
///
/// In a list row a theme got 48×32 of colour beside its name, which is enough
/// to tell six apart and not enough to choose between them — the thing being
/// picked is what every page will look like, and it was being sold as a
/// bullet point. This is the same paper, ink, rule, accent and fore-edge the
/// page actually draws, at a size where the difference is visible.
struct ThemeTile: View {
    let candidate: Theme
    let isSelected: Bool

    @Environment(\.theme) private var theme

    /// Scaled, because the name underneath is.
    ///
    /// Fixed at 108×84 the tiles looked right at the default text size and
    /// fell apart at AX5: every label around them grew, the names truncated to
    /// "Cya…" and "Fox…", and the checkmark landed on the next tile. A picker
    /// whose options cannot be read is not a picker.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    /// Capped, because a tile is a picture and not a paragraph.
    ///
    /// Scaling it at the full text rate made the name readable and the picker
    /// useless: at AX5 one tile filled the screen, so choosing a theme meant
    /// scrolling blind through six of them with nothing to compare. Growing
    /// part of the way keeps two in view and gives the label the room it
    /// actually needed — the rest comes from letting the name wrap.
    private var scale: CGFloat { min(textScale, 1.5) }

    private var tileWidth: CGFloat { Layout.Space.vast * 2.25 * scale }
    private var tileHeight: CGFloat { Layout.Space.vast * 1.75 * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.snug) {
            page
            label
        }
        .frame(width: tileWidth)
    }

    private var page: some View {
        ZStack(alignment: .topLeading) {
            candidate.stock

            // The fore-edge, which is the one part of the app you cannot judge
            // from a flat swatch — it is only ever seen as a thin strip.
            HStack(spacing: 0) {
                candidate.edge.frame(width: Layout.Space.tight)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: Layout.Space.snug) {
                Capsule()
                    .fill(candidate.ink)
                    .frame(width: tileWidth * 0.46, height: Layout.Space.tight)

                VStack(alignment: .leading, spacing: Layout.Space.tight + 1) {
                    ForEach(0..<3, id: \.self) { line in
                        Capsule()
                            .fill(candidate.inkSecondary)
                            .frame(
                                width: tileWidth * (line == 2 ? 0.42 : 0.62),
                                height: Layout.hairline * 4
                            )
                    }
                }

                HStack(spacing: Layout.Space.tight) {
                    Circle()
                        .fill(candidate.accent)
                        .frame(width: Layout.Space.snug, height: Layout.Space.snug)
                    Capsule()
                        .fill(candidate.gilt)
                        .frame(width: Layout.Space.regular, height: Layout.hairline * 4)
                }
            }
            .padding(.leading, Layout.Space.cosy)
            .padding(.trailing, Layout.Space.snug)
            .padding(.vertical, Layout.Space.cosy)
        }
        .frame(width: tileWidth, height: tileHeight)
        .clipShape(.rect(cornerRadius: Layout.Radius.regular))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.Radius.regular)
                .strokeBorder(
                    isSelected ? theme.accent : theme.cardBorder,
                    lineWidth: isSelected ? 2 : Layout.hairline
                )
        }
    }

    private var label: some View {
        HStack(spacing: Layout.Space.tight) {
            Text(candidate.name)
                .versoText(.chromeLabel)
                .foregroundStyle(isSelected ? theme.ink : theme.inkSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.accent)
                    .imageScale(.small)
            }
        }
        .padding(.horizontal, Layout.Space.hair)
    }
}

/// The paper a page is printed on, drawn by the view the page itself uses — so
/// what is chosen is literally what appears.
struct StockTile: View {
    let candidate: Stock
    let isSelected: Bool

    @Environment(\.theme) private var theme

    /// Scaled with the label beneath it, for the reason `ThemeTile` gives.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    /// Capped with the label wrapping, for the reason `ThemeTile` gives.
    private var scale: CGFloat { min(textScale, 1.5) }

    private var tileWidth: CGFloat { Layout.Space.vast * 1.5 * scale }
    private var tileHeight: CGFloat { Layout.Space.vast * 1.15 * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.snug) {
            StockPattern(stock: candidate, theme: theme, lineHeight: Layout.Space.cosy)
                .background(theme.stock)
                .frame(width: tileWidth, height: tileHeight)
                .clipShape(.rect(cornerRadius: Layout.Radius.regular))
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.Radius.regular)
                        .strokeBorder(
                            isSelected ? theme.accent : theme.cardBorder,
                            lineWidth: isSelected ? 2 : Layout.hairline
                        )
                }

            HStack(spacing: Layout.Space.tight) {
                Text(candidate.name)
                    .versoText(.chromeCaption)
                    .foregroundStyle(isSelected ? theme.ink : theme.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                        .imageScale(.small)
                }
            }
            .padding(.horizontal, Layout.Space.hair)
        }
        .frame(width: tileWidth)
    }
}

/// A horizontally scrolling shelf of tiles.
///
/// Full-bleed on purpose. The shelf cancels the page's own margin and puts it
/// back as a content inset, so the first tile lines up with the cards above it
/// while the rest scroll all the way to the screen edge. Left inside the
/// margin, a shelf stops short of the edge and reads as a cropped list rather
/// than a continuing one — nothing about it invites the swipe.
struct SettingsShelf<Content: View>: View {
    /// The page margin this shelf is escaping. Passed rather than assumed, so
    /// a change to the screen's padding cannot silently misalign it.
    var margin: CGFloat = Layout.Space.regular
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Layout.Space.cosy) {
                content
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, margin, for: .scrollContent)
        .padding(.horizontal, -margin)
    }
}
