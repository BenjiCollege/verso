import Foundation

/// Each block type's Markdown, written where the payload is.
///
/// The exporter walks blocks and asks; it never learns what a checklist is.
/// A block type added later exports the moment it says how, and exports as
/// plain text until then.

extension HeadingPayload {
    var markdownRepresentation: String {
        String(repeating: "#", count: level.rawValue) + " " + text
    }
}

extension ListPayload {
    var markdownRepresentation: String {
        items.enumerated().map { index, item in
            switch style {
            case .bullet: "- \(item.text)"
            case .numbered: "\(index + 1). \(item.text)"
            }
        }.joined(separator: "\n")
    }
}

extension ChecklistPayload {
    var markdownRepresentation: String {
        sections().map { section in
            var lines: [String] = []
            if let title = section.title, !title.isEmpty {
                lines.append("**\(title)**\n")
            }
            lines.append(contentsOf: section.items.map { item in
                var line = "- [\(item.checked ? "x" : " ")] \(item.label)"

                var details: [String] = []
                if shows(.quantity), let quantity = item.quantity {
                    let formatted = quantity.formatted(.number.precision(.fractionLength(0...2)))
                    details.append(shows(.unit) ? "\(formatted) \(item.unit ?? "")".trimmingCharacters(in: .whitespaces) : formatted)
                }
                if shows(.price), let price = item.price {
                    details.append(price.formatted(.number.precision(.fractionLength(0...2))))
                }
                if !details.isEmpty { line += " — \(details.joined(separator: " · "))" }
                if shows(.note), let note = item.note, !note.isEmpty { line += "\n  \(note)" }
                return line
            })
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

extension DividerPayload {
    var markdownRepresentation: String {
        style == .space ? "" : "---"
    }
}

extension MetricPayload {
    var markdownRepresentation: String {
        guard let value else { return "**\(label)** — _not recorded_" }
        let formatted = value.formatted(.number.precision(.fractionLength(0...2)))
        let reading = unit.isEmpty ? formatted : "\(formatted) \(unit)"
        guard let target else { return "**\(label)** — \(reading)" }
        return "**\(label)** — \(reading) of \(target.formatted(.number.precision(.fractionLength(0...2))))"
    }
}

extension TimerPayload {
    var markdownRepresentation: String {
        let name = label.isEmpty ? String(localized: "Timer") : label
        return "**\(name)** — \(duration.timerClockText)"
    }
}

extension FormulaPayload {
    var markdownRepresentation: String {
        // The expression, not the result: a Markdown file is not recomputed,
        // and a stale number would be worse than an honest formula.
        "**\(label)** — `\(expression)`"
    }
}

extension ProgressPayload {
    var markdownRepresentation: String {
        let current = current.formatted(.number.precision(.fractionLength(0...2)))
        let target = target.formatted(.number.precision(.fractionLength(0...2)))
        return "**\(label)** — \(current) / \(target)"
    }
}

extension RatingPayload {
    var markdownRepresentation: String {
        guard let value else { return "**\(label)** — _not rated_" }
        return "**\(label)** — \(value)/\(scale)"
    }
}

extension TablePayload {
    /// A GitHub-flavoured pipe table, which is the only table syntax with any
    /// real reach.
    var markdownRepresentation: String {
        guard !columns.isEmpty else { return caption }

        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: " ")
        }

        var lines: [String] = []
        if !caption.isEmpty { lines.append("**\(caption)**\n") }

        lines.append("| " + columns.map { escape($0.title) }.joined(separator: " | ") + " |")
        lines.append("| " + columns.map { _ in "---" }.joined(separator: " | ") + " |")

        for row in normalized().rows {
            let cells = zip(columns, row.cells).map { escape($1.display(for: $0.kind)) }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }
}

extension SchedulePayload {
    var markdownRepresentation: String {
        let name = label.isEmpty ? String(localized: "Reminder") : label
        guard let dueAt else { return "**\(name)**" }

        var line = "**\(name)** — \(dueAt.formatted(date: .abbreviated, time: .shortened))"
        if let recurrence { line += " · \(recurrence.displayDescription)" }
        return line
    }
}

extension PlacePayload {
    var markdownRepresentation: String {
        let name = self.name.isEmpty ? String(localized: "Place") : self.name
        guard let coordinate else { return "📍 \(name)" }
        // A geo: link opens in Maps and degrades to plain text everywhere else.
        return "📍 [\(name)](geo:\(coordinate.latitude),\(coordinate.longitude))"
    }
}

extension TextPayload {
    var markdownRepresentation: String { plain }
}
