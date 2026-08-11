import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why the on-device model can or cannot be used.
enum IntelligenceAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady
    case frameworkUnavailable
    case other(String)

    var isAvailable: Bool { self == .available }

    /// Shown only in Settings.
    ///
    /// Section 7: unavailable affordances are hidden entirely, never disabled.
    /// A greyed-out button is a smaller version of a feature you cannot have,
    /// which is worse than no button — so this message exists to answer
    /// "why don't I see that?", not to sit next to a dead control.
    var explanation: String? {
        switch self {
        case .available:
            nil
        case .deviceNotEligible:
            String(localized: "This device doesn't support Apple Intelligence. Verso works fully without it.")
        case .notEnabled:
            String(localized: "Apple Intelligence is turned off. You can turn it on in Settings.")
        case .modelNotReady:
            String(localized: "Apple Intelligence is still preparing. This usually sorts itself out shortly.")
        case .frameworkUnavailable:
            String(localized: "On-device models aren't available in this build.")
        case .other(let reason):
            reason
        }
    }
}

#if canImport(FoundationModels)

/// Structured output types.
///
/// `@Generable` means the model returns these directly rather than prose to be
/// parsed — which is the whole reason section 7 specifies guided generation.
/// Parsing a model's free text is where AI features go to become flaky.
@Generable
struct GeneratedTitle {
    @Guide(description: "A title of at most eight words. No quotation marks, no trailing full stop.")
    var title: String
}

@Generable
struct GeneratedTags {
    @Guide(description: "Tags chosen only from the supplied list. Never invent one. At most five.")
    var tags: [String]
}

@Generable
struct GeneratedSummary {
    @Guide(description: "Exactly three bullet points, each one sentence, each from the note itself.")
    var bullets: [String]
}

@Generable
struct GeneratedActions {
    @Guide(description: "Things somebody has to do, phrased as instructions. Empty if there are none.")
    var actions: [String]
}

@Generable
struct GeneratedItem {
    var label: String
    @Guide(description: "How many, if the text says. Omit otherwise.")
    var quantity: Double?
    @Guide(description: "The unit, such as g or tbsp, if the text says. Omit otherwise.")
    var unit: String?
}

@Generable
struct GeneratedSection {
    @Guide(description: "A short heading for this section.")
    var heading: String
    @Guide(description: "Items, if this section is a list of things to get or do. Empty otherwise.")
    var items: [GeneratedItem]
    @Guide(description: "The prose of this section, if it is not a list. Empty otherwise.")
    var prose: String
}

@Generable
struct GeneratedNote {
    @Guide(description: "A title of at most eight words.")
    var title: String
    @Guide(description: "The note's sections, in the order they appear in the source text.")
    var sections: [GeneratedSection]
}

/// The on-device language model.
///
/// Every method falls back to the heuristic provider rather than failing:
/// generation can refuse, exceed its context, or be interrupted, and none of
/// those are worth showing a user an error over when a perfectly good answer is
/// available a line below.
struct FoundationModelsIntelligence: IntelligenceProvider {

    let fallback = HeuristicIntelligence()

    static var availability: IntelligenceAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: .deviceNotEligible
            case .appleIntelligenceNotEnabled: .notEnabled
            case .modelNotReady: .modelNotReady
            @unknown default: .other(String(localized: "Unavailable on this device."))
            }
        }
    }

    /// Notes can be long and the context window is not. Truncating explicitly
    /// beats being refused for length.
    private static let maximumCharacters = 6_000

    private func session(_ instructions: String) -> LanguageModelSession {
        LanguageModelSession(instructions: instructions)
    }

    private func clipped(_ text: String) -> String {
        String(text.prefix(Self.maximumCharacters))
    }

    // MARK: - IntelligenceProvider

    func suggestTitle(for digest: NoteDigest) async -> String? {
        guard !digest.isEmpty else { return nil }

        do {
            let response = try await session(
                "You name notes. Reply with a short, plain title describing what the note is about. Never add commentary."
            )
            .respond(to: "Title this note:\n\n\(clipped(digest.text))", generating: GeneratedTitle.self)

            let title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? await fallback.suggestTitle(for: digest) : title
        } catch {
            return await fallback.suggestTitle(for: digest)
        }
    }

    func suggestTags(for digest: NoteDigest, existing: [String]) async -> [String] {
        guard !digest.isEmpty, !existing.isEmpty else { return [] }

        do {
            let response = try await session(
                "You tag notes using only tags that already exist. You never invent a tag."
            )
            .respond(
                to: """
                Existing tags: \(existing.joined(separator: ", "))

                Note:
                \(clipped(digest.text))

                Which existing tags apply?
                """,
                generating: GeneratedTags.self
            )

            // Constrained twice: once in the prompt, once here. A model that
            // invents a tag anyway must not be able to widen the vocabulary.
            let allowed = Set(existing.map { $0.lowercased() })
            let filtered = response.content.tags.filter { allowed.contains($0.lowercased()) }
            return filtered.isEmpty ? await fallback.suggestTags(for: digest, existing: existing) : Array(filtered.prefix(5))
        } catch {
            return await fallback.suggestTags(for: digest, existing: existing)
        }
    }

    func summarise(_ digest: NoteDigest) async -> [String] {
        guard !digest.isEmpty else { return [] }

        do {
            let response = try await session(
                "You summarise notes in exactly three short bullets. You only state things the note says."
            )
            .respond(to: "Summarise this note:\n\n\(clipped(digest.text))", generating: GeneratedSummary.self)

            let bullets = response.content.bullets
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return bullets.isEmpty ? await fallback.summarise(digest) : Array(bullets.prefix(3))
        } catch {
            return await fallback.summarise(digest)
        }
    }

    func extractActions(from digest: NoteDigest) async -> [String] {
        guard !digest.isEmpty else { return [] }

        do {
            let response = try await session(
                "You find action items in meeting notes. If there are none, you return none rather than inventing any."
            )
            .respond(to: "Find the actions in this note:\n\n\(clipped(digest.text))", generating: GeneratedActions.self)

            return response.content.actions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            return await fallback.extractActions(from: digest)
        }
    }

    func structure(_ text: String) async -> CapturedNote {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return CapturedNote() }

        do {
            let response = try await session(
                """
                You turn pasted text into a structured note. Lists of things to buy or do become items \
                with quantities where the text gives them. Everything else stays as prose. You never add \
                anything the text does not contain.
                """
            )
            .respond(to: "Structure this:\n\n\(clipped(text))", generating: GeneratedNote.self)

            let captured = CapturedNote(
                title: response.content.title.trimmingCharacters(in: .whitespacesAndNewlines),
                sections: response.content.sections.map { section in
                    CapturedNote.Section(
                        heading: section.heading.trimmingCharacters(in: .whitespacesAndNewlines),
                        items: section.items.compactMap { item in
                            let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !label.isEmpty else { return nil }
                            return CapturedNote.Item(label: label, quantity: item.quantity, unit: item.unit)
                        },
                        prose: section.prose.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            )

            // A model that returns nothing useful is worse than the parser,
            // which at least preserves what was pasted.
            return captured.isEmpty ? await fallback.structure(text) : captured
        } catch {
            return await fallback.structure(text)
        }
    }
}

#endif
