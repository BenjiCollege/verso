import Foundation
import SwiftData
import Testing
@testable import VersoKit

@Suite("Geofence budget")
struct GeofenceBudgetTests {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// Roughly London. Longitude degrees are ~68km apart at this latitude, so
    /// "east by n" gives predictable, well-separated distances.
    private let origin = Coordinate(latitude: 51.5074, longitude: -0.1278)

    private func east(_ steps: Double) -> Coordinate {
        Coordinate(latitude: origin.latitude, longitude: origin.longitude + steps * 0.01)
    }

    private func candidate(
        _ label: String,
        center: Coordinate?,
        actionable: Bool = true,
        activity: TimeInterval = 0,
        noteID: UUID = UUID(),
        blockID: UUID = UUID()
    ) -> GeofenceCandidate {
        GeofenceCandidate(
            id: GeofenceIdentity(noteID: noteID, blockID: blockID),
            target: PlaceTarget(
                name: label,
                coordinate: center,
                poiCategory: center == nil ? "MKPOICategoryFoodMarket" : nil,
                radius: 150,
                trigger: .arrive
            ),
            center: center,
            isActionable: actionable,
            lastActivity: now.addingTimeInterval(activity),
            noteTitle: label
        )
    }

    // MARK: - The limit

    /// The number that makes this whole type necessary. iOS silently ignores
    /// the twenty-first region.
    @Test("The system limit is twenty and cannot be raised")
    func systemLimitIsFixed() {
        #expect(GeofenceBudget.systemLimit == 20)
        #expect(GeofenceBudget(limit: 50).limit == 20)
        #expect(GeofenceBudget(limit: -1).limit == 0)
        #expect(GeofenceBudget(limit: 5).limit == 5)
    }

    @Test("Everything past the limit is deferred, not dropped")
    func overBudgetCandidatesAreDeferred() {
        let candidates = (0..<25).map { candidate("p\($0)", center: east(Double($0))) }
        let plan = GeofenceBudget().plan(candidates: candidates, userLocation: origin)

        #expect(plan.monitored.count == 20)
        #expect(plan.deferred.count == 5)
        #expect(plan.isOverBudget)
        // Nothing may be silently lost: every candidate is accounted for.
        #expect(plan.monitored.count + plan.deferred.count + plan.unresolved.count + plan.dormant.count == 25)
    }

    @Test("Under the limit, nothing is deferred")
    func underBudgetIsClean() {
        let plan = GeofenceBudget().plan(
            candidates: (0..<5).map { candidate("p\($0)", center: east(Double($0))) },
            userLocation: origin
        )
        #expect(plan.monitored.count == 5)
        #expect(!plan.isOverBudget)
    }

    // MARK: - Ranking

    @Test("Nearer places win")
    func nearestFirst() {
        let far = candidate("far", center: east(10))
        let near = candidate("near", center: east(1))
        let middle = candidate("middle", center: east(5))

        let plan = GeofenceBudget(limit: 2).plan(
            candidates: [far, near, middle],
            userLocation: origin
        )

        #expect(plan.monitored.map(\.target.name) == ["near", "middle"])
        #expect(plan.deferred.map(\.target.name) == ["far"])
    }

    /// Section 7 asks for proximity *and* recency. Recency is the tiebreak, not
    /// the other way round — a list you edited this morning is no use if it is
    /// two hundred miles away.
    @Test("Recency breaks ties between equally distant places")
    func recencyBreaksTies() {
        let sameSpot = east(3)
        let old = candidate("old", center: sameSpot, activity: -86_400)
        let recent = candidate("recent", center: sameSpot, activity: -60)

        let plan = GeofenceBudget(limit: 1).plan(candidates: [old, recent], userLocation: origin)
        #expect(plan.monitored.map(\.target.name) == ["recent"])
    }

    /// Two runs with the same inputs must produce the same plan, or every
    /// refresh would churn regions in and out for no reason.
    @Test("Ranking is stable when distance and recency both tie")
    func rankingIsDeterministic() {
        let spot = east(2)
        let candidates = (0..<6).map { candidate("p\($0)", center: spot) }

        let first = GeofenceBudget(limit: 3).plan(candidates: candidates, userLocation: origin)
        let second = GeofenceBudget(limit: 3).plan(candidates: candidates.reversed(), userLocation: origin)

        #expect(first.monitored.map(\.id) == second.monitored.map(\.id))
    }

    /// With no fix there is no proximity to rank by, so the ranking must fall
    /// back to recency rather than to whatever order the fetch happened to
    /// return.
    @Test("Without a location fix, ranking falls back to recency")
    func noLocationFallsBackToRecency() {
        let old = candidate("old", center: east(1), activity: -86_400)
        let recent = candidate("recent", center: east(9), activity: -60)

        let plan = GeofenceBudget(limit: 1).plan(candidates: [old, recent], userLocation: nil)
        #expect(plan.monitored.map(\.target.name) == ["recent"])
    }

    @Test("A candidate with no coordinate never outranks one that has one")
    func unresolvedNeverOutranksResolved() {
        let resolved = candidate("resolved", center: east(40), activity: -86_400)
        let unresolved = candidate("unresolved", center: nil, activity: 0)

        let plan = GeofenceBudget(limit: 1).plan(candidates: [resolved, unresolved], userLocation: origin)

        #expect(plan.monitored.map(\.target.name) == ["resolved"])
        #expect(plan.unresolved.map(\.target.name) == ["unresolved"])
    }

    // MARK: - Actionability

    @Test("Checked-off reminders are dormant and never take a slot")
    func dormantCandidatesAreExcluded() {
        let done = candidate("done", center: east(1), actionable: false)
        let todo = candidate("todo", center: east(9))

        let plan = GeofenceBudget(limit: 1).plan(candidates: [done, todo], userLocation: origin)

        #expect(plan.monitored.map(\.target.name) == ["todo"])
        #expect(plan.dormant.map(\.target.name) == ["done"])
        #expect(!plan.isOverBudget, "a dormant reminder is not competing for a slot")
    }

    @Test("A library of only finished lists monitors nothing")
    func allDormant() {
        let plan = GeofenceBudget().plan(
            candidates: (0..<5).map { candidate("p\($0)", center: east(Double($0)), actionable: false) },
            userLocation: origin
        )
        #expect(plan.monitored.isEmpty)
        #expect(plan.dormant.count == 5)
    }

    @Test("An empty library produces an empty plan")
    func emptyPlan() {
        let plan = GeofenceBudget().plan(candidates: [], userLocation: origin)
        #expect(plan == GeofencePlan(limit: GeofenceBudget.systemLimit))
    }

    // MARK: - Status reporting

    /// Section 7: when a place reminder is inactive, tell the user — never fail
    /// silently. Every state has to have something to say.
    @Test("Every inactive state has a message, and the active one has none")
    func statusesExplainThemselves() {
        let monitored = candidate("near", center: east(1))
        let deferred = candidate("far", center: east(9))
        let unresolved = candidate("category", center: nil)
        let dormant = candidate("done", center: east(2), actionable: false)

        let plan = GeofenceBudget(limit: 1).plan(
            candidates: [monitored, deferred, unresolved, dormant],
            userLocation: origin
        )

        #expect(plan.status(for: monitored.id) == .monitoring)
        #expect(plan.status(for: monitored.id).isActive)
        #expect(plan.status(for: monitored.id).message == nil)

        for candidate in [deferred, unresolved, dormant] {
            let status = plan.status(for: candidate.id)
            #expect(!status.isActive)
            #expect(status.message?.isEmpty == false, "\(status) must explain itself")
        }

        #expect(plan.status(for: GeofenceIdentity(noteID: UUID(), blockID: UUID())) == .unknown)
    }

    @Test("A deferred reminder is told its position in the queue")
    func deferredReportsItsPosition() {
        let candidates = (0..<4).map { candidate("p\($0)", center: east(Double($0))) }
        let plan = GeofenceBudget(limit: 2).plan(candidates: candidates, userLocation: origin)

        #expect(plan.status(for: candidates[2].id) == .deferred(position: 3, limit: 2))
        #expect(plan.status(for: candidates[3].id) == .deferred(position: 4, limit: 2))
    }

    /// A category resolves to several branches. The block is active if any one
    /// of them is.
    @Test("A block's status is the best of the regions it produced")
    func blockStatusIsTheBestOfItsRegions() {
        let noteID = UUID()
        let blockID = UUID()

        func branch(_ index: Int, _ center: Coordinate) -> GeofenceCandidate {
            var result = candidate("branch\(index)", center: center, noteID: noteID, blockID: blockID)
            result.id = GeofenceIdentity(noteID: noteID, blockID: blockID, resolutionIndex: index)
            return result
        }

        let plan = GeofenceBudget(limit: 1).plan(
            candidates: [branch(0, east(9)), branch(1, east(1))],
            userLocation: origin
        )

        #expect(plan.status(forBlock: blockID, noteID: noteID) == .monitoring)
    }

    // MARK: - Identity

    @Test("Identities round-trip through their string form")
    func identityRoundTrips() throws {
        let withItem = GeofenceIdentity(noteID: UUID(), blockID: UUID(), itemID: UUID(), resolutionIndex: 2)
        let withoutItem = GeofenceIdentity(noteID: UUID(), blockID: UUID())

        #expect(GeofenceIdentity(stringValue: withItem.stringValue) == withItem)
        #expect(GeofenceIdentity(stringValue: withoutItem.stringValue) == withoutItem)
        #expect(GeofenceIdentity(stringValue: "nonsense") == nil)
        #expect(GeofenceIdentity(stringValue: "a|b|c|d") == nil)
    }

    @Test("A block's regions share a scope prefix")
    func blockScopeMatchesItsRegions() {
        let noteID = UUID()
        let blockID = UUID()
        let scope = GeofenceIdentity(noteID: noteID, blockID: blockID).blockScope

        for index in 0..<3 {
            let identity = GeofenceIdentity(noteID: noteID, blockID: blockID, resolutionIndex: index)
            #expect(identity.stringValue.hasPrefix(scope))
        }
        #expect(!GeofenceIdentity(noteID: noteID, blockID: UUID()).stringValue.hasPrefix(scope))
    }
}

@Suite("Geofence candidates")
struct GeofenceCandidateBuilderTests {

    private func makeNote(in context: ModelContext, title: String = "List") -> Note {
        let note = Note(title: title)
        context.insert(note)
        return note
    }

    private func attach<P: BlockPayload>(_ payload: P, to note: Note, in context: ModelContext) throws -> Block {
        let block = try Block(payload)
        context.insert(block)
        note.append(block)
        return block
    }

    private var somewhere: ChecklistPayload.ItemPlace {
        .init(latitude: 51.5, longitude: -0.12, radius: 200)
    }

    @Test("An unchecked item with a place is actionable; a checked one is not")
    func checklistItemActionability() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = makeNote(in: context)

        _ = try attach(
            ChecklistPayload(items: [
                .init(label: "Milk", checked: false, place: somewhere),
                .init(label: "Bread", checked: true, place: somewhere),
                .init(label: "No place"),
            ]),
            to: note,
            in: context
        )

        let candidates = GeofenceCandidateBuilder.candidates(in: note)
        #expect(candidates.count == 2)
        #expect(candidates.filter(\.isActionable).map(\.target.name) == ["Milk"])
    }

    @Test("A place block stays actionable while its note has unchecked items")
    func placeBlockFollowsTheList() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = makeNote(in: context)

        _ = try attach(PlacePayload(name: "Shop", coordinate: .init(latitude: 51.5, longitude: -0.12)), to: note, in: context)
        let checklist = try attach(ChecklistPayload(items: [.init(label: "Milk")]), to: note, in: context)

        #expect(GeofenceCandidateBuilder.candidates(in: note).allSatisfy { $0.isActionable })

        var payload = try checklist.decoded(as: ChecklistPayload.self)
        payload.items[0].checked = true
        try checklist.store(payload)

        #expect(GeofenceCandidateBuilder.candidates(in: note).allSatisfy { !$0.isActionable })
    }

    /// A standalone "remind me when I get there" note has nothing to check off,
    /// and must not be dormant forever because of it.
    @Test("A place block in a note with no checklist stays actionable")
    func standalonePlaceBlockStaysActive() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = makeNote(in: context)
        _ = try attach(PlacePayload(name: "Home", coordinate: .init(latitude: 51.5, longitude: -0.12)), to: note, in: context)

        #expect(GeofenceCandidateBuilder.candidates(in: note).allSatisfy { $0.isActionable })
    }

    @Test("A trashed or hidden note contributes nothing")
    func trashedNotesAreIgnored() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = makeNote(in: context)
        _ = try attach(PlacePayload(name: "Shop", coordinate: .init(latitude: 51.5, longitude: -0.12)), to: note, in: context)

        note.isTrashed = true
        #expect(GeofenceCandidateBuilder.candidates(in: note).isEmpty)

        note.isTrashed = false
        note.isHidden = true
        #expect(GeofenceCandidateBuilder.candidates(in: note).isEmpty)
    }

    @Test("A category place with no coordinate is still a candidate, just unresolved")
    func categoryPlacesAreCandidates() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = makeNote(in: context)
        _ = try attach(PlacePayload(poiCategory: "MKPOICategoryFoodMarket"), to: note, in: context)

        let candidates = GeofenceCandidateBuilder.candidates(in: note)
        #expect(candidates.count == 1)
        #expect(!candidates[0].isResolved)
        #expect(candidates[0].isActionable)
    }

    @Test("A place with neither coordinate nor category is not a candidate")
    func emptyPlacesAreSkipped() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = makeNote(in: context)
        _ = try attach(PlacePayload(name: "Nowhere"), to: note, in: context)

        #expect(GeofenceCandidateBuilder.candidates(in: note).isEmpty)
    }

    /// (0, 0) is a real place in the Atlantic and never what a half-filled
    /// payload meant.
    @Test("A null island coordinate is rejected")
    func nullIslandIsRejected() {
        #expect(!Coordinate(latitude: 0, longitude: 0).isValid)
        #expect(!Coordinate(latitude: 91, longitude: 0).isValid)
        #expect(Coordinate(latitude: 51.5, longitude: -0.12).isValid)
    }

    @Test("Radii are clamped to what a geofence can actually do")
    func radiusClamping() {
        #expect(PlaceTarget.clampRadius(10) == 100)
        #expect(PlaceTarget.clampRadius(150) == 150)
        #expect(PlaceTarget.clampRadius(999_999) == 10_000)
    }
}
