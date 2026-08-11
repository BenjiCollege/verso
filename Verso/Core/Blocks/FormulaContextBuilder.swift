import Foundation

/// Builds the vocabulary a formula in a given note can see.
///
/// This is the seam where content-agnostic meets useful. The engine knows only
/// numbers and lists; this file names the lists a note happens to contain —
/// `price`, `subtotal`, `checked` — from the blocks that are actually there.
/// It still knows nothing about groceries or workouts: `sum(subtotal)` is the
/// total of whatever was priced, and `sumproduct(metric("weight"), metric("reps"))`
/// is a volume load only because of what the user called their series.
enum FormulaContextBuilder {

    /// The names available in every note. Shown in the formula editor, because
    /// an expression language nobody can discover is a language nobody uses.
    static let vocabulary: [(name: String, summary: LocalizedStringResource)] = [
        ("price", "Every item price in the note"),
        ("quantity", "Every item quantity"),
        ("subtotal", "Price × quantity, per item"),
        ("checkedSubtotal", "Subtotals of checked items only"),
        ("rating", "Every rating value"),
        ("itemCount", "How many checklist items"),
        ("checkedCount", "How many are checked"),
        ("uncheckedCount", "How many are not"),
        ("series(\"id\")", "Every reading ever, across all notes"),
        ("metric(\"id\")", "Readings in this note only"),
        ("column(\"Title\")", "Numbers from a table column"),
    ]

    static let functions = [
        "sum", "avg", "min", "max", "count", "first", "last",
        "sumproduct", "abs", "round", "floor", "ceil", "sqrt", "clamp",
    ]

    static func context(for note: Note, metrics: MetricSeriesStore?) -> FormulaContext {
        var context = FormulaContext()

        var prices: [Double] = []
        var quantities: [Double] = []
        var subtotals: [Double] = []
        var checkedSubtotals: [Double] = []
        var ratings: [Double] = []
        var itemCount = 0
        var checkedCount = 0

        // Metric readings in this note, kept in block order so `sumproduct`
        // pairs the first weight with the first reps.
        var metricsBySeries: [String: [Double]] = [:]
        var tableColumns: [String: [Double]] = [:]

        for block in note.orderedBlocks {
            switch block.type {
            case .checklist:
                guard let payload = try? block.decoded(as: ChecklistPayload.self) else { continue }
                for item in payload.items {
                    itemCount += 1
                    if item.checked { checkedCount += 1 }

                    if let quantity = item.quantity { quantities.append(quantity) }
                    guard let price = item.price else { continue }
                    let priceValue = NSDecimalNumber(decimal: price).doubleValue
                    prices.append(priceValue)

                    let subtotal = priceValue * (item.quantity ?? 1)
                    subtotals.append(subtotal)
                    if item.checked { checkedSubtotals.append(subtotal) }
                }

            case .metric:
                guard let payload = try? block.decoded(as: MetricPayload.self), let value = payload.value else {
                    continue
                }
                metricsBySeries[payload.seriesID, default: []].append(value)

            case .rating:
                guard let payload = try? block.decoded(as: RatingPayload.self), let value = payload.value else {
                    continue
                }
                ratings.append(Double(value))

            case .table:
                guard let payload = try? block.decoded(as: TablePayload.self) else { continue }
                for column in payload.columns where !column.title.isEmpty {
                    let key = column.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    tableColumns[key, default: []].append(contentsOf: payload.numbers(inColumnTitled: column.title))
                }

            default:
                // Formula blocks are deliberately absent: a formula that could
                // read another formula could read itself.
                continue
            }
        }

        context.lists = [
            "price": prices,
            "quantity": quantities,
            "subtotal": subtotals,
            "checkedSubtotal": checkedSubtotals,
            "rating": ratings,
        ]
        context.numbers = [
            "itemCount": Double(itemCount),
            "checkedCount": Double(checkedCount),
            "uncheckedCount": Double(itemCount - checkedCount),
        ]

        context.metrics = { seriesID in metricsBySeries[seriesID] ?? [] }
        context.columns = { title in
            tableColumns[title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? []
        }
        context.series = { seriesID in
            metrics?.values(seriesID: seriesID) ?? []
        }

        return context
    }
}
