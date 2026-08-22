import Foundation
import NaturalLanguage
import OSLog
import SwiftData

/// A note, ranked against a query.
struct SearchHit: Identifiable, Hashable, Sendable {
    var id: UUID { noteID }
    var noteID: UUID
    var score: Double
    /// The line the match came from, for showing under the title.
    var excerpt: String
    var isSemantic: Bool
}

/// Searching by meaning, with searching by words underneath it.
///
/// The embeddings come from `NLEmbedding`, which is on-device and available far
/// more widely than Apple Intelligence — so semantic search is not gated behind
/// it. Where embeddings are unavailable for the user's language, lexical
/// scoring carries the whole feature rather than half of it.
/// Not `Sendable`: it holds an `NLEmbedding`, which is not. It never needs to
/// cross an isolation boundary — one is built where a search is run, and only
/// `SearchHit` and `Entry` travel.
struct SemanticIndex {

    static let logger = Logger(subsystem: "com.verso.notes", category: "search")

    struct Entry: Sendable {
        var noteID: UUID
        var title: String
        var text: String
        var isLocked: Bool
    }

    /// The language to score in.
    ///
    /// Derived from the device rather than fixed at English, because fixing it
    /// is what turns the lexical fallback into a lie: a French library scored
    /// against English vectors does not fall back, it matches badly. Where the
    /// device's language has no sentence embedding, `embedding` is `nil` and
    /// the lexical path carries the whole feature — which is the intended
    /// behaviour, and could never be reached while this said `.english`.
    static var preferredLanguage: NLLanguage {
        guard let code = Locale.current.language.languageCode?.identifier else { return .english }
        return NLLanguage(rawValue: code)
    }

    /// `nil` when the device has no sentence embedding for this language.
    private let embedding: NLEmbedding?

    init(language: NLLanguage = SemanticIndex.preferredLanguage) {
        self.embedding = NLEmbedding.sentenceEmbedding(for: language)
    }

    var supportsSemanticMatching: Bool { embedding != nil }

    // MARK: - Searching

    func search(_ query: String, in entries: [Entry], limit: Int = 40) -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Section 7: locked and hidden notes are excluded from indexing, and
        // search is indexing by another name.
        let searchable = entries.filter { !$0.isLocked }

        let lexical = searchable.compactMap { entry -> SearchHit? in
            guard let (score, excerpt) = lexicalScore(query: trimmed, entry: entry) else { return nil }
            return SearchHit(noteID: entry.noteID, score: score, excerpt: excerpt, isSemantic: false)
        }

        guard let embedding else {
            return Array(lexical.sorted { $0.score > $1.score }.prefix(limit))
        }

        var byNote: [UUID: SearchHit] = Dictionary(uniqueKeysWithValues: lexical.map { ($0.noteID, $0) })

        for entry in searchable {
            guard let (distance, excerpt) = semanticDistance(query: trimmed, entry: entry, embedding: embedding) else {
                continue
            }
            // NLEmbedding returns a distance; nearer is better.
            let score = max(0, 1 - distance)
            guard score > 0.45 else { continue }

            // A note that matches both ways should outrank one that matches
            // either, but a literal match is never demoted by a weak semantic
            // one.
            if let existing = byNote[entry.noteID] {
                byNote[entry.noteID] = SearchHit(
                    noteID: entry.noteID,
                    score: existing.score + score * 0.5,
                    excerpt: existing.excerpt,
                    isSemantic: true
                )
            } else {
                byNote[entry.noteID] = SearchHit(
                    noteID: entry.noteID,
                    score: score,
                    excerpt: excerpt,
                    isSemantic: true
                )
            }
        }

        return Array(byNote.values.sorted { $0.score > $1.score }.prefix(limit))
    }

    // MARK: - Scoring

    /// Title matches beat body matches, prefixes beat contains, and every
    /// query word has to appear somewhere.
    private func lexicalScore(query: String, entry: Entry) -> (Double, String)? {
        let needle = HeuristicIntelligence.fold(query)
        let title = HeuristicIntelligence.fold(entry.title)
        let body = HeuristicIntelligence.fold(entry.text)

        let words = needle.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        guard words.allSatisfy({ title.contains($0) || body.contains($0) }) else { return nil }

        var score = 0.0
        if title.contains(needle) { score += 3 }
        if title.hasPrefix(needle) { score += 2 }
        if body.contains(needle) { score += 1.5 }
        score += Double(words.count { title.contains($0) }) * 0.5
        score += Double(words.count { body.contains($0) }) * 0.25

        return (score, excerpt(containing: words.first ?? needle, in: entry.text))
    }

    private func semanticDistance(query: String, entry: Entry, embedding: NLEmbedding) -> (Double, String)?
    {
        let candidates = HeuristicIntelligence.sentences(in: entry.text).prefix(24)
        guard !candidates.isEmpty else { return nil }

        var best: (distance: Double, sentence: String)?
        for sentence in candidates {
            let distance = embedding.distance(between: query, and: sentence)
            // A distance of zero means one of the two produced no vector.
            guard distance > 0 else { continue }
            if best == nil || distance < best!.distance {
                best = (distance, sentence)
            }
        }

        guard let best else { return nil }
        return (best.distance, HeuristicIntelligence.truncate(best.sentence, toWords: 22))
    }

    private func excerpt(containing needle: String, in text: String) -> String {
        for line in text.split(separator: "\n") {
            if HeuristicIntelligence.fold(String(line)).contains(needle) {
                return HeuristicIntelligence.truncate(String(line).trimmingCharacters(in: .whitespaces), toWords: 22)
            }
        }
        return HeuristicIntelligence.truncate(text.trimmingCharacters(in: .whitespacesAndNewlines), toWords: 22)
    }
}

/// Runs a search off the main actor.
///
/// Both halves of a search are expensive and neither belongs on the thread that
/// has to draw the result: building the entries decodes every block of every
/// note, and scoring them loads a sentence-embedding model and walks up to 24
/// sentences per note. `@ModelActor` gives this its own `ModelContext` so the
/// first half is safe off the main actor, and keeping `SemanticIndex` as actor
/// state means the model is loaded once per session rather than once per
/// keystroke. Only `SearchHit` — which is `Sendable` — crosses back.
@ModelActor
actor SearchIndexSource {

    /// Held rather than rebuilt because the initialiser loads an `NLEmbedding`.
    /// Not `Sendable`, which is exactly why it lives inside an actor.
    private var index: SemanticIndex?

    /// Entries, scored, in one hop across the isolation boundary.
    func search(_ query: String, limit: Int = 40) -> [SearchHit] {
        let index = index ?? SemanticIndex()
        self.index = index
        return index.search(query, in: entries(), limit: limit)
    }

    func entries() -> [SemanticIndex.Entry] {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { !$0.isTrashed && !$0.isHidden }
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []

        return notes.map { note in
            SemanticIndex.Entry(
                noteID: note.id,
                title: note.title,
                // `VaultPolicy` decides what may be indexed; a locked note
                // contributes nothing but is still listed so it is not silently
                // missing from the count.
                text: VaultPolicy.isEligibleForIndexing(note)
                    ? note.orderedBlocks.map { BlockRegistry.shared.plainText(for: $0) }.joined(separator: "\n")
                    : "",
                isLocked: !VaultPolicy.isEligibleForIndexing(note)
            )
        }
    }
}
