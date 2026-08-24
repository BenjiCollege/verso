import SwiftData
import SwiftUI
import UIKit
import WidgetKit

/// The sheet another app's Share button opens.
///
/// The third thing `VersoKit` makes public, after the scene and the widgets,
/// and for the same reason: the extension target holds `@main` and nothing
/// else, so the store, the theme and the note writer here are the app's own
/// code rather than a second copy that can drift.
///
/// It deliberately does *not* look like a system share sheet. Cards on a
/// canvas, the app's type, the app's paper: the point of sharing into Verso is
/// that what you get back is a page, and the sheet should say so before the
/// Save button is tapped.
public struct ShareCaptureView: View {

    private let items: [NSExtensionItem]
    private let onSaved: () -> Void
    private let onCancel: () -> Void

    public init(
        items: [NSExtensionItem],
        onSaved: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.items = items
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    @Environment(\.colorScheme) private var systemColorScheme

    /// The heuristic provider, not the model-backed one.
    ///
    /// A share extension gets a fraction of the app's memory and is killed
    /// rather than paged when it goes over, and a language-model session is the
    /// largest single thing this codebase can allocate. `HeuristicIntelligence`
    /// finds the same lists, headings and quantities by parsing, which is most
    /// of what a shared page needs — so this takes the deterministic path on
    /// purpose rather than as a fallback.
    @State private var intelligence = IntelligenceService(
        provider: HeuristicIntelligence(),
        availability: .frameworkUnavailable
    )

    @State private var capture: SharedCapture?
    @State private var title = ""
    @State private var isSaving = false
    @State private var failure: String?

    /// The bundled catalogue and the default theme for the system's appearance.
    ///
    /// Not the user's chosen theme: `AppearanceStore` writes to the app's own
    /// `UserDefaults`, which this process cannot see, and moving those
    /// preferences into the app group would orphan every existing setting. A
    /// share sheet is open for seconds, so default paper is a small price; the
    /// migration that would fix it is not this change's to take.
    private var catalog: ThemeCatalog { .shared }

    private var theme: Theme {
        catalog.defaultTheme(for: systemColorScheme == .dark ? .dark : .light)
    }

    private var canSave: Bool {
        guard let capture, !capture.isEmpty else { return false }
        return !isSaving
    }

    public var body: some View {
        NavigationStack {
            sheet
                .navigationTitle("Save to Verso")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!canSave)
                    }
                }
        }
        .environment(\.themeCatalog, catalog)
        .versoTheme(theme, stock: catalog.resolveStock(selectedID: nil))
        .versoMotion()
        .task {
            let loaded = await SharedCaptureLoader.load(from: items)
            capture = loaded
            title = loaded.suggestedTitle
        }
    }

    private var sheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.Space.regular) {
                if let capture, !capture.isEmpty {
                    titleField
                    SharedPreview(capture: capture)
                } else if let capture, capture.isEmpty {
                    // Save is disabled here, and a disabled button with nothing
                    // beside it is a dead end. Say why instead.
                    Text("There was nothing in that share Verso could read.")
                        .versoText(.chromeLabel)
                        .foregroundStyle(theme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .versoCard()
                } else {
                    // A sentence rather than a spinner: reading an item
                    // provider takes a frame or two, and a spinner that flashes
                    // for one frame reads as a fault.
                    Text("Reading what was shared…")
                        .versoText(.chromeLabel)
                        .foregroundStyle(theme.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Layout.Space.loose)
                }

                if let failure {
                    Text(verbatim: failure)
                        .versoText(.chromeCaption)
                        .foregroundStyle(theme.accentAlternate)
                        .versoCard()
                }
            }
            .padding(Layout.Space.regular)
            .animation(.settle, value: capture)
        }
        .background { theme.canvas.ignoresSafeArea() }
        .scrollDismissesKeyboard(.interactively)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: Layout.Space.tight) {
            SectionLabel(title: "Title")
            TextField(
                "Title",
                text: $title,
                prompt: Text("Untitled").foregroundStyle(theme.inkTertiary)
            )
            .textFieldStyle(.plain)
            .versoText(.body)
            .foregroundStyle(theme.ink)
            .frame(minHeight: Layout.minimumHitTarget)
            .versoCard()
            .accessibilityLabel(Text("Note title"))
        }
    }

    private func save() {
        guard let capture, canSave else { return }
        isSaving = true
        failure = nil

        Task { @MainActor in
            do {
                try await SharedCaptureWriter.write(
                    capture,
                    title: title,
                    in: ModelContext(VersoIntentContainer.shared),
                    intelligence: intelligence
                )
                // The Home Screen is often the next thing seen after a share
                // sheet closes, and a widget still listing the previous note
                // makes the save look as though it did not happen.
                WidgetCenter.shared.reloadAllTimelines()
                onSaved()
            } catch {
                isSaving = false
                failure = String(localized: "That couldn't be saved. Try again, or open Verso and paste it in.")
                SharedCaptureWriter.logger.error(
                    "Share save failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}

// MARK: - Preview of what arrived

/// What the other app handed over, shown before it is committed.
///
/// A Save button over a sheet that does not show what is being saved is a
/// guess, and the one thing a share extension must never be is a guess: the
/// content came from somewhere else and the user is the only one who can say
/// it is the right thing.
private struct SharedPreview: View {
    let capture: SharedCapture

    @Environment(\.theme) private var theme

    /// Scales with the type size, so a thumbnail beside AX5 text is not a
    /// postage stamp next to a headline.
    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.tight) {
            SectionLabel(title: "Shared", detail: detail)

            VStack(alignment: .leading, spacing: Layout.Space.cosy) {
                if !capture.images.isEmpty {
                    imageStrip
                }

                ForEach(capture.links, id: \.self) { link in
                    linkRow(link)
                }

                if !capture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(verbatim: capture.text)
                        .versoText(.body)
                        .foregroundStyle(theme.ink)
                        // Enough to recognise what this is without the sheet
                        // becoming the place you read it.
                        .lineLimit(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .versoCard()
        }
    }

    private var detail: String? {
        var parts: [String] = []
        if !capture.images.isEmpty {
            parts.append(String(localized: "\(capture.images.count) pictures"))
        }
        if !capture.links.isEmpty {
            parts.append(String(localized: "\(capture.links.count) links"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var imageStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Layout.Space.snug) {
                ForEach(Array(capture.images.enumerated()), id: \.offset) { index, data in
                    thumbnail(data, index: index)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func thumbnail(_ data: Data, index: Int) -> some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(.rect(cornerRadius: Layout.Radius.tight))
                .accessibilityLabel(Text("Shared picture \(index + 1)"))
        }
    }

    private func linkRow(_ link: URL) -> some View {
        HStack(spacing: Layout.Space.snug) {
            Image(systemName: "link")
                .foregroundStyle(theme.accent)
            Text(verbatim: link.absoluteString)
                .versoText(.callout)
                .foregroundStyle(theme.inkSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Link"))
        .accessibilityValue(Text(verbatim: link.absoluteString))
    }
}
