import Foundation
import SwiftData

/// A free-form label. CloudKit forbids `@Attribute(.unique)`, so uniqueness by
/// name is enforced at the point of creation instead — see `Tag.findOrCreate`.
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var notes: [Note]? = []

    init(id: UUID = UUID(), name: String = "") {
        self.id = id
        self.name = name
    }
}

extension Tag {
    /// Case-insensitive dedupe. Two devices can still race and both create the
    /// same tag before sync converges; `mergeDuplicates` cleans that up.
    static func findOrCreate(named name: String, in context: ModelContext) throws -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.lowercased()
        let existing = try context.fetch(FetchDescriptor<Tag>())
        if let match = existing.first(where: { $0.name.lowercased() == folded }) {
            return match
        }
        let tag = Tag(name: trimmed)
        context.insert(tag)
        return tag
    }

    /// Collapses tags that ended up sharing a name across devices, keeping the
    /// oldest by UUID ordering so every device picks the same survivor.
    static func mergeDuplicates(in context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<Tag>())
        let groups = Dictionary(grouping: all) { $0.name.lowercased() }
        for (_, duplicates) in groups where duplicates.count > 1 {
            let sorted = duplicates.sorted { $0.id.uuidString < $1.id.uuidString }
            guard let survivor = sorted.first else { continue }
            for loser in sorted.dropFirst() {
                for note in loser.notes ?? [] {
                    var tags = note.tags ?? []
                    if !tags.contains(where: { $0.id == survivor.id }) {
                        tags.append(survivor)
                    }
                    note.tags = tags.filter { $0.id != loser.id }
                }
                context.delete(loser)
            }
        }
    }
}
