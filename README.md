# Verso

A block-based notes app for iOS and iPadOS. Every feature is free — no paywall,
no subscription, no server.

The specification lives in [CLAUDE.md](CLAUDE.md). This file covers only the
state of the build.

---

## Status: Phases 1–6 complete, not yet compiled

Phases 1 (Foundation), 2 (Editor), 3 (Data blocks), 4 (Time and place),
5 (Templates) and 6 (Fore-edge and history) are written in full. None of it has
**ever been compiled, run, or checked against the iOS 26 SDK**, because it was
authored on Windows 11 with no Xcode, no Swift toolchain, and no simulator
available.

Everything below is therefore written from knowledge of the frameworks rather
than verified against the installed SDK, which is the opposite of the rule in
§1 of CLAUDE.md. That was a deliberate, agreed trade — the code exists to be
ported and fixed on a Mac, not to be trusted as-is.

### First run on a Mac

```bash
open Verso.xcodeproj
```

Then, in order:

1. Set your team and change `PRODUCT_BUNDLE_IDENTIFIER` from `com.verso.notes`.
   The iCloud container in `Config/Verso.entitlements`
   (`iCloud.com.verso.notes`) and `VersoModelContainer.cloudKitContainerIdentifier`
   must be changed to match.
2. Build. Expect compile errors; fix them rather than working around them.
3. Run the test suite — it is the fastest way to find what drifted.

### What to check first

These are the places where an unverified API is most likely to be wrong. They
are ordered by how much of the build they would block.

| Area | What to verify |
|---|---|
| `Verso.xcodeproj/project.pbxproj` | Hand-written, using Xcode 16+ synchronized filesystem groups (`objectVersion = 77`). If Xcode refuses it, create a fresh project and drag the `Verso/` and `VersoTests/` folders in — the source tree is the project structure by design, so nothing else needs to move. |
| `@Entry` macro | Used for every environment key. Xcode 16+ macro. |
| `ModelConfiguration(_:schema:isStoredInMemoryOnly:allowsSave:cloudKitDatabase:)` | Argument label order and the `.private(_:)` case. |
| `SWIFT_APPROACHABLE_CONCURRENCY` | Enabled; `SWIFT_DEFAULT_ACTOR_ISOLATION` is deliberately left at `nonisolated`. |
| Swift Testing parameterised tests | `@Test(arguments:)` with a struct and with tuples. |
| `NSKeyedArchiver` round-trip in `TextPayload` | Secure-coding archive of `NSAttributedString`. |
| `Decimal` through `JSONEncoder` | `BlockPayloadRoundTripTests` asserts `3.49` survives exactly. |
| `Canvas` + `GraphicsContext` calls in `StockPattern` | Signatures of `stroke`, `fill`, `StrokeStyle`. |
| `Image(decorative:scale:)` + `.resizable(resizingMode: .tile)` | Grain tiling. |
| `count(where:)`, `Locale.current.currency` | Small standard-library and Foundation calls. |

Phase 2 adds a second, larger cluster of unverified surface. In rough order of
how much would break if it is wrong:

| Area | What to verify |
|---|---|
| `UITextView(usingTextLayoutManager: true)` inherited by `VersoTextView` | `VersoTextView.make()` deliberately declares no initialiser so this one is inherited. If a subclass initialiser creeps in, TextKit 1 takes over silently and the fragment rendering simply never runs. |
| `NSTextLayoutFragment` subclassing | `init(textElement:range:)`, `textLineFragments`, and whether `typographicBounds` is fragment-relative as assumed in `PageTextLayoutFragment.drawRules`. |
| `NSTextLayoutManagerDelegate` isolation | `PageLayoutDelegate.snapshot` is `nonisolated(unsafe)` precisely because this is unknown. If the protocol turns out to be `@MainActor`, drop the annotation. |
| `NSTextLayoutManager.setRenderingAttributes(_:for:)` / `invalidateRenderingAttributes(for:)` | Focus Mode dimming. Also `NSTextContentManager.location(_:offsetBy:)`, used to bridge `NSRange` to `NSTextRange`. |
| `ScrollPosition.scrollTo(y:)` and `onScrollGeometryChange` | iOS 18 scroll APIs; typewriter scroll depends on both. |
| `onGeometryChange(for:of:action:)` | Reports each text block's frame in the page coordinate space. |
| `nonisolated init()` on `@MainActor @Observable` | `TextEditingSession`, so the environment key can build a default. |
| `@ModelActor` on `LinkIndexBuilder` | Generated `init(modelContainer:)` and background-context fetching. |

Phase 3 is mostly plain Swift and correspondingly lower-risk. What is left to
verify:

| Area | What to verify |
|---|---|
| Swift Charts marks | `BarMark` / `LineMark` / `PointMark` / `RuleMark` modifier names, and `AXChartDescriptorRepresentable` + `accessibilityChartDescriptor`. |
| `AVAudioSession` category options | `.playback` with `[.mixWithOthers, .duckOthers]`, and that no `UIBackgroundModes` entry is needed for it. |
| `UNMutableNotificationContent.interruptionLevel` | `.timeSensitive` needs the Time Sensitive Notifications capability adding in Xcode. |
| `Grid` / `GridRow` in a horizontal `ScrollView` | The table block's layout. |
| `accessibilityAdjustableAction` | The rating block is one adjustable control rather than N buttons. |

Phase 4 leans on Core Location's newest API, which is where its risk sits:

| Area | What to verify |
|---|---|
| `CLMonitor` | `await CLMonitor(name)`, `add(_:identifier:)`, `remove(_:)`, `identifiers`, and the `events` stream. This is the iOS 17+ replacement for the deprecated `startMonitoring(for:)`; picking the modern API over the familiar one was deliberate, but none of it is verified. Confirm the ~20-condition ceiling still holds — `GeofenceBudget.systemLimit` encodes it. |
| `CLMonitor.Event.state` | The `.satisfied` / `.unsatisfied` cases that arrival and departure map onto. |
| `MKLocalPointsOfInterestRequest` | Category resolution, its 50km radius ceiling, and the `MKPointOfInterestCategory` cases in `PlaceResolver.offeredCategories`. |
| `MapReader` + `proxy.convert(_:from:)` | Tap-to-drop-a-pin in the place picker. |
| `@Observable` on an `NSObject` subclass | `LocationAuthority` is both, so it can be a `CLLocationManagerDelegate`. |
| Always-authorisation flow | When In Use must be granted before Always can be requested. |

Phase 5 is mostly JSON and pure Swift. What is left to verify:

| Area | What to verify |
|---|---|
| `UTType(exportedAs:conformingTo:)` | Must match the `UTExportedTypeDeclarations` entry in `Info.plist` exactly, or `.versotemplate` files will not open in Verso. |
| `fileImporter` + `ShareLink(item: URL)` | Template import and export. |
| `ContentUnavailableView.search(text:)` | Empty states in the gallery and the catalog picker. |
| Application Support directory | User templates are written there; confirm it exists or is created on first save. |

Phase 6's risk is concentrated in Core Haptics, which cannot be exercised in the
simulator at all:

| Area | What to verify |
|---|---|
| `CHHapticEngine.playPattern(from:)` | The five authored AHAP files. Check them on a device — a wrong intensity is not a compile error, and silence is indistinguishable from unsupported hardware. |
| `CHHapticAdvancedPatternPlayer.sendParameters(_:atTime:)` | Live modulation of the fore-edge scrub bed by thumb velocity. |
| `NSData.compressed(using: .zlib)` | Snapshot compression, in both directions. |
| Detached `@Model` instances | `VersionPreview` builds `Block` objects belonging to no `ModelContext` so history renders through the same views as the present. |
| `DragGesture.Value.time` | Used for scrub velocity. |

### Known limitations

Deliberate, not oversights:

- **No app icon artwork.** `AppIcon.appiconset` is declared but empty.
- **Sync is untested.** §9 requires verification across two simulators on one
  iCloud account. That needs a Mac.
- **The backlink index is in memory, not persisted.** Links live inside archived
  text, which SwiftData cannot form a predicate against. It builds on first use
  rather than at launch, so it costs nothing against the 400ms budget, and every
  later edit patches it incrementally. If a library ever grows large enough for
  the first build to be felt, the fix is a persisted `NoteLink` model — a schema
  change, and therefore yours to approve.
- **Headings and list items are still plain `TextField`s.** Only `text` blocks
  are rich. Nothing in §5 gives them inline marks.
- **User templates do not sync.** They are files in Application Support, which
  is what makes export and import the same bytes that are already on disk — a
  template changes hands as a file and no server is involved. Syncing them would
  mean a `UserTemplate` `@Model`, which is a schema change and therefore yours
  to approve.
- **The exercise library holds ~170 entries, not ~200.** §7 asks for about two
  hundred. Padding it with near-duplicates would make the picker worse, so the
  gap is left visible; adding more is one JSON file edit and no Swift.

### Deviations from the specification

All flagged rather than silently taken:

1. **`Motion` tokens are computed properties, not `static let`.** Functionally
   identical, and avoids depending on whether `SwiftUI.Animation` is `Sendable`
   on a given SDK.
2. **Themes carry an optional `accentAlternate`.** §6 lists a second accent for
   `riso` (`#0B4BD4`) with no column for it. It is stored rather than dropped.
3. **Grain is a fixed page texture, not per-fragment.** §7 groups grain with the
   rules under `NSTextLayoutFragment` rendering. Rules *are* per-fragment, which
   is what puts them on real baselines. Grain is not: drawing it per fragment
   would texture only where there are words, leaving the margins and everything
   past the last block bare.
4. **Block reordering moved into its own sheet.** Typewriter scroll needs an
   exact content offset, and `List` will not surrender one, so the page became a
   `ScrollView`. Reordering kept `List` — and with it drag-and-drop and
   VoiceOver — on a screen built for it.
5. **A `[[wiki link]]` is followed from the formatting bar, not by tapping it.**
   In an editable text view a tap places the caret, which is correct; you cannot
   edit text you cannot click into. When the caret sits inside a link, an open
   action appears in the bar instead.
6. **`metric.value` and `rating.value` are optional; `table` gained a `caption`
   and `rating` a `symbol`.** §5 lists field names, not optionality. An unfilled
   metric is not a measurement of zero and must not pull a chart down to the
   axis, so it stores as absent.
7. **`Core/Timers/` is a new directory.** §3's tree has no home for a service
   that owns both `AVAudioSession` and `UNUserNotificationCenter`; filing it
   under `Audio/` would misdescribe it.
8. **`schedule` gained a `label`, `place` gained a `name`.** §5 lists the other
   fields; a reminder with nothing to call it is unusable in a list and unusable
   in a notification.
9. **`Core/Schedule/` is a new directory**, alongside the `Core/Timers/` added
   in Phase 3.
10. **`Recurrence` is structured, not an RRULE string.** The app has to *compute*
    occurrences — `UNCalendarNotificationTrigger` can only repeat the simple
    shapes, and everything else is scheduled a few ahead and topped up. Parsing
    RRULE to do that would be a lot of surface for no gain.
11. **`metric` gained four options: `showsPreviousEntry`, `restTimerSeconds`,
    `decomposition` and `catalogID`.** These are how §7's strength
    non-negotiables are met without a single template identifier in Swift.
    Every one is a property of *a metric* — a cooldown, a previous reading, a
    decomposition into available units, a list to pick a name from — and every
    one is switched on by JSON. `Decomposition` is deliberately named for what
    it does rather than for plates.
12. **"One-tap repeat set" is table row duplication.** Repeating a row copies
    its values and clears its checkboxes, which is what "same again" means for
    any table, not just a set of squats.
13. **The fore-edge previews; it does not restore.** §6 says dragging scrubs
    history and content morphs backward as the thumb travels, which it does.
    Letting go leaves the past version on screen with a bar offering *Restore*
    or *Back to Now*. Overwriting a note because a thumb happened to stop
    somewhere would be indefensible, and restoring records the present first, so
    it is reversible either way.
14. **The fore-edge scrub bed is built in code, not authored as AHAP.** The
    other five patterns are files. Every parameter the scrub starts with is
    replaced by thumb velocity within milliseconds, so authoring them would be
    documentation pretending to be design.
15. **No `UIBackgroundModes: audio`.** §7 specifies `AVAudioSession` + a local
   notification for rest timers. The session here only makes the completion
   sound audible over music and with the ringer switch off. Background delivery
   is the notification's job — claiming the audio background mode for a notes
   app that plays no continuous audio is an App Review rejection waiting to
   happen. `.timeSensitive` interruption level does need the Time Sensitive
   Notifications capability adding in Xcode.

---

## Structure

The folder layout in §3 of CLAUDE.md *is* the Xcode project structure —
synchronized groups mean adding a file needs no project-file edit.

Two rules keep the engine content-agnostic, and both are enforced by tests:

- **Decoding goes through `BlockRegistry`.** The only `switch` over `BlockType`
  is the view factory in `Core/Blocks/BlockRenderer.swift`.
- **Adding a template is one JSON file and zero Swift.**
  `TemplateInstantiationTests.newTemplateNeedsNoSwift` invents a template at
  runtime and builds it through the same path the bundled ones use.

Adding a theme or a paper stock is likewise one JSON file in
`Verso/Resources/`.

## Tests

| Suite | Covers |
|---|---|
| `BlockPayloadRoundTripTests` | Encode/decode for all five Phase 1 payloads, encoding determinism, registry transcoding, forward-compatible degradation, checklist sectioning |
| `ThemeLoaderTests` | All six themes and seven stocks load; palettes match §6 exactly; hex parsing; Increase Contrast and Reduce Transparency resolution |
| `TypographyTokenTests` | The 34/26/20/17/15/13/11 scale, 1.55× leading, the 68-character measure |
| `MotionResolverTests` | Every token and every reveal style has a reduce-motion path |
| `TemplateInstantiationTests` | Both templates, persistence, failure modes, the zero-Swift guarantee |
| `SchemaValidityTests` | CloudKit constraints, cascade deletes, block position density, tag dedupe, metric series queries |
| `InlineStyleTests` | Marks survive archiving, presentation never does, toggling is reversible and independent, a mixed selection reports no common mark |
| `WikiLinkTests` | Link and draft parsing, malformed brackets, UTF-16 offsets |
| `TypewriterScrollerTests` | Anchoring, the jitter deadband, clamping at both ends, the reserved bottom inset |
| `LinkGraphTests` / `LinkIndexTests` | Both directions stay consistent, links resolve by title and by stored id, a renamed target keeps its edge, unresolved titles are kept |
| `FormulaTests` | Arithmetic and precedence, aggregations, lookups, a running total and a volume load, and every malformed input being rejected rather than guessed at |
| `MetricSeriesTests` | Daily bucketing, moving averages, scoped series queries, idempotent recording, personal records excluding themselves, label slugging |
| `DataBlockPayloadTests` | Round-trip for all six new payloads, clamping, ragged-table repair, unknown enums degrading |
| `RestTimerTests` | Remaining time from the wall clock, finishing, pausing, encoding for relaunch |
| `GeofenceBudgetTests` | The twenty-region ceiling, proximity-then-recency ranking, deterministic ordering, dormant reminders never taking a slot, and every inactive state having something to say |
| `GeofenceCandidateBuilderTests` | Which places are actionable, trashed notes contributing nothing, null-island rejection, radius clamping |
| `RecurrenceTests` | Every frequency and interval, multi-weekday weeks, month-end clamping, end dates and occurrence counts, and which series map onto a repeating system trigger |
| `ScheduleNotificationPlannerTests` | Alarm offsets, past alarms dropped, repeating vs concrete scheduling, identifier scoping, and the pending-notification budget |
| `TemplateLibraryTests` | All 24 templates plus blank, six per category, every one instantiable, every formula parsing, every theme/stock reference resolving, and the strength template switching on all six non-negotiables |
| `CatalogTests` | The exercise library loads, ids are unique and match the metric block's slug, search covers names and facets |
| `DecompositionTests` | Exact loads, greedy order, shortfall reported rather than rounded away, no floating-point drift at 1.25kg granularity |
| `TemplateAuthoringTests` | Structure preserved and personal data dropped, export/import round trip, unknown block types skipped |
| `UserTemplateStoreTests` | Save, rename, delete, export/import minting a new id, hostile filenames sanitised |
| `NoteSnapshotTests` | Deltas rewind exactly, carry only what changed, distinguish a field cleared from one untouched, and survive compression |
| `VersionPolicyTests` | Which edits are history and which are typos being fixed |
| `VersionStoreTests` | Every version in a long delta chain reconstructing exactly, restore being reversible, pruning never orphaning a delta |
| `ForeEdgeModelTests` / `ForeEdgeScrubberTests` | Density encoding length, pattern encoding theme deterministically, the drag mapping and its inverse agreeing |
| `HapticPatternTests` | Every named moment has a well-formed AHAP file present in the bundle |

Still owed by §9: vault encrypt/decrypt, which arrives with Phase 8.
