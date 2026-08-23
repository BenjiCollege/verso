import SwiftUI

/// One control the formatting bar can offer.
///
/// The bar is described as data rather than written out four times because the
/// promise that matters — bold, italic and the link the caret is already inside
/// stay one tap away at *every* text size — is a property of the whole set of
/// densities. Four hand-written `HStack`s have nowhere to assert that, and
/// nothing to stop the next edit quietly dropping italic into a menu.
enum FormattingControl: Hashable {
    case undo
    case redo
    case style(InlineStyle)
    /// Open a `[[` and start naming a note to link to.
    case insertLink
    /// Follow the link the caret is sitting in.
    case openLink

    /// Every control, in reading order. Overflow order is taken from here too,
    /// so a control lands in the same place in the menu at every density.
    static let all: [FormattingControl] =
        [.undo, .redo] + InlineStyle.all.map(FormattingControl.style) + [.insertLink, .openLink]
}

/// How much of the bar fits across; `ViewThatFits` picks the first one that does.
///
/// Nine controls at a 44pt hit target want about 430pt of width, which no
/// iPhone has even at the default text size — and at AX5 the glyphs alone are
/// three times that size. So the bar has to shed, and the interesting question
/// is only ever *what* it sheds first.
///
/// Rejected the obvious alternative, a horizontally scrolling row: it keeps
/// everything reachable on paper, but a scroll view offers no sign that there
/// is anything past the edge, and a swipe along a 44pt strip wedged against the
/// keyboard is a poor ask of exactly the people who turned the text size up. A
/// menu is discoverable, is one tap deep, and reads its contents out.
enum FormattingDensity: CaseIterable {
    case full
    case reduced
    case compact
    case minimal

    /// Controls shown directly, in groups. A hairline separator sits between
    /// one group and the next.
    var inlineGroups: [[FormattingControl]] {
        switch self {
        case .full:
            [[.undo, .redo], InlineStyle.all.map(FormattingControl.style), [.insertLink, .openLink]]
        case .reduced:
            [[.undo, .redo], [.style(.bold), .style(.italic)], [.insertLink, .openLink]]
        case .compact:
            [[.style(.bold), .style(.italic)], [.insertLink, .openLink]]
        case .minimal:
            [[.style(.bold), .style(.italic), .openLink]]
        }
    }

    var inlineControls: [FormattingControl] {
        inlineGroups.flatMap { $0 }
    }

    /// Everything the row could not hold, behind the overflow menu.
    var overflowControls: [FormattingControl] {
        FormattingControl.all.filter { !inlineControls.contains($0) }
    }
}

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

    /// The separator has to grow with the glyphs beside it, or it shrinks to a
    /// tick between two AX5 buttons.
    @ScaledMetric(relativeTo: .body) private var separatorHeight: CGFloat = Layout.Space.regular

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(.full)
            row(.reduced)
            row(.compact)
            row(.minimal)
        }
        .versoText(.chromeBody)
        .foregroundStyle(theme.ink)
        .padding(.horizontal, Layout.Space.regular)
        .padding(.vertical, Layout.Space.tight)
        .background(.bar)
        .animation(motion.animation(.snap), value: linkedNote?.id)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Text formatting"))
    }

    private func row(_ density: FormattingDensity) -> some View {
        let groups = density.inlineGroups
        let overflow = density.overflowControls

        return HStack(spacing: Layout.Space.tight) {
            ForEach(groups.indices, id: \.self) { index in
                if index > 0 {
                    separator
                }
                ForEach(groups[index], id: \.self) { control in
                    inlineControl(control)
                }
            }

            if !overflow.isEmpty {
                separator
                overflowMenu(overflow)
            }

            // Ideal width zero, so `ViewThatFits` measures the controls rather
            // than being told every row wants the whole screen.
            Spacer(minLength: 0)
        }
    }

    // MARK: - Directly reachable controls

    @ViewBuilder
    private func inlineControl(_ control: FormattingControl) -> some View {
        switch control {
        case .undo:
            // Undo first, on the left, where a hand already is. The text view
            // has kept an undo stack all along; nothing was reachable to drive
            // it, so the only way in was the shake gesture — undiscoverable, and
            // switched off by many people precisely because it fires by mistake.
            Button {
                session.undo()
            } label: {
                glyph("arrow.uturn.backward")
            }
            .disabled(!session.canUndo)
            .accessibilityLabel(Text("Undo"))

        case .redo:
            Button {
                session.redo()
            } label: {
                glyph("arrow.uturn.forward")
            }
            .disabled(!session.canRedo)
            .accessibilityLabel(Text("Redo"))

        case .style(let style):
            styleButton(style)

        case .insertLink:
            Button {
                session.startLink()
            } label: {
                glyph("link.badge.plus")
            }
            .accessibilityLabel(Text("Link to a note"))

        case .openLink:
            if let linkedNote {
                NavigationLink(value: linkedNote) {
                    glyph("arrow.up.forward.square")
                }
                .accessibilityLabel(Text("Open linked note"))
                .transition(motion.transition(.snap, motion: .scale.combined(with: .opacity)))
            }
        }
    }

    /// A bare `Image` in a `Button` is about twenty points across. Undo and Redo
    /// were two of those sitting four points apart, which is a coin toss rather
    /// than a pair of targets. The frame is the fix, not the gap: two 44pt
    /// targets four points apart are unambiguous.
    private func glyph(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
            .contentShape(.rect)
    }

    private var separator: some View {
        Divider()
            .frame(height: separatorHeight)
            .overlay(theme.rule)
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
        // ⌘B / ⌘I / ⌘U, which every text field on the platform has and this
        // app had none of. Attached to the button rather than declared
        // separately so the shortcut cannot outlive the control — a density
        // that drops italic also drops ⌘I, which is correct: a shortcut for a
        // button that is not on screen is a hidden feature, and one that fires
        // while the bar is dismissed would edit a block nobody is looking at.
        .modifier(StyleShortcut(style: style))
        .accessibilityLabel(Text(style.displayName))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: - Overflow

    private func overflowMenu(_ controls: [FormattingControl]) -> some View {
        Menu {
            ForEach(controls, id: \.self) { control in
                menuItem(control)
            }
        } label: {
            glyph("ellipsis.circle")
        }
        .accessibilityLabel(Text("More formatting"))
    }

    @ViewBuilder
    private func menuItem(_ control: FormattingControl) -> some View {
        switch control {
        case .undo:
            Button {
                session.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!session.canUndo)

        case .redo:
            Button {
                session.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!session.canRedo)

        case .style(let style):
            // A `Toggle` rather than a `Button`, so the menu draws the checkmark
            // and VoiceOver gets the on/off state the inline button also has.
            Toggle(isOn: styleBinding(style)) {
                Label {
                    Text(style.displayName)
                } icon: {
                    Image(systemName: style.systemImage)
                }
            }

        case .insertLink:
            Button {
                session.startLink()
            } label: {
                Label("Link to a Note", systemImage: "link.badge.plus")
            }

        case .openLink:
            // Never gets here. Following the link under the caret stays on the
            // bar at every density, and `FormattingToolbarTests` is what keeps
            // that true rather than this comment.
            EmptyView()
        }
    }

    private func styleBinding(_ style: InlineStyle) -> Binding<Bool> {
        Binding(
            get: { session.activeStyle.contains(style) },
            // The session owns the toggle; the new value is whatever the editor
            // reports back, not what the menu assumed.
            set: { _ in session.toggle(style) }
        )
    }
}

/// The keyboard equivalent for a mark, where one exists.
///
/// A `ViewModifier` rather than an inline `if`: `keyboardShortcut` returns a
/// different type from the view it is applied to, so branching inline would
/// need `AnyView` or a `Group`, and both cost more than this does.
private struct StyleShortcut: ViewModifier {
    let style: InlineStyle

    func body(content: Content) -> some View {
        if let key = style.keyEquivalent {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}

extension InlineStyle {
    /// Only the three the platform has trained everyone to expect. Code and
    /// strikethrough have no conventional shortcut, and inventing one would be
    /// a binding nobody guesses and every other app disagrees with.
    var keyEquivalent: KeyEquivalent? {
        switch self {
        case .bold: "b"
        case .italic: "i"
        case .underline: "u"
        default: nil
        }
    }
}
