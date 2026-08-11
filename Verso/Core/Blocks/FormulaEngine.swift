import Foundation

/// The values a formula can hold while it is being evaluated.
enum FormulaValue: Equatable, Sendable {
    case number(Double)
    case list([Double])
    /// Only ever a function argument — `series("bench-press")`. Arithmetic on a
    /// string is an error, not a coercion.
    case text(String)
}

/// What a formula can see.
///
/// The note fills this in; the engine has no idea where any of it came from.
/// That separation is the whole reason `sum(subtotal)` can mean a grocery total
/// in one note and something else entirely in another without this file
/// changing.
struct FormulaContext {
    var numbers: [String: Double] = [:]
    var lists: [String: [Double]] = [:]

    /// Resolves `series("id")` against the `MetricEntry` store. A closure
    /// rather than a prefetched dictionary because a note should not have to
    /// load every series in the app to evaluate one formula.
    var series: (String) -> [Double] = { _ in [] }

    /// Resolves `metric("series-id")` — readings in *this* note only.
    var metrics: (String) -> [Double] = { _ in [] }

    /// Resolves `column("Title")` against table blocks in this note.
    var columns: (String) -> [Double] = { _ in [] }

    init() {}
}

enum FormulaError: LocalizedError, Equatable {
    case empty
    case unexpectedCharacter(String, at: Int)
    case unexpectedEnd
    case expected(String, at: Int)
    case unknownName(String)
    case unknownFunction(String)
    case badArgumentCount(function: String, expected: String, got: Int)
    case expectedNumber(String)
    case expectedList(String)
    case expectedText(String)
    case divisionByZero
    case tooComplex

    var errorDescription: String? {
        switch self {
        case .empty: "No expression."
        case .unexpectedCharacter(let character, let index): "Unexpected “\(character)” at \(index)."
        case .unexpectedEnd: "The expression ends too early."
        case .expected(let what, let index): "Expected \(what) at \(index)."
        case .unknownName(let name): "“\(name)” isn't something this note has."
        case .unknownFunction(let name): "There's no function called “\(name)”."
        case .badArgumentCount(let function, let expected, let got):
            "\(function) takes \(expected), not \(got)."
        case .expectedNumber(let context): "\(context) needs a number."
        case .expectedList(let context): "\(context) needs a list of numbers."
        case .expectedText(let context): "\(context) needs a name in quotes."
        case .divisionByZero: "Division by zero."
        case .tooComplex: "This expression nests too deeply."
        }
    }
}

// MARK: - Tokens

private enum FormulaToken: Equatable {
    case number(Double)
    case name(String)
    case text(String)
    case symbol(Character)
}

private struct FormulaLexer {
    let characters: [Character]
    var index = 0

    init(_ source: String) {
        characters = Array(source)
    }

    mutating func tokenize() throws -> [(token: FormulaToken, offset: Int)] {
        var result: [(token: FormulaToken, offset: Int)] = []

        while index < characters.count {
            let character = characters[index]
            let start = index

            if character.isWhitespace {
                index += 1
            } else if character.isNumber || (character == "." && peekIsNumber(at: index + 1)) {
                result.append((.number(try readNumber()), start))
            } else if character.isLetter || character == "_" {
                result.append((.name(readName()), start))
            } else if character == "\"" || character == "'" {
                result.append((.text(try readText(delimiter: character)), start))
            } else if "+-*/%(),".contains(character) {
                index += 1
                result.append((.symbol(character), start))
            } else {
                throw FormulaError.unexpectedCharacter(String(character), at: start)
            }
        }
        return result
    }

    private func peekIsNumber(at position: Int) -> Bool {
        position < characters.count && characters[position].isNumber
    }

    private mutating func readNumber() throws -> Double {
        let start = index
        var sawSeparator = false
        while index < characters.count {
            let character = characters[index]
            if character.isNumber {
                index += 1
            } else if character == "." && !sawSeparator {
                sawSeparator = true
                index += 1
            } else {
                break
            }
        }
        let literal = String(characters[start..<index])
        guard let value = Double(literal) else {
            throw FormulaError.unexpectedCharacter(literal, at: start)
        }
        return value
    }

    private mutating func readName() -> String {
        let start = index
        while index < characters.count, characters[index].isLetter || characters[index].isNumber
            || characters[index] == "_" || characters[index] == "." {
            index += 1
        }
        return String(characters[start..<index])
    }

    /// Quoted so that a series id may contain hyphens — `bench-press` would
    /// otherwise lex as a subtraction.
    private mutating func readText(delimiter: Character) throws -> String {
        let opening = index
        index += 1
        let start = index
        while index < characters.count, characters[index] != delimiter {
            index += 1
        }
        guard index < characters.count else {
            throw FormulaError.expected("a closing \(delimiter)", at: opening)
        }
        let literal = String(characters[start..<index])
        index += 1
        return literal
    }
}

// MARK: - Evaluation

/// A small recursive-descent evaluator.
///
/// Deliberately not a general-purpose language: there is no assignment, no
/// control flow, and no way to reach outside the context the note handed it.
/// A formula is a read-only question about a note.
struct FormulaEvaluator {

    private let tokens: [(token: FormulaToken, offset: Int)]
    private let context: FormulaContext
    private var position = 0
    private var depth = 0

    private static let maximumDepth = 32

    private init(tokens: [(token: FormulaToken, offset: Int)], context: FormulaContext) {
        self.tokens = tokens
        self.context = context
    }

    static func evaluate(_ expression: String, context: FormulaContext) throws -> Double {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FormulaError.empty }

        var lexer = FormulaLexer(trimmed)
        var evaluator = FormulaEvaluator(tokens: try lexer.tokenize(), context: context)
        let value = try evaluator.parseExpression()

        guard evaluator.position == evaluator.tokens.count else {
            throw FormulaError.expected("the end of the expression", at: evaluator.currentOffset)
        }
        return try evaluator.number(value, "The result")
    }

    // MARK: Grammar

    private mutating func parseExpression() throws -> FormulaValue {
        var left = try parseTerm()
        while case .symbol(let symbol)? = peek(), symbol == "+" || symbol == "-" {
            advance()
            let right = try parseTerm()
            let a = try number(left, "The left side of \(symbol)")
            let b = try number(right, "The right side of \(symbol)")
            left = .number(symbol == "+" ? a + b : a - b)
        }
        return left
    }

    private mutating func parseTerm() throws -> FormulaValue {
        var left = try parseUnary()
        while case .symbol(let symbol)? = peek(), symbol == "*" || symbol == "/" || symbol == "%" {
            advance()
            let right = try parseUnary()
            let a = try number(left, "The left side of \(symbol)")
            let b = try number(right, "The right side of \(symbol)")

            switch symbol {
            case "*":
                left = .number(a * b)
            case "/":
                guard b != 0 else { throw FormulaError.divisionByZero }
                left = .number(a / b)
            default:
                guard b != 0 else { throw FormulaError.divisionByZero }
                left = .number(a.truncatingRemainder(dividingBy: b))
            }
        }
        return left
    }

    private mutating func parseUnary() throws -> FormulaValue {
        if case .symbol(let symbol)? = peek(), symbol == "-" || symbol == "+" {
            advance()
            let value = try parseUnary()
            let scalar = try number(value, "A negated value")
            return .number(symbol == "-" ? -scalar : scalar)
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> FormulaValue {
        guard let entry = peek() else { throw FormulaError.unexpectedEnd }

        switch entry {
        case .number(let value):
            advance()
            return .number(value)

        case .text(let value):
            advance()
            return .text(value)

        case .symbol("("):
            advance()
            depth += 1
            defer { depth -= 1 }
            guard depth < Self.maximumDepth else { throw FormulaError.tooComplex }

            let value = try parseExpression()
            try expectClosingBracket()
            return value

        case .symbol(let symbol):
            throw FormulaError.unexpectedCharacter(String(symbol), at: currentOffset)

        case .name(let name):
            advance()
            if case .symbol("(")? = peek() {
                advance()
                depth += 1
                defer { depth -= 1 }
                guard depth < Self.maximumDepth else { throw FormulaError.tooComplex }

                let arguments = try parseArguments()
                return try apply(function: name, arguments: arguments)
            }
            return try resolve(name: name)
        }
    }

    private mutating func parseArguments() throws -> [FormulaValue] {
        var arguments: [FormulaValue] = []
        if case .symbol(")")? = peek() {
            advance()
            return arguments
        }
        while true {
            arguments.append(try parseExpression())
            guard case .symbol(let symbol)? = peek() else { throw FormulaError.unexpectedEnd }
            advance()
            if symbol == ")" { return arguments }
            guard symbol == "," else {
                throw FormulaError.expected("a comma or a closing bracket", at: currentOffset)
            }
        }
    }

    private mutating func expectClosingBracket() throws {
        guard case .symbol(")")? = peek() else {
            throw FormulaError.expected("a closing bracket", at: currentOffset)
        }
        advance()
    }

    // MARK: Names and functions

    private func resolve(name: String) throws -> FormulaValue {
        if let value = context.numbers[name] { return .number(value) }
        if let list = context.lists[name] { return .list(list) }
        throw FormulaError.unknownName(name)
    }

    private func apply(function rawName: String, arguments: [FormulaValue]) throws -> FormulaValue {
        let name = rawName.lowercased()

        switch name {
        // Lookups. Each takes one quoted name and produces a list.
        case "series", "metric", "column":
            guard arguments.count == 1 else {
                throw FormulaError.badArgumentCount(function: name, expected: "one name", got: arguments.count)
            }
            let key = try text(arguments[0], name)
            return switch name {
            case "series": .list(context.series(key))
            case "metric": .list(context.metrics(key))
            default: .list(context.columns(key))
            }

        // Aggregations over a list.
        case "sum", "avg", "mean", "count", "first", "last":
            guard arguments.count == 1 else {
                throw FormulaError.badArgumentCount(function: name, expected: "one list", got: arguments.count)
            }
            let values = try list(arguments[0], name)
            return switch name {
            case "sum": .number(values.reduce(0, +))
            case "avg", "mean": .number(values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count))
            case "count": .number(Double(values.count))
            case "first": .number(values.first ?? 0)
            default: .number(values.last ?? 0)
            }

        // min and max read a list, or several numbers.
        case "min", "max":
            guard !arguments.isEmpty else {
                throw FormulaError.badArgumentCount(function: name, expected: "at least one value", got: 0)
            }
            let values: [Double]
            if arguments.count == 1 {
                values = try list(arguments[0], name)
            } else {
                values = try arguments.map { try number($0, name) }
            }
            guard let result = name == "min" ? values.min() : values.max() else { return .number(0) }
            return .number(result)

        /// Pairs two lists by position and sums the products. This is what
        /// turns weight and reps into volume load without the engine knowing
        /// either word.
        case "sumproduct":
            guard arguments.count == 2 else {
                throw FormulaError.badArgumentCount(function: name, expected: "two lists", got: arguments.count)
            }
            let a = try list(arguments[0], name)
            let b = try list(arguments[1], name)
            return .number(zip(a, b).reduce(0) { $0 + $1.0 * $1.1 })

        case "abs", "round", "floor", "ceil", "sqrt":
            guard arguments.count == 1 else {
                throw FormulaError.badArgumentCount(function: name, expected: "one number", got: arguments.count)
            }
            let value = try number(arguments[0], name)
            return switch name {
            case "abs": .number(Swift.abs(value))
            case "round": .number(value.rounded())
            case "floor": .number(value.rounded(.down))
            case "ceil": .number(value.rounded(.up))
            default: .number(value < 0 ? 0 : value.squareRoot())
            }

        case "clamp":
            guard arguments.count == 3 else {
                throw FormulaError.badArgumentCount(function: name, expected: "three numbers", got: arguments.count)
            }
            let value = try number(arguments[0], name)
            let lower = try number(arguments[1], name)
            let upper = try number(arguments[2], name)
            return .number(Swift.min(Swift.max(value, lower), upper))

        default:
            throw FormulaError.unknownFunction(rawName)
        }
    }

    // MARK: Coercion

    /// A single number is a one-element list, so `sum(3)` works and a series
    /// with one reading behaves like one with ten.
    private func list(_ value: FormulaValue, _ context: String) throws -> [Double] {
        switch value {
        case .list(let values): values
        case .number(let value): [value]
        case .text: throw FormulaError.expectedList(context)
        }
    }

    /// A list is *not* silently a number. `sum(prices) + 1` is meaningful;
    /// `prices + 1` is a mistake, and saying so beats guessing.
    private func number(_ value: FormulaValue, _ context: String) throws -> Double {
        switch value {
        case .number(let value): value
        case .list: throw FormulaError.expectedNumber(context)
        case .text: throw FormulaError.expectedNumber(context)
        }
    }

    private func text(_ value: FormulaValue, _ context: String) throws -> String {
        guard case .text(let string) = value else { throw FormulaError.expectedText(context) }
        return string
    }

    // MARK: Cursor

    private func peek() -> FormulaToken? {
        position < tokens.count ? tokens[position].token : nil
    }

    private mutating func advance() {
        position += 1
    }

    private var currentOffset: Int {
        position < tokens.count ? tokens[position].offset : (tokens.last?.offset ?? 0)
    }
}
