import SwiftData
import SwiftUI
import UIKit

/// Scan a receipt, check what was read, keep it.
///
/// The review step is the whole design. OCR on a crumpled till roll is right
/// most of the time and confidently wrong the rest, and the number it gets
/// wrong goes into an expense total somebody later claims. So nothing is saved
/// until it has been shown, everything is editable, and a field that could not
/// be read is left visibly blank rather than filled with a guess.
///
/// What comes out is an ordinary note. There is no receipt block, no receipt
/// template id, and nothing downstream knows this screen exists — search,
/// export, the fore-edge and the vault all treat it as the heading, table,
/// metric and place that it is.
struct ReceiptScanSheet: View {
    /// Where the finished note should be filed. Passing the folder in is what
    /// makes "everything from this trip" work without this screen knowing what
    /// a trip is.
    var folder: Folder?

    let onSaved: (Note) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(HapticEngine.self) private var haptics

    @State private var stage: Stage = .ready
    @State private var pages: [UIImage] = []
    @State private var receipt = Receipt()
    @State private var place: ResolvedPlace?
    @State private var chosenFolder: Folder?
    @State private var failure: String?

    @State private var location = LocationAuthority()

    @Query(sort: [SortDescriptor(\Folder.position)]) private var folders: [Folder]

    private enum Stage: Equatable {
        case ready
        case scanning
        case reading
        case review
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .ready: readyState
                case .scanning: Color.clear
                case .reading: readingState
                case .review: reviewForm
                }
            }
            .background(theme.canvas.ignoresSafeArea())
            .navigationTitle("Scan a Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if stage == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save).fontWeight(.semibold)
                    }
                }
            }
            .fullScreenCover(isPresented: scanning) {
                DocumentScannerView { outcome in
                    switch outcome {
                    case .scanned(let images): read(images)
                    case .cancelled: stage = pages.isEmpty ? .ready : .review
                    case .failed(let error):
                        failure = error.localizedDescription
                        stage = pages.isEmpty ? .ready : .review
                    }
                }
                .ignoresSafeArea()
            }
            .alert(
                "Couldn't read that",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
                presenting: failure
            ) { _ in
                Button("OK", role: .cancel) { failure = nil }
            } message: { Text($0) }
            .task {
                chosenFolder = folder
                // Asked for on open rather than at save, so the answer has
                // arrived by the time it is needed. A receipt is scanned where
                // it was bought; a minute later in the car it is not.
                location.requestAuthorization()
                location.refreshLocation()
            }
        }
    }

    private var scanning: Binding<Bool> {
        Binding(get: { stage == .scanning }, set: { if !$0 && stage == .scanning { stage = .ready } })
    }

    // MARK: - Stages

    private var readyState: some View {
        VStack(spacing: Layout.Space.regular) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: Layout.Space.airy, weight: .light))
                .foregroundStyle(theme.inkTertiary)

            Text("Photograph the receipt")
                .versoText(.title)
                .foregroundStyle(theme.ink)

            Text("The amount, the shop and the date are read off it. You can correct anything before it is saved.")
                .versoText(.chromeCaption)
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Layout.Space.loose)

            if DocumentScannerView.isSupported {
                Button {
                    stage = .scanning
                } label: {
                    Text("Scan")
                        .versoText(.chromeBody)
                        .padding(.horizontal, Layout.Space.loose)
                        .padding(.vertical, Layout.Space.cosy)
                        .frame(minHeight: Layout.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.stock)
                .background(theme.accent, in: .rect(cornerRadius: Layout.Radius.capsule))
            } else {
                // Says why rather than showing a button that opens a black
                // screen. The simulator lands here, and so does an iPad without
                // a usable camera.
                Text("This device has no camera Verso can scan with.")
                    .versoText(.chromeCaption)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Layout.Space.loose)
    }

    private var readingState: some View {
        VStack(spacing: Layout.Space.cosy) {
            ProgressView().controlSize(.large).tint(theme.inkTertiary)
            Text("Reading the receipt")
                .versoText(.chromeCaption)
                .foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Review

    private var reviewForm: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.Space.loose) {
                if let first = pages.first {
                    Image(uiImage: first)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: Layout.Space.vast * 5)
                        .clipShape(.rect(cornerRadius: Layout.Radius.regular))
                        .overlay {
                            RoundedRectangle(cornerRadius: Layout.Radius.regular)
                                .strokeBorder(theme.cardBorder, lineWidth: Layout.hairline)
                        }
                        .accessibilityLabel(Text("The receipt as photographed"))
                }

                SettingsGroup(
                    title: "What was read",
                    footnote: "Anything left blank could not be read off the paper. Nothing is guessed."
                ) {
                    field("Shop", text: $receipt.merchant, prompt: "Not read")
                    SettingsDivider()
                    amountField
                    SettingsDivider()
                    SettingsRow(title: "Date") {
                        SettingsValue(text: dateDescription)
                    }
                    if let place {
                        SettingsDivider()
                        SettingsRow(title: "Where") { SettingsValue(text: place.name) }
                    }
                }

                if !receipt.items.isEmpty {
                    SettingsGroup(title: "Items") {
                        ForEach(Array(receipt.items.enumerated()), id: \.offset) { index, item in
                            if index > 0 { SettingsDivider() }
                            SettingsRow(title: LocalizedStringResource(stringLiteral: item.label)) {
                                SettingsValue(text: item.amount.map(money) ?? "—")
                            }
                        }
                    }
                }

                filingGroup
            }
            .padding(.horizontal, Layout.Space.regular)
            .padding(.vertical, Layout.Space.snug)
        }
    }

    /// Which pile this goes on. The answer to "multiple per day" and "a whole
    /// work trip" is the same answer, because a folder already is that.
    private var filingGroup: some View {
        SettingsGroup(
            title: "Keep it with",
            footnote: "Receipts in one folder add up together — a trip, an event, or a month."
        ) {
            Menu {
                Button("Nothing in particular") { chosenFolder = nil }
                ForEach(folders) { candidate in
                    Button(candidate.name) { chosenFolder = candidate }
                }
            } label: {
                SettingsRow(title: "Folder") {
                    SettingsValue(text: chosenFolder?.name ?? String(localized: "None"))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Folder"))
            .accessibilityValue(Text(chosenFolder?.name ?? String(localized: "None")))
        }
    }

    private func field(
        _ title: LocalizedStringResource,
        text: Binding<String>,
        prompt: LocalizedStringResource
    ) -> some View {
        SettingsRow(title: title) {
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(theme.inkTertiary))
                .multilineTextAlignment(.trailing)
                .versoText(.chromeLabel)
                .foregroundStyle(theme.ink)
                .accessibilityLabel(Text(title))
        }
    }

    private var amountField: some View {
        SettingsRow(title: "Total") {
            TextField(
                "",
                value: $receipt.total,
                format: .number.precision(.fractionLength(2)),
                prompt: Text("Not read").foregroundStyle(theme.inkTertiary)
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .versoText(.chromeLabel)
            .foregroundStyle(theme.ink)
            .accessibilityLabel(Text("Total"))
        }
    }

    private var dateDescription: String {
        let when = receipt.purchasedAt ?? Date()
        return when.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }

    private func money(_ amount: Double) -> String {
        receipt.currency.isEmpty
            ? amount.formatted(.number.precision(.fractionLength(2)))
            : "\(receipt.currency)\(amount.formatted(.number.precision(.fractionLength(2))))"
    }

    // MARK: - Work

    private func read(_ images: [UIImage]) {
        pages = images
        stage = .reading

        Task {
            defer { stage = .review }
            do {
                let lines = try await TextRecognition.lines(in: images)
                receipt = ReceiptReader.read(lines)
            } catch {
                // A scan that cannot be read is still a scan. The picture is
                // kept and the fields are left empty for the user to fill —
                // losing the photograph because the text was illegible would be
                // the worst possible response to a bad photograph.
                failure = error.localizedDescription
            }
            place = await nearestPlace()
        }
    }

    /// Where this was, if the device knows. Best-effort by design: no
    /// permission, no signal, or nothing nearby all mean the note simply has no
    /// place block.
    private func nearestPlace() async -> ResolvedPlace? {
        // `allowsMonitoring` rather than a specific case: it already means
        // "the device will tell us where we are", covers reduced accuracy —
        // which is plenty for naming a shop — and is the same test the place
        // block uses, so the two cannot disagree about what permission means.
        guard location.availability.allowsMonitoring, let here = location.userLocation else { return nil }
        return await PlaceResolver.resolve(category: "restaurant", near: here, limit: 1).first
            ?? ResolvedPlace(name: String(localized: "Where this was scanned"), coordinate: here)
    }

    private func save() {
        do {
            let note = try TemplateInstantiator.makeNote(
                from: receipt.makeTemplate(scannedAt: Date(), place: place),
                in: context
            )

            // The photograph goes in first, because it is the evidence and the
            // rest is a reading of it. Prepending rather than appending means
            // the note opens on the receipt.
            if let first = pages.first {
                try attach(first, to: note)
            }

            note.folder = chosenFolder
            note.touch()

            haptics.play(.checklistCheck)
            onSaved(note)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func attach(_ image: UIImage, to note: Note) throws {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let payload = try ImageStore.importImage(
            data: data,
            atPageWidth: ImagePayload.assumedPageWidth,
            into: note,
            context: context
        )

        let block = try BlockRegistry.shared.makeBlock(of: .image)
        try block.store(payload)
        context.insert(block)
        note.insert(block, at: 0)
    }
}
