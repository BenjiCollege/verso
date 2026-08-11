import Foundation
import Testing
@testable import Verso

@Suite("Formula evaluation")
struct FormulaTests {

    private func context(
        numbers: [String: Double] = [:],
        lists: [String: [Double]] = [:],
        series: [String: [Double]] = [:],
        metrics: [String: [Double]] = [:],
        columns: [String: [Double]] = [:]
    ) -> FormulaContext {
        var context = FormulaContext()
        context.numbers = numbers
        context.lists = lists
        context.series = { series[$0] ?? [] }
        context.metrics = { metrics[$0] ?? [] }
        context.columns = { columns[$0] ?? [] }
        return context
    }

    private func evaluate(_ expression: String, _ context: FormulaContext = FormulaContext()) throws -> Double {
        try FormulaEvaluator.evaluate(expression, context: context)
    }

    // MARK: - Arithmetic

    @Test("Arithmetic and precedence", arguments: [
        ("1 + 2", 3.0),
        ("2 * 3 + 1", 7.0),
        ("1 + 2 * 3", 7.0),
        ("(1 + 2) * 3", 9.0),
        ("10 / 4", 2.5),
        ("10 % 3", 1.0),
        ("-5 + 2", -3.0),
        ("- (2 + 3)", -5.0),
        ("2 * -3", -6.0),
        ("1.5 + .5", 2.0),
        ("100", 100.0),
        ("((((1))))", 1.0),
    ])
    func arithmetic(expression: String, expected: Double) throws {
        #expect(try evaluate(expression) == expected)
    }

    @Test("Whitespace is irrelevant")
    func whitespaceIsIgnored() throws {
        #expect(try evaluate("  1+\t2 * 3  ") == 7)
    }

    @Test("Division by zero is an error, not an infinity")
    func divisionByZero() {
        #expect(throws: FormulaError.divisionByZero) { _ = try evaluate("1 / 0") }
        #expect(throws: FormulaError.divisionByZero) { _ = try evaluate("1 % 0") }
    }

    // MARK: - Names

    @Test("Numbers and lists resolve from the context")
    func namesResolve() throws {
        let context = context(numbers: ["itemCount": 4], lists: ["price": [1, 2, 3]])
        #expect(try evaluate("itemCount", context) == 4)
        #expect(try evaluate("sum(price)", context) == 6)
        #expect(try evaluate("itemCount * 2", context) == 8)
    }

    @Test("An unknown name says so instead of evaluating to zero")
    func unknownNameThrows() {
        #expect(throws: FormulaError.unknownName("nope")) { _ = try evaluate("nope") }
    }

    @Test("An unknown function says so")
    func unknownFunctionThrows() {
        #expect(throws: FormulaError.unknownFunction("frobnicate")) { _ = try evaluate("frobnicate(1)") }
    }

    /// Silently coercing a list to a number is how a wrong total looks right.
    @Test("A list in a number's place is an error")
    func listInScalarPositionThrows() {
        let context = context(lists: ["price": [1, 2]])
        #expect(throws: (any Error).self) { _ = try evaluate("price + 1", context) }
        #expect(throws: (any Error).self) { _ = try evaluate("price", context) }
    }

    // MARK: - Aggregations

    @Test("Aggregations over a list", arguments: [
        ("sum(v)", 10.0),
        ("avg(v)", 2.5),
        ("mean(v)", 2.5),
        ("count(v)", 4.0),
        ("min(v)", 1.0),
        ("max(v)", 4.0),
        ("first(v)", 1.0),
        ("last(v)", 4.0),
    ])
    func aggregations(expression: String, expected: Double) throws {
        #expect(try evaluate(expression, context(lists: ["v": [1, 2, 3, 4]])) == expected)
    }

    @Test("Aggregating an empty list gives zero rather than failing")
    func emptyAggregations() throws {
        let empty = context(lists: ["v": []])
        #expect(try evaluate("sum(v)", empty) == 0)
        #expect(try evaluate("avg(v)", empty) == 0)
        #expect(try evaluate("count(v)", empty) == 0)
        #expect(try evaluate("first(v)", empty) == 0)
    }

    @Test("A single number behaves like a one-element list")
    func scalarIsAList() throws {
        #expect(try evaluate("sum(3)") == 3)
        #expect(try evaluate("count(3)") == 1)
    }

    @Test("min and max also take several numbers")
    func variadicMinMax() throws {
        #expect(try evaluate("min(3, 1, 2)") == 1)
        #expect(try evaluate("max(3, 1, 2)") == 3)
    }

    @Test("Scalar functions", arguments: [
        ("abs(-3)", 3.0),
        ("round(2.6)", 3.0),
        ("floor(2.9)", 2.0),
        ("ceil(2.1)", 3.0),
        ("sqrt(9)", 3.0),
        ("sqrt(-1)", 0.0),
        ("clamp(15, 0, 10)", 10.0),
        ("clamp(-5, 0, 10)", 0.0),
        ("clamp(5, 0, 10)", 5.0),
    ])
    func scalarFunctions(expression: String, expected: Double) throws {
        #expect(try evaluate(expression) == expected)
    }

    @Test("The wrong number of arguments is reported, not guessed at")
    func argumentCountIsChecked() {
        #expect(throws: (any Error).self) { _ = try evaluate("sum()") }
        #expect(throws: (any Error).self) { _ = try evaluate("clamp(1, 2)") }
        #expect(throws: (any Error).self) { _ = try evaluate("sumproduct(1)") }
    }

    // MARK: - Lookups

    @Test("Quoted names reach the series, metric and column resolvers")
    func lookupsResolve() throws {
        let context = context(
            series: ["bench-press": [80, 82.5, 85]],
            metrics: ["water": [250, 500]],
            columns: ["weight": [10, 20]]
        )
        #expect(try evaluate("max(series(\"bench-press\"))", context) == 85)
        #expect(try evaluate("sum(metric(\"water\"))", context) == 750)
        #expect(try evaluate("sum(column(\"weight\"))", context) == 30)
    }

    /// The whole reason lookups take a quoted string: `bench-press` as a bare
    /// name would lex as a subtraction.
    @Test("A hyphenated series id survives because it is quoted")
    func hyphenatedIDsSurvive() throws {
        let context = context(series: ["front-squat-3rm": [100]])
        #expect(try evaluate("sum(series('front-squat-3rm'))", context) == 100)
    }

    @Test("A lookup with no matching data gives an empty list, not an error")
    func missingLookupIsEmpty() throws {
        #expect(try evaluate("sum(series(\"nothing\"))") == 0)
        #expect(try evaluate("count(metric(\"nothing\"))") == 0)
    }

    @Test("A lookup needs a quoted name")
    func lookupNeedsText() {
        #expect(throws: (any Error).self) { _ = try evaluate("series(3)") }
    }

    // MARK: - Real expressions

    /// A grocery running total. The engine has no idea that is what it is.
    @Test("Running total from subtotals")
    func runningTotal() throws {
        // Values chosen to be exact in binary, so this test is about the
        // evaluator and not about floating-point representation.
        let context = context(
            numbers: ["checkedCount": 2],
            lists: ["subtotal": [3.5, 2.0, 8.25], "checkedSubtotal": [3.5, 8.25]]
        )
        #expect(try evaluate("sum(subtotal)", context) == 13.75)
        #expect(try evaluate("sum(checkedSubtotal)", context) == 11.75)
        #expect(try evaluate("sum(subtotal) - sum(checkedSubtotal)", context) == 2.0)
    }

    /// Volume load. Same engine, same functions, different series names.
    @Test("Volume load pairs two series by position")
    func volumeLoad() throws {
        let context = context(metrics: ["weight": [80, 80, 85], "reps": [8, 8, 5]])
        #expect(try evaluate("sumproduct(metric(\"weight\"), metric(\"reps\"))", context) == 1705)
    }

    @Test("sumproduct stops at the shorter list rather than inventing values")
    func sumproductPairsPositionally() throws {
        let context = context(metrics: ["a": [2, 3, 4], "b": [10, 10]])
        #expect(try evaluate("sumproduct(metric(\"a\"), metric(\"b\"))", context) == 50)
    }

    @Test("Percentage of a target")
    func percentageOfTarget() throws {
        let context = context(numbers: ["target": 1000], lists: ["v": [250, 500]])
        #expect(try evaluate("sum(v) / target * 100", context) == 75)
    }

    // MARK: - Malformed input

    @Test("Malformed expressions are rejected", arguments: [
        "", "   ", "1 +", "(1", "1)", "* 2", "1 2", "sum(", "sum(1))", "@", "1 + $",
        "series(\"unclosed", "sum(1,)", "clamp(1 2 3)",
    ])
    func malformedThrows(expression: String) {
        #expect(throws: (any Error).self) { _ = try evaluate(expression) }
    }

    @Test("Deep nesting is refused rather than overflowing the stack")
    func deepNestingIsRefused() {
        let expression = String(repeating: "(", count: 200) + "1" + String(repeating: ")", count: 200)
        #expect(throws: FormulaError.tooComplex) { _ = try evaluate(expression) }
    }

    @Test("Function names are case-insensitive")
    func functionNamesAreCaseInsensitive() throws {
        #expect(try evaluate("SUM(3)") == 3)
        #expect(try evaluate("Abs(-2)") == 2)
    }
}
