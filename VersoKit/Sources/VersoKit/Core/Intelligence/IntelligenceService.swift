import Foundation
import SwiftData

/// The app's one entry point to anything intelligent.
///
/// It picks a provider at launch and never changes shape afterwards: callers
/// ask for a title and get one, whether it came from a language model or from
/// counting words. Section 1 requires the app to be fully usable without Apple
/// Intelligence, and the way to guarantee that is for the rest of the app not
/// to know which it got.
@MainActor
@Observable
final class IntelligenceService {

    private(set) var availability: IntelligenceAvailability
    private(set) var isWorking = false

    private let provider: any IntelligenceProvider

    init() {
        #if canImport(FoundationModels)
        let availability = FoundationModelsIntelligence.availability
        self.availability = availability
        self.provider = availability.isAvailable
            ? FoundationModelsIntelligence()
            : HeuristicIntelligence()
        #else
        self.availability = .frameworkUnavailable
        self.provider = HeuristicIntelligence()
        #endif
    }

    /// For tests, and for forcing the fallback path in Settings.
    init(provider: any IntelligenceProvider, availability: IntelligenceAvailability = .available) {
        self.provider = provider
        self.availability = availability
    }

    /// Whether the *model-backed* version is running.
    ///
    /// Nothing in the UI branches on this to decide whether to show a feature —
    /// every feature is always shown, because every feature always works. It is
    /// for the one line in Settings that explains what is doing the work.
    var isUsingOnDeviceModel: Bool { availability.isAvailable }

    // MARK: - Operations

    func suggestTitle(for note: Note) async -> String? {
        await run { await provider.suggestTitle(for: NoteDigest(note)) }
    }

    /// Applies a title only to a note that has none.
    ///
    /// Section 7 says auto-title on first save. Overwriting a title somebody
    /// chose would be the app deciding it knows better.
    @discardableResult
    func autoTitleIfNeeded(_ note: Note) async -> Bool {
        guard note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let title = await suggestTitle(for: note), !title.isEmpty else { return false }
        guard note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        note.title = title
        note.touch()
        return true
    }

    func suggestTags(for note: Note, in context: ModelContext) async -> [String] {
        let existing = ((try? context.fetch(FetchDescriptor<Tag>())) ?? [])
            .map(\.name)
            .filter { !$0.isEmpty }
        guard !existing.isEmpty else { return [] }

        return await run { await provider.suggestTags(for: NoteDigest(note), existing: existing) }
    }

    func summarise(_ note: Note) async -> [String] {
        await run { await provider.summarise(NoteDigest(note)) }
    }

    func extractActions(from note: Note) async -> [String] {
        await run { await provider.extractActions(from: NoteDigest(note)) }
    }

    func structure(_ text: String) async -> CapturedNote {
        await run { await provider.structure(text) }
    }

    /// Builds a note from free text — pasted, or spoken.
    func makeNote(from text: String, in context: ModelContext) async throws -> Note {
        let captured = await structure(text)
        return try TemplateInstantiator.makeNote(from: captured.makeTemplate(), in: context)
    }

    private func run<T>(_ work: () async -> T) async -> T {
        isWorking = true
        defer { isWorking = false }
        return await work()
    }
}
