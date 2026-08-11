import Foundation

struct TablePayload: BlockPayload {
    static let blockType = BlockType.table

    enum ColumnKind: String, Codable, CaseIterable, Sendable {
        case text
        case number
        case date
        case checkbox

        var displayName: LocalizedStringResource {
            switch self {
            case .text: "Text"
            case .number: "Number"
            case .date: "Date"
            case .checkbox: "Checkbox"
            }
        }
    }

    struct Column: Codable, Hashable, Identifiable, Sendable {
        var id: UUID
        var title: String
        var kind: ColumnKind

        init(id: UUID = UUID(), title: String = "", kind: ColumnKind = .text) {
            self.id = id
            self.title = title
            self.kind = kind
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            let rawKind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ColumnKind.text.rawValue
            self.kind = ColumnKind(rawValue: rawKind) ?? .text
        }
    }

    /// Every representation a cell might hold, all optional.
    ///
    /// Deliberately not an enum keyed to the column type: changing a column
    /// from text to number would then throw away what was typed. This way the
    /// column decides which field to read and the rest waits, intact, in case
    /// the column changes back.
    struct Cell: Codable, Hashable, Sendable {
        var text: String?
        var number: Double?
        var date: Date?
        var checked: Bool?

        init(text: String? = nil, number: Double? = nil, date: Date? = nil, checked: Bool? = nil) {
            self.text = text
            self.number = number
            self.date = date
            self.checked = checked
        }

        var isEmpty: Bool {
            (text?.isEmpty ?? true) && number == nil && date == nil && !(checked ?? false)
        }

        func display(for kind: ColumnKind) -> String {
            switch kind {
            case .text: text ?? ""
            case .number: number.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? ""
            case .date: date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
            case .checkbox: (checked ?? false) ? "✓" : ""
            }
        }
    }

    struct Row: Codable, Hashable, Identifiable, Sendable {
        var id: UUID
        /// Positional, aligned with `columns`. `normalized()` keeps the counts
        /// in step after a column is added or removed.
        var cells: [Cell]

        init(id: UUID = UUID(), cells: [Cell] = []) {
            self.id = id
            self.cells = cells
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            self.cells = try container.decodeIfPresent([Cell].self, forKey: .cells) ?? []
        }
    }

    var caption: String
    var columns: [Column]
    var rows: [Row]

    init(caption: String = "", columns: [Column] = [], rows: [Row] = []) {
        self.caption = caption
        self.columns = columns
        self.rows = rows
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.caption = try container.decodeIfPresent(String.self, forKey: .caption) ?? ""
        self.columns = try container.decodeIfPresent([Column].self, forKey: .columns) ?? []
        self.rows = try container.decodeIfPresent([Row].self, forKey: .rows) ?? []
        self = self.normalized()
    }

    static func makeDefault() -> TablePayload {
        TablePayload(
            columns: [Column(title: ""), Column(title: "", kind: .number)],
            rows: [Row(), Row()]
        ).normalized()
    }

    var plainTextRepresentation: String {
        let header = columns.map(\.title).filter { !$0.isEmpty }.joined(separator: " · ")
        let body = rows.map { row in
            zip(columns, row.cells).map { $1.display(for: $0.kind) }.joined(separator: " · ")
        }
        return ([caption, header] + body).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The columns are the form; the rows are what somebody filled in. Row
    /// count is kept so the shape of the table survives.
    func resetForTemplate() -> TablePayload {
        var copy = self
        copy.rows = rows.map { TablePayload.Row(cells: Array(repeating: Cell(), count: columns.count)) }
        return copy
    }

    /// Pads or trims every row so its cell count matches the column count.
    /// A template that ships ragged rows, or a column added on another device,
    /// both land here rather than in an index-out-of-range.
    func normalized() -> TablePayload {
        var copy = self
        copy.rows = rows.map { row in
            var row = row
            if row.cells.count < columns.count {
                row.cells.append(contentsOf: Array(repeating: Cell(), count: columns.count - row.cells.count))
            } else if row.cells.count > columns.count {
                row.cells = Array(row.cells.prefix(columns.count))
            }
            return row
        }
        return copy
    }

    /// The numbers in a column, for `column("Weight")` in a formula.
    func numbers(inColumnTitled title: String) -> [Double] {
        let key = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let index = columns.firstIndex(where: {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
        }) else { return [] }

        return rows.compactMap { row in
            guard index < row.cells.count else { return nil }
            let cell = row.cells[index]
            switch columns[index].kind {
            case .number: return cell.number
            case .checkbox: return (cell.checked ?? false) ? 1 : 0
            case .text: return cell.text.flatMap(Double.init)
            case .date: return nil
            }
        }
    }
}
