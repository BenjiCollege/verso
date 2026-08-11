import SwiftUI

/// The formatting bar, pinned above the keyboard.
///
/// A SwiftUI view held by `safeAreaInset` rather than a UIKit
/// `inputAccessoryView`: it stays inside the SwiftUI world, so it gets the
/// theme, Dynamic Type and VoiceOver ordering for free, and keyboard avoidance
/// puts it in the right place without a hosting controller.
struct FormattingToolbar: View {
    let session: TextEditingSession
    /// Resolved by the editor, so following a link is an ordinary
    /// `NavigationLink` on the enclosing stack rather than a button that has to
    /// reach for it.
    let linkedNote: Note?

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion

    var body: some View {
        HStack(spacing: Layout.Space.tight) {
            ForEach(InlineStyle.all, id: \.rawValue) { style in
                styleButton(style)
            }

            Divider()
                .frame(height: Layout.Space.regular)
                .overlay(theme.rule)

            Button {
                session.startLink()
            } label: {
                Image(systemName: "link.badge.plus")
                    .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Link to a note"))

            if let linkedNote {
                NavigationLink(value: linkedNote) {
                    Label("Open", systemImage: "arrow.up.forward.square")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("Open linked note"))
                .transition(motion.transition(.snap, motion: .scale.combined(with: .opacity)))
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, Layout.Space.regular)
        .padding(.vertical, Layout.Space.tight)
        .background(.bar)
        .animation(motion.animation(.snap), value: linkedNote?.id)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Text formatting"))
    }

    private func styleButton(_ style: InlineStyle) -> some View {
        let isOn = session.activeStyle.contains(style)

        return Button {
            session.toggle(style)
        } label: {
            Image(systemName: style.systemImage)
                .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                .background(
                    isOn ? theme.accent.opacity(0.18) : .clear,
                    in: .rect(cornerRadius: Layout.Radius.tight)
                )
                .foregroundStyle(isOn ? theme.accent : theme.ink)
                .contentShape(.rect)
        }
        .accessibilityLabel(Text(style.displayName))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
