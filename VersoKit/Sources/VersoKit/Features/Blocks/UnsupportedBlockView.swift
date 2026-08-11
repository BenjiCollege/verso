import SwiftUI

/// Shown in place of a block this build can't render.
///
/// It says so plainly and takes up space, because the alternative — quietly
/// dropping the block — makes it look as though sync lost the user's content.
/// The stored payload is never touched, so a later build renders it properly.
struct UnsupportedBlockView: View {
    let typeName: String
    let systemImage: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Layout.Space.cosy) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.inkSecondary)

            VStack(alignment: .leading, spacing: Layout.Space.hair) {
                Text("\(typeName) block")
                    .versoText(.callout)
                    .foregroundStyle(theme.ink)
                Text("Not supported in this version. Its contents are safe.")
                    .versoText(.footnote)
                    .foregroundStyle(theme.inkSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(Layout.Space.cosy)
        .background(theme.inset, in: .rect(cornerRadius: Layout.Radius.tight))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.Radius.tight)
                .strokeBorder(theme.rule, style: StrokeStyle(lineWidth: Layout.hairline, dash: [4, 3]))
        }
        .accessibilityElement(children: .combine)
    }
}
