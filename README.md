# Verso

A block-based notes app for iOS and iPadOS. Every feature is free — no paywall,
no subscription, no server.

The specification lives in [CLAUDE.md](CLAUDE.md). This file covers only the
state of the build.

---

## Status: Phase 1 complete, not yet compiled

Phase 1 (Foundation) is written in full — all nine numbered steps. It has
**never been compiled, run, or checked against the iOS 26 SDK**, because it was
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

### Known Phase 1 limitations

Deliberate, not oversights:

- **Text editing is a SwiftUI `TextField`.** Phase 2 replaces it with a
  TextKit 2 `UITextView`. Until then an edit rebuilds the attributed archive
  from plain text — harmless, because there is no formatting UI yet.
- **Stock rules do not scroll with the text.** They are drawn behind the list.
  Phase 2 moves them into `NSTextLayoutFragment` rendering, which is where they
  belong.
- **Every keystroke re-encodes the block payload.** Correct but chattier than it
  needs to be; coalescing belongs with the Phase 2 editor.
- **No app icon artwork.** `AppIcon.appiconset` is declared but empty.
- **Sync is untested.** §9 requires verification across two simulators on one
  iCloud account. That needs a Mac.

### Deviations from the specification

Two, both minor, both flagged rather than silently taken:

1. **`Motion` tokens are computed properties, not `static let`.** Functionally
   identical, and avoids depending on whether `SwiftUI.Animation` is `Sendable`
   on a given SDK.
2. **Themes carry an optional `accentAlternate`.** §6 lists a second accent for
   `riso` (`#0B4BD4`) with no column for it. It is stored rather than dropped;
   nothing in Phase 1 reads it.

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

Still owed by §9: formula evaluation, geofence budget manager, and vault
encrypt/decrypt — those arrive with Phases 3, 4 and 8.
