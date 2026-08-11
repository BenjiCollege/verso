import SwiftData
import SwiftUI

/// Paste something in, or say it, and get a note with structure.
///
/// The same path either way: text goes to `IntelligenceService.structure`,
/// which returns a `CapturedNote`, which becomes a `Template`, which is
/// instantiated by the same code every other template uses.
struct CaptureSheet: View {
    let onCreate: (Note) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(IntelligenceService.self) private var intelligence

    @State private var speech = SpeechTranscription()
    @State private var text = ""
    @State private var preview: CapturedNote?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .versoText(.body)
                        .foregroundStyle(theme.ink)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Paste a recipe, a list, or anything with a shape to it.")
                                    .versoText(.body)
                                    .foregroundStyle(theme.inkTertiary)
                                    .padding(.top, Layout.Space.snug)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Text")
                } footer: {
                    // Section 7: hide unavailable affordances entirely. If the
                    // device cannot transcribe on-device, there is no button.
                    if speech.isSupported {
                        dictationRow
                    } else if case .unavailable(let reason) = speech.state {
                        Text(reason)
                    }
                }

                if let preview, !preview.isEmpty {
                    Section("What Verso found") {
                        ForEach(Array(preview.sections.enumerated()), id: \.offset) { _, section in
                            sectionSummary(section)
                        }
                    }
                }
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
            }
            .onChange(of: speech.transcript) { _, transcript in
                if !transcript.isEmpty { text = transcript }
            }
            .task(id: text) {
                // Debounced so every keystroke does not start a generation.
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, !text.isEmpty else { return }
                preview = await intelligence.structure(text)
            }
        }
    }

    private var dictationRow: some View {
        Button {
            Task {
                if speech.isListening {
                    text = speech.stop()
                } else {
                    await speech.start()
                }
            }
        } label: {
            Label(
                speech.isListening ? "Stop listening" : "Dictate",
                systemImage: speech.isListening ? "stop.circle.fill" : "mic"
            )
            .foregroundStyle(speech.isListening ? theme.accent : theme.inkSecondary)
        }
        .buttonStyle(.plain)
        .frame(minHeight: Layout.minimumHitTarget)
        .accessibilityHint(Text("Transcription happens on this device. Nothing is sent anywhere."))
    }

    private func sectionSummary(_ section: CapturedNote.Section) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.hair) {
            if !section.heading.isEmpty {
                Text(section.heading)
                    .versoText(.metadata)
                    .foregroundStyle(theme.inkSecondary)
            }
            if !section.items.isEmpty {
                Text("\(section.items.count) items")
                    .versoText(.chromeCaption)
                    .foregroundStyle(theme.inkTertiary)
            }
            if !section.prose.isEmpty {
                Text(section.prose)
                    .versoText(.chromeCaption)
                    .foregroundStyle(theme.inkTertiary)
                    .lineLimit(2)
            }
        }
    }

    private func create() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            guard let note = try? await intelligence.makeNote(from: text, in: context) else { return }
            onCreate(note)
            dismiss()
        }
    }
}
