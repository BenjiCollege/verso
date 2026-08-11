import Foundation

/// The most capable block in the engine, and the one most at risk of growing
/// use-case knowledge. It has none: it knows how to group items by a key, which
/// per-item fields to expose, and nothing else. "Aisle" is a `Group.label` in a
/// JSON template, not a concept in this file.
struct ChecklistPayload: BlockPayload {
    static let blockType = BlockType.checklist

    /// Which item property drives sectioning.
    enum GroupBy: String, Codable, CaseIterable, Sendable {
        case none
        case group
        case checked
        case tag

        var displayName: LocalizedStringResource {
            switch self {
            case .none: "No grouping"
            case .group: "Group"
            case .checked: "Completion"
            case .tag: "Tag"
            }
        }
    }

    /// The optional per-item fields this checklist puts in front of the user.
    /// A packing list turns them all off; a grocery list turns on quantity,
    /// unit and price. Both are the same code path.
    enum ItemField: String, Codable, CaseIterable, Sendable {
        case quantity
        case unit
        case price
        case note
        case tags
        case schedule
        case place
        case image
        case link

        var displayName: LocalizedStringResource {
            switch self {
            case .quantity: "Quantity"
            case .unit: "Unit"
            case .price: "Price"
            case .note: "Note"
            case .tags: "Tags"
            case .schedule: "Schedule"
            case .place: "Place"
            case .image: "Image"
            case .link: "Link"
            }
        }
    }

    struct Group: Codable, Hashable, Identifiable, Sendable {
        /// A stable key, not a display string. `Item.group` matches on this.
        var id: String
        var label: String
        var position: Int

        init(id: String, label: String, position: Int = 0) {
            self.id = id
            self.label = label
            self.position = position
        }
    }

    // MARK: - Per-item references
    //
    // These are the attachment points listed in section 5. Phases 3, 4 and 10
    // fill them in; they are declared now so the payload shape is stable and
    // a template written today can round-trip through a later build unchanged.

    struct ItemSchedule: Codable, Hashable, Sendable {
        var dueAt: Date?
        var recurrence: String?

        init(dueAt: Date? = nil, recurrence: String? = nil) {
            self.dueAt = dueAt
            self.recurrence = recurrence
        }
    }

    struct ItemPlace: Codable, Hashable, Sendable {
        var latitude: Double?
        var longitude: Double?
        /// A MapKit POI category identifier, for "any grocery store".
        var poiCategory: String?
        var radius: Double

        init(latitude: Double? = nil, longitude: Double? = nil, poiCategory: String? = nil, radius: Double = 150) {
            self.latitude = latitude
            self.longitude = longitude
            self.poiCategory = poiCategory
            self.radius = radius
        }
    }

    struct ItemImage: Codable, Hashable, Sendable {
        var assetID: UUID
        var caption: String?

        init(assetID: UUID, caption: String? = nil) {
            self.assetID = assetID
            self.caption = caption
        }
    }

    struct ItemLink: Codable, Hashable, Sendable {
        var url: URL?
        /// A `[[wiki-link]]` target within the app.
        var noteID: UUID?

        init(url: URL? = nil, noteID: UUID? = nil) {
            self.url = url
            self.noteID = noteID
        }
    }

    struct Item: Codable, Hashable, Identifiable, Sendable {
        var id: UUID
        var label: String
        var checked: Bool
        var checkedAt: Date?

        var quantity: Double?
        var unit: String?
        var price: Decimal?
        var currency: String?

        /// Matches `Group.id`. `nil` means ungrouped.
        var group: String?
        var note: String?
        var tags: [String]

        var schedule: ItemSchedule?
        var place: ItemPlace?
        var image: ItemImage?
        var link: ItemLink?

        init(
            id: UUID = UUID(),
            label: String = "",
            checked: Bool = false,
            checkedAt: Date? = nil,
            quantity: Double? = nil,
            unit: String? = nil,
            price: Decimal? = nil,
            currency: String? = nil,
            group: String? = nil,
            note: String? = nil,
            tags: [String] = [],
            schedule: ItemSchedule? = nil,
            place: ItemPlace? = nil,
            image: ItemImage? = nil,
            link: ItemLink? = nil
        ) {
            self.id = id
            self.label = label
            self.checked = checked
            self.checkedAt = checkedAt
            self.quantity = quantity
            self.unit = unit
            self.price = price
            self.currency = currency
            self.group = group
            self.note = note
            self.tags = tags
            self.schedule = schedule
            self.place = place
            self.image = image
            self.link = link
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Templates ship items without ids; minting one here is what lets a
            // template author write plain JSON.
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
            self.checked = try container.decodeIfPresent(Bool.self, forKey: .checked) ?? false
            self.checkedAt = try container.decodeIfPresent(Date.self, forKey: .checkedAt)
            self.quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
            self.unit = try container.decodeIfPresent(String.self, forKey: .unit)
            self.price = try container.decodeIfPresent(Decimal.self, forKey: .price)
            self.currency = try container.decodeIfPresent(String.self, forKey: .currency)
            self.group = try container.decodeIfPresent(String.self, forKey: .group)
            self.note = try container.decodeIfPresent(String.self, forKey: .note)
            self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
            self.schedule = try container.decodeIfPresent(ItemSchedule.self, forKey: .schedule)
            self.place = try container.decodeIfPresent(ItemPlace.self, forKey: .place)
            self.image = try container.decodeIfPresent(ItemImage.self, forKey: .image)
            self.link = try container.decodeIfPresent(ItemLink.self, forKey: .link)
        }
    }

    var groupBy: GroupBy
    var groups: [Group]
    var itemFields: [ItemField]
    var items: [Item]

    init(
        groupBy: GroupBy = .none,
        groups: [Group] = [],
        itemFields: [ItemField] = [],
        items: [Item] = []
    ) {
        self.groupBy = groupBy
        self.groups = groups
        self.itemFields = itemFields
        self.items = items
    }

    /// Unknown `groupBy` values and unknown `itemFields` are dropped rather than
    /// thrown on, so a note authored on a newer build still opens here.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawGroupBy = try container.decodeIfPresent(String.self, forKey: .groupBy) ?? GroupBy.none.rawValue
        self.groupBy = GroupBy(rawValue: rawGroupBy) ?? .none
        self.groups = try container.decodeIfPresent([Group].self, forKey: .groups) ?? []
        let rawFields = try container.decodeIfPresent([String].self, forKey: .itemFields) ?? []
        self.itemFields = rawFields.compactMap(ItemField.init(rawValue:))
        self.items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
    }

    static func makeDefault() -> ChecklistPayload {
        ChecklistPayload(groupBy: .none, groups: [], itemFields: [], items: [Item()])
    }

    var plainTextRepresentation: String {
        items.map(\.label).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

// MARK: - Sectioning

extension ChecklistPayload {
    /// One rendered section of the checklist.
    struct Section: Identifiable, Sendable {
        var id: String
        var title: String?
        var items: [Item]
    }

    func shows(_ field: ItemField) -> Bool {
        itemFields.contains(field)
    }

    /// Splits `items` according to `groupBy`, preserving item order within a
    /// section. Items whose `group` key has no matching `Group` fall into a
    /// trailing untitled section rather than disappearing.
    func sections() -> [Section] {
        switch groupBy {
        case .none:
            return [Section(id: "all", title: nil, items: items)]

        case .group:
            let ordered = groups.sorted { $0.position < $1.position }
            var sections = ordered.map { group in
                Section(id: group.id, title: group.label, items: items.filter { $0.group == group.id })
            }
            let known = Set(ordered.map(\.id))
            let ungrouped = items.filter { $0.group.map { !known.contains($0) } ?? true }
            if !ungrouped.isEmpty {
                sections.append(Section(id: "__ungrouped", title: nil, items: ungrouped))
            }
            return sections.filter { !$0.items.isEmpty }

        case .checked:
            let open = items.filter { !$0.checked }
            let done = items.filter(\.checked)
            return [
                Section(id: "open", title: String(localized: "To do"), items: open),
                Section(id: "done", title: String(localized: "Done"), items: done),
            ].filter { !$0.items.isEmpty }

        case .tag:
            var seen = Set<String>()
            let uniqueTags = items.flatMap(\.tags).filter { seen.insert($0).inserted }
            var sections = uniqueTags.map { tag in
                Section(id: tag, title: tag, items: items.filter { $0.tags.contains(tag) })
            }
            let untagged = items.filter { $0.tags.isEmpty }
            if !untagged.isEmpty {
                sections.append(Section(id: "__untagged", title: nil, items: untagged))
            }
            return sections.filter { !$0.items.isEmpty }
        }
    }

    var completedCount: Int { items.count(where: \.checked) }

    var completionFraction: Double {
        guard !items.isEmpty else { return 0 }
        return Double(completedCount) / Double(items.count)
    }

    mutating func setChecked(_ checked: Bool, itemID: UUID, at date: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].checked = checked
        items[index].checkedAt = checked ? date : nil
    }
}
