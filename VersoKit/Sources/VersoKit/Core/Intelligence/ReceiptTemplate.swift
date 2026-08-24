import Foundation

extension Receipt {

    /// The metric series every receipt total is recorded against.
    ///
    /// One shared series is what makes a trip's total possible without anything
    /// knowing what a trip is: `MetricSeries` can already sum a series over a
    /// date range or a scope, so twelve receipts filed in a folder add
    /// themselves up through machinery that predates receipts entirely.
    static let expenseSeriesID = "expense"

    /// Builds the note, the way capture does.
    ///
    /// A runtime `Template` with a generated id, instantiated by the same
    /// `TemplateInstantiator` every bundled template goes through. This matters
    /// more than it looks: the alternative — a `receipt.json` in the bundle and
    /// `if templateID == "receipt"` somewhere in Swift — is exactly what the
    /// project's second rule forbids, and it is forbidden because it is how an
    /// engine that knows nothing about use cases starts knowing about one.
    ///
    /// So nothing here is special-cased downstream. What comes out is an
    /// ordinary note of ordinary blocks: a heading, a table, a metric, a place.
    /// Every other screen — search, export, the fore-edge, Read Mode, the vault
    /// — handles it without a line of receipt-specific code.
    func makeTemplate(
        scannedAt: Date,
        place: ResolvedPlace? = nil,
        locale: Locale = .current
    ) -> Template {
        var blocks: [Template.BlockSpec] = []

        // The line items, as a table rather than a checklist. A receipt's rows
        // are read, not ticked, and a table has a numeric column that sums.
        if !items.isEmpty {
            blocks.append(Template.BlockSpec(type: BlockType.table.rawValue, payload: itemsTable))
        }

        // The total as a metric, so it joins the shared expense series.
        if let total {
            blocks.append(
                Template.BlockSpec(
                    type: BlockType.metric.rawValue,
                    payload: .object([
                        "label": .string(String(localized: "Total")),
                        "value": .number(total),
                        "unit": .string(currency),
                        "seriesID": .string(Self.expenseSeriesID),
                    ])
                )
            )
        }

        // Where it happened, if the device could say. A place block, so it is
        // the same object a reminder would use rather than a line of text that
        // happens to contain an address.
        if let place {
            blocks.append(
                Template.BlockSpec(
                    type: BlockType.place.rawValue,
                    payload: .object([
                        "name": .string(place.name),
                        "latitude": .number(place.coordinate.latitude),
                        "longitude": .number(place.coordinate.longitude),
                    ])
                )
            )
        }

        // Somewhere to write why this was bought, which is the thing no scanner
        // can recover and the only reason to keep a receipt for longer than the
        // return window.
        blocks.append(
            Template.BlockSpec(type: BlockType.text.rawValue, payload: .object(["plain": .string("")]))
        )

        return Template(
            id: "receipt." + UUID().uuidString,
            name: title(locale: locale),
            systemImage: "receipt",
            titleFormat: title(locale: locale),
            blocks: blocks
        )
    }

    private var itemsTable: JSONValue {
        let columns: [JSONValue] = [
            .object([
                "id": .string(UUID().uuidString),
                "title": .string(String(localized: "Item")),
                "kind": .string("text"),
            ]),
            .object([
                "id": .string(UUID().uuidString),
                "title": .string(currency.isEmpty ? String(localized: "Amount") : currency),
                "kind": .string("number"),
            ]),
        ]

        let rows: [JSONValue] = items.map { item in
            var amountCell: [String: JSONValue] = [:]
            if let amount = item.amount { amountCell["number"] = .number(amount) }
            return .object([
                "id": .string(UUID().uuidString),
                "cells": .array([
                    .object(["text": .string(item.label)]),
                    .object(amountCell),
                ]),
            ])
        }

        return .object([
            "caption": .string(""),
            "columns": .array(columns),
            "rows": .array(rows),
        ])
    }

    /// "Pret A Manger — 12 Aug, 1:04 PM", falling back through what is known.
    ///
    /// The date printed on the receipt wins over when it was scanned: a receipt
    /// photographed a week later is still Friday's lunch, and filing it under
    /// the day it was photographed is the mistake this whole feature exists to
    /// stop somebody making by hand.
    func title(locale: Locale = .current, scannedAt: Date = Date()) -> String {
        let when = purchasedAt ?? scannedAt
        let stamp = when.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))

        guard !merchant.isEmpty else {
            return String(localized: "Receipt — \(stamp)")
        }
        return "\(merchant) — \(stamp)"
    }
}
