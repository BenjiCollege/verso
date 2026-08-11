# Verso

A block-based notes app for iOS and iPadOS. Every feature is free — no paywall,
no subscription, no server.

The specification lives in [CLAUDE.md](CLAUDE.md). This file covers only the
state of the build.

---

## Status: Phases 1–2 complete, not yet compiled

Phase 1 (Foundation) and Phase 2 (Editor) are written in full. Neither has
**ever been compiled, run, or checked against the iOS 26 SDK**, because they
were authored on Windows 11 with no Xcode, no Swift toolchain, and no simulator
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

Still owed by §9: formula evaluation, geofence budget manager, and vault
encrypt/decrypt — those arrive with Phases 3, 4 and 8.
