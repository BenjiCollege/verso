import Foundation
import NaturalLanguage

/// Everything the app can do without a language model.
///
/// This is not a stub. Section 1 requires the app to be fully usable on a
/// device with no Apple Intelligence support, which means these have to be good
/// enough that nobody feels they are missing out — and in practice, for titling
/// and for parsing a pasted list, structure beats inference anyway.
struct HeuristicIntelligence: IntelligenceProvider {

    // MARK: - Titling

    /// The first heading, or the first sentence. A note's opening line is
    /// almost always what it is about.
    func suggestTitle(for digest: NoteDigest) async -> String? {
        guard let first = digest.blocks.first(where: { !$0.isEmpty }) else { return nil }

        let line = first
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? first

        let sentence = Self.firstSentence(of: line)
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return Self.truncate(trimmed, toWords: 8)
    }

    // MARK: - Tags

    /// Matches existing tags that actually appear in the note.
    ///
    /// It cannot invent one, which is the constraint section 7 asks for — and
    /// it is why this fallback is not obviously worse than the model.
    func suggestTags(for digest: NoteDigest, existing: [String]) async -> [String] {
        let haystack = Self.fold(digest.text)
        guard !haystack.isEmpty else { return [] }

        return existing
            .filter { tag in
                let needle = Self.fold(tag)
                return needle.count > 2 && haystack.contains(needle)
            }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Summary

    /// Extractive: the three sentences that carry the most of the note's own
    /// distinctive words.
    ///
    /// It cannot paraphrase, so it never invents a claim the note did not make
    /// — which for a summary is the failure that matters.
    func summarise(_ digest: NoteDigest) async -> [String] {
        let sentences = Self.sentences(in: digest.text)
        guard sentences.count > 3 else {
            return sentences.map { Self.truncate($0, toWords: 24) }
        }

        var frequencies: [String: Int] = [:]
        for sentence in sentences {
            for word in Self.significantWords(in: sentence) {
                frequencies[word, default: 0] += 1
            }
        }

        let scored = sentences.enumerated().map { index, sentence -> (index: Int, sentence: String, score: Double) in
            let words = Self.significantWords(in: sentence)
            guard !words.isEmpty else { return (index, sentence, 0) }
            let total = words.reduce(0) { $0 + (frequencies[$1] ?? 0) }
            // Divided by length so a rambling sentence does not win on volume.
            return (index, sentence, Double(total) / Double(words.count))
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(3)
            // Back into reading order: three sentences out of sequence read as
            // three fragments.
            .sorted { $0.index < $1.index }
            .map { Self.truncate($0.sentence, toWords: 24) }
    }

    // MARK: - Actions

    private static let actionMarkers = ["todo", "action:", "action item", "follow up", "follow-up", "next step"]
    private static let actionVerbs = [
        "send", "email", "call", "ask", "check", "confirm", "write", "draft", "review",
        "book", "schedule", "update", "fix", "share", "chase", "prepare", "arrange",
    ]

    func extractActions(from digest: NoteDigest) async -> [String] {
        let lines = digest.text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return lines.compactMap { line -> String? in
            let cleaned = Self.stripListMarker(line)
            guard cleaned.count > 3 else { return nil }

            let folded = Self.fold(cleaned)
            let marked = Self.actionMarkers.contains { folded.contains($0) }
            // "Send the deck" — imperative openings are what an action reads
            // like; "I sent the deck" is a note about the past.
            let imperative = Self.actionVerbs.contains { folded.hasPrefix($0 + " ") }

            guard marked || imperative else { return nil }
            return Self.truncate(cleaned, toWords: 18)
        }
        .reduce(into: [String]()) { result, action in
            if !result.contains(action) { result.append(action) }
        }
    }

    // MARK: - Structuring

    private static let bulletPrefixes: Set<Character> = ["-", "*", "•", "–", "—", "‣", "·"]

    /// Parses pasted or spoken text into sections and lists.
    ///
    /// Handles Markdown headings, bullets, numbered lines, and the
    /// "2 lemons" / "lemons x2" / "300g flour" shapes that recipes and shopping
    /// lists are actually written in. No inference — just reading the shape
    /// somebody already put there.
    func structure(_ text: String) async -> CapturedNote {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var title = ""
        var sections: [CapturedNote.Section] = []
        var current = CapturedNote.Section(heading: "")
        var prose: [String] = []

        func flush() {
            current.prose = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.items.isEmpty || !current.prose.isEmpty || !current.heading.isEmpty {
                sections.append(current)
            }
            current = CapturedNote.Section(heading: "")
            prose = []
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let heading = Self.markdownHeading(line) {
                if title.isEmpty && sections.isEmpty && current.items.isEmpty && prose.isEmpty {
                    title = heading
                    continue
                }
                flush()
                current.heading = heading
                continue
            }

            if Self.looksLikeItem(line) {
                current.items.append(Self.parseItem(Self.stripListMarker(line)))
                continue
            }

            // A colon-terminated short line is a heading in everything but
            // syntax: "Sauce:" in a recipe, "Bathroom:" in a packing list.
            if line.hasSuffix(":"), line.count < 40, !current.items.isEmpty || prose.isEmpty {
                flush()
                current.heading = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }

            if title.isEmpty && sections.isEmpty && current.items.isEmpty && prose.isEmpty && line.count < 60 {
                title = line
                continue
            }

            prose.append(line)
        }
        flush()

        return CapturedNote(title: title, sections: sections)
    }

    // MARK: - Text helpers

    static func markdownHeading(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let text = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    static func looksLikeItem(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        if bulletPrefixes.contains(first) { return true }
        if line.hasPrefix("[ ]") || line.hasPrefix("[x]") || line.hasPrefix("[X]") { return true }

        // "1. " or "1) "
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(".") || rest.hasPrefix(")") { return true }
            // A bare "2 lemons" is an item too, but "2024 was a good year" is
            // not — a quantity is small and followed by a word.
            if rest.hasPrefix(" "), let value = Int(digits), value <= 999, line.split(separator: " ").count <= 6 {
                return true
            }
        }
        return false
    }

    static func stripListMarker(_ line: String) -> String {
        var result = line

        if let first = result.first, bulletPrefixes.contains(first) {
            result = String(result.dropFirst())
        }
        for marker in ["[ ]", "[x]", "[X]"] where result.trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
            result = String(result.trimmingCharacters(in: .whitespaces).dropFirst(marker.count))
        }

        let trimmed = result.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            let rest = trimmed.dropFirst(digits.count)
            if rest.hasPrefix(".") || rest.hasPrefix(")") {
                return String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        return trimmed
    }

    private static let knownUnits: Set<String> = [
        "g", "kg", "mg", "ml", "l", "cl", "oz", "lb", "lbs",
        "tsp", "tbsp", "cup", "cups", "pack", "packs", "tin", "tins",
        "bunch", "clove", "cloves", "slice", "slices", "ea", "x",
    ]

    /// Pulls a quantity and unit out of the front or back of an item.
    static func parseItem(_ text: String) -> CapturedNote.Item {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return CapturedNote.Item(label: "") }

        // Trailing form: "Lemons x2", "Milk 2".
        let parts = cleaned.split(separator: " ").map(String.init)
        if parts.count >= 2, let last = parts.last {
            let candidate = last.hasPrefix("x") || last.hasPrefix("×") ? String(last.dropFirst()) : last
            if let quantity = Double(candidate), quantity > 0, parts.count > 1 {
                return CapturedNote.Item(
                    label: parts.dropLast().joined(separator: " "),
                    quantity: quantity
                )
            }
        }

        // Leading form: "2 lemons", "300g flour", "2 tbsp olive oil".
        let leadingDigits = cleaned.prefix { $0.isNumber || $0 == "." }
        guard !leadingDigits.isEmpty, let quantity = Double(leadingDigits) else {
            return CapturedNote.Item(label: cleaned)
        }

        var rest = String(cleaned.dropFirst(leadingDigits.count))
        var unit: String?

        // "300g" — the unit is glued to the number.
        let glued = rest.prefix { $0.isLetter }
        if !glued.isEmpty, knownUnits.contains(glued.lowercased()) {
            unit = String(glued)
            rest = String(rest.dropFirst(glued.count))
        } else {
            let words = rest.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
            if let first = words.first, knownUnits.contains(first.lowercased()), words.count > 1 {
                unit = first
                rest = words.dropFirst().joined(separator: " ")
            }
        }

        let label = rest.trimmingCharacters(in: .whitespaces)
        return label.isEmpty
            ? CapturedNote.Item(label: cleaned)
            : CapturedNote.Item(label: label, quantity: quantity, unit: unit)
    }

    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count > 2 { result.append(sentence) }
            return true
        }
        return result
    }

    static func firstSentence(of text: String) -> String {
        sentences(in: text).first ?? text
    }

    /// Words worth scoring: not the fifty that appear in every sentence.
    static func significantWords(in text: String) -> [String] {
        var result: [String] = []
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace, .omitOther]
        ) { tag, range in
            guard let tag, [.noun, .verb, .adjective, .otherWord].contains(tag) else { return true }
            let word = fold(String(text[range]))
            if word.count > 2 { result.append(word) }
            return true
        }
        return result
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    static func truncate(_ text: String, toWords limit: Int) -> String {
        let words = text.split(separator: " ")
        guard words.count > limit else { return text }
        return words.prefix(limit).joined(separator: " ") + "…"
    }
}
