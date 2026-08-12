# Verso

A block-based notes app for iOS and iPadOS, built around the idea that a note is
a **page** rather than a text field. Every note carries a paper stock, a theme
and a typographic scale; text is laid out through TextKit 2 so the ruled lines
sit on real baselines rather than being a background image.

Every feature is free. No paywall, no subscription, no accounts, and no server —
the only sync is CloudKit's private database, which is the user's own iCloud, and
every intelligent feature runs on-device or not at all.

**What a note is made of.** A note is an ordered list of typed blocks — text,
heading, checklist, list, table, divider, metric, rating, progress, formula,
timer, schedule, place, ink, audio, attachment. The engine never switches on
block type outside one view factory; everything else goes through a registry
that maps a type to its payload. Templates are JSON, so a new one is a file and
no Swift.

Some of what that buys, concretely:

- **Formulas** that read the blocks around them — `sum(subtotal)` over a
  checklist, a running volume load over a strength table
- **Metric series** shared across features, so sleep from a journal template and
  a working set from a workout land in one queryable store and chart together
- **Place and schedule blocks** that become geofenced or recurring reminders,
  budgeted against the system's ~20-region ceiling
- **A vault** — per-note encryption with a passphrase-derived key, so locked
  notes open on a second device without the key ever reaching a server
- **A fore-edge** — drag the page edge to scrub through version history, with
  the paper's edge texture encoding where the changes are
- **Audio notes with a sync map**, so tapping a word plays the moment it was
  written, and ink replays stroke by stroke
- **Read Mode** with an authored reveal — words or glyphs arriving on a stagger,
  every style with a Reduce Motion path
- **On-device intelligence** for titling, tagging, summarising and structuring
  captured text, each with a working heuristic fallback when the model is
  unavailable

> The specification is `CLAUDE.md`, which is **not in this repository**. The `§`
> references throughout this file point at its sections.

---

## Status

CI is green. The project compiles against the iOS 26 SDK and **467 tests in 50
suites pass** on the simulator, on every push.

What that does *not* cover, and what nobody should assume from the green tick:

- It has **never run on a physical device**. Haptics, biometrics, Pencil,
  geofencing and the on-device language model cannot be exercised in a simulator
  at all.
- It has **never synced**. Two devices on one iCloud account is the only real
  test of the CloudKit schema, and it hasn't happened.
- There is **no app icon**. `AppIcon.appiconset` declares three 1024×1024 slots
  and contains no images.

It was written on Windows 11 with no Xcode, no Swift toolchain and no simulator,
which is why the repo is arranged so a Mac is never required: `project.yml` is
the source of truth, `.xcodeproj` is generated, and CI builds on a runner.

[TESTFLIGHT.md](TESTFLIGHT.md) covers signing and distribution.
[SUBMISSION.md](SUBMISSION.md) separates what is done in the repo from what
still needs you.

---

## What it's built on

**No third-party dependencies.** Everything below ships with the platform.

| Framework | What it does here |
|---|---|
| **SwiftUI** | Every screen. UIKit appears only where SwiftUI has no equivalent. |
| **SwiftData** + **CloudKit** | The store, synced through the user's private database. The schema obeys CloudKit's constraints — no `.unique`, everything defaulted or optional, every relationship with a declared inverse — and `SchemaValidityTests` asserts it, so a violation fails a test rather than the first sync. |
| **TextKit 2** (`UIKit`) | Ruled paper, focus dimming and the per-glyph reveal, all done by subclassing `NSTextLayoutFragment` and setting rendering attributes — so none of it forces a re-layout. |
| **PencilKit** | Ink blocks and PDF annotation. Stroke timestamps drive the ink half of the audio sync map. |
| **PDFKit** + **CoreGraphics** + **ImageIO** | Document viewing, annotation, PDF export in two forms (flattened and layered), and the animated share card. |
| **AVFoundation** + **Speech** | Audio notes, recorded as mono AAC, transcribed strictly on-device. |
| **FoundationModels** | Titling, tagging, summarising, structuring. Every use has a heuristic fallback that runs when the model is unavailable — which is most of the install base. |
| **NaturalLanguage** | Sentence embeddings for semantic search, with a lexical path for the many languages that have none. |
| **CoreLocation** + **MapKit** | Place blocks and arrival reminders, via `CLMonitor` rather than the deprecated region API. |
| **UserNotifications** | Schedules, timers and geofence reminders. Time-sensitive interruption levels, with the entitlement to match. |
| **CryptoKit** + **CommonCrypto** + **Security** + **LocalAuthentication** | The vault: AES-GCM content encryption, PBKDF2 for the passphrase-derived key, two Keychain items because a biometry-bound one cannot sync. |
| **CoreHaptics** | Five authored AHAP patterns, plus one live-modulated bed for the fore-edge scrub. |
| **Swift Charts** + **Accessibility** | Metric charts, each with an `AXChartDescriptor` so they are audible as well as visible. |
| **AppIntents** + **WidgetKit** + **CoreSpotlight** | Shortcuts, widgets, a Control Centre control, Handoff and Spotlight indexing — all of which honour the same vault exclusions the library does. |
| **Swift Testing** | The whole suite. No XCTest. |

Swift 6 language mode with strict concurrency, `SWIFT_DEFAULT_ACTOR_ISOLATION`
deliberately left at `nonisolated` rather than `MainActor`. iOS 26 deployment
target.

---

## Structure

A thin Xcode project over a local Swift package.

```
project.yml               the project, as source — .xcodeproj is generated
.github/workflows/        build+test on every push; release on manual dispatch
scripts/                  what was actually signed, verified
VersoKit/                 the whole app, as a package
  Package.swift
  Sources/VersoKit/
    App/                  VersoScene, RootView, NavigationRequest
    Core/                 the engine — see below
    Features/             the screens
    Intents/              App Intents and their entities
    Widgets/              the widget and control views
    Resources/            themes, stocks, templates, exercises, haptics
Verso/                    the app target
  App/VersoApp.swift      @main, and nothing else
  Resources/              asset catalogue, PrivacyInfo.xcprivacy
VersoWidgets/             the extension target
  VersoWidgetBundle.swift @main, and nothing else
VersoTests/               21 files, @testable import VersoKit
Config/                   Info.plists and entitlements
```

`Core/` holds the engine, one directory per concern: `Blocks` (the registry and
the payload types), `Models`, `Persistence`, `Theming`, `Templates`, `Metrics`,
`Search`, `Security`, `Intelligence`, `Motion`, `Audio`, `Ink`, `Documents`,
`Location`, `Schedule`, `Timers`, `Haptics`, `Export`, `Support`. `Features/`
holds the screens built on it: `Editor`, `Library`, `ReadMode`, `ForeEdge`,
`Vault`, `Blocks`, `Templates`, `Documents`, `Ink`, `Settings`.

**Why a package.** Both targets depend on the one package, so there is exactly
one copy of the engine, the models and the store — and the compiler enforces
that, rather than a project-file membership list. Moving the whole app into the
package and leaving only `@main` behind is what made that possible without
making a hundred types public.

**The public surface is five types**, across 149 files: `VersoScene`,
`RecentNotesWidget`, `QuickCaptureWidget`, `VersoCaptureControl`, and
`VersoKitPackage`. Everything else is internal. What the app target can reach is
a decision rather than an accident of what happened to be visible, and adding to
the engine never widens the API by accident.

Resources come from `Bundle.module`, declared with SwiftPM's `.copy` rather than
`.process` — `.process` flattens a directory into the bundle root, which leaves
every catalogue in one pile and a subdirectory lookup finding nothing.

### Two rules keep the engine content-agnostic

Both are enforced by tests, not by convention:

- **Decoding goes through `BlockRegistry`.** The only `switch` over `BlockType`
  is the view factory in `Core/Blocks/BlockRenderer.swift`.
- **Adding a template is one JSON file and zero Swift.**
  `TemplateInstantiationTests` invents a template at runtime and builds it
  through the same path the bundled ones use.

Adding a theme or a paper stock is likewise one JSON file.

---

## Building

No Mac required to find out whether it builds — push a branch, and `ios.yml`
compiles and tests it on a runner with no credentials of any kind.

On a Mac:

```bash
brew install xcodegen && xcodegen generate && open Verso.xcodeproj
```

`.xcodeproj` is generated and gitignored, so a build-setting change is a
one-line edit to `project.yml` rather than a merge conflict in a 4,000-line
project file.

The bundle identifier is `com.verso.notes`, with `group.com.verso.notes` and
`iCloud.com.verso.notes` alongside it. Changing it means changing all three,
plus the keychain service — [TESTFLIGHT.md](TESTFLIGHT.md) §3.3 has the command.

---

## What only a device can prove

Everything below compiled and, where testable, passed. None of it has been seen
working. Ordered by how quietly it fails.

| Area | What to check |
|---|---|
| **Keychain and biometrics** | `.biometryCurrentSet` must destroy the local key when enrolled biometrics change; the synchronizable item must reach a second device and the biometry-bound one must not. `kSecUseAuthenticationUIFail` must answer "does a key exist" *without* putting up Face ID on launch. |
| **CloudKit sync** | Two simulators, one account. The schema is asserted; the round trip is not. Also confirm `.externalStorage` ships audio as an asset rather than stalling a save. |
| **The app group** | App, widget and intents read one store through `group.com.verso.notes`. Getting it wrong means three processes quietly using three different databases — `scripts/verify-entitlements.sh` reads what `codesign` actually recorded, because this is the failure the App Store does not object to. |
| **Haptics** | Five AHAP files, none of which can play in a simulator. A wrong intensity is not a compile error, and silence is indistinguishable from hardware that has no haptics. |
| **On-device language model** | `SystemLanguageModel.default.availability` gates everything, and every path behind it has a fallback. Confirm the fallback is what runs when the model is absent — not an empty result. |
| **TextKit 2 fragment rendering** | `VersoTextView` declares no initialiser so `usingTextLayoutManager: true` is inherited. If a subclass initialiser ever creeps in, TextKit 1 takes over silently and the ruled lines simply never draw. |
| **PDF geometry** | Page space is bottom-left origin and every annotation flips exactly once. Mirrored highlights mean the flip happened twice or not at all. Check a two-column PDF and one mixing page sizes. |
| **Pencil** | `PKStroke.path.creationDate` drives ink replay; if it is not what it appears to be, replay is wrong rather than absent. Pencil Pro squeeze may fire the older tap callback. |
| **Geofencing** | `CLMonitor`'s event stream and the ~20-region ceiling `GeofenceBudget.systemLimit` encodes. Always-authorisation must be requested only after When In Use is granted. |
| **Shortcuts registration** | Intents in a package compile but do **not** register unless the app and the extension each declare an `AppIntentsPackage`. Both do. Without it Shortcuts is simply empty and nothing explains why — so check it lists the five intents. |
| **Reveal at 60fps** | Per-glyph rendering attributes under a `TimelineView`, and whether it fights the layout manager. |

---

## Known limitations

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

## Deviations from the specification

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
15. **The reveal works at two levels, and which one depends on the style.**
    Every style staggers whole blocks; `typewriter`, `fadeUp` and `blurIn`
    additionally reveal *within* text blocks via TextKit 2 rendering
    attributes. A checklist or a chart has no glyphs to stagger, and
    per-glyph *offset* or *blur* would need custom fragment drawing with a
    transform per line — so those arrive as whole blocks. Nothing in §6 says
    otherwise, but it is worth knowing which half of a reveal you are seeing.
16. **The animated share card is a GIF, not a video.** §7 says "animated share
    card" without naming a format. A GIF needs no export session, no asset
    writer and no permissions, plays inline in every messaging app, and is
    written with ImageIO, which is already present. Nothing is uploaded to make
    one.
17. **The passphrase-wrapped vault key lives in iCloud Keychain, not in a
    `@Model`.** §7 requires the wrapped key to reach other devices. A
    synchronizable keychain item does that end-to-end encrypted with no schema
    change; a `VaultRecord` model would have been a §4 change, and those are
    yours to approve. The trade-off: if iCloud Keychain is switched off, the
    wrapped key does not travel, and the vault has to be set up again on the
    second device. A model would be the belt-and-braces alternative.
18. **Locking a note also encrypts its version history.** §7 does not mention
    versions, but a snapshot holding yesterday's plaintext would make locking
    cosmetic.
19. **Leaving the app closes the vault.** A vault that stays open in your pocket
    is a Face ID gate wearing a costume.
20. **Semantic search is not gated behind Apple Intelligence.** §7 lists it
    under Foundation Models, but sentence embeddings come from `NLEmbedding`,
    which is on-device and available far more widely. Where embeddings do not
    exist for the user's language, lexical scoring carries the whole feature
    rather than half of it.
21. **The AI affordances are never hidden — only the model behind them
    changes.** §7 says to hide unavailable affordances entirely, and dictation
    obeys that literally: no on-device transcription, no microphone button.
    But suggestions, titling and capture always work, because §1 requires a
    non-AI fallback for each. Hiding those buttons on a non-Apple-Intelligence
    device would advertise an absence that isn't there. The one line in
    Settings says which is doing the work.
22. **Dictation refuses rather than going online.** If a device cannot
    transcribe on-device, the feature reports itself unavailable instead of
    letting `SFSpeechRecognizer` send audio to a server.
23. **Device-only recordings never enter the store at all.** §4's `localOnly`
    could have been a flag asking the sync engine not to carry the bytes.
    Instead the bytes are simply absent from `AudioAsset.recording` and live
    only in the app container, which is a promise rather than a request.
24. **Replay reveals whole strokes, not growing ones.** A stroke becomes
    visible when it *finished*. Interpolating within a stroke would need
    per-point redrawing and would read as a glitch rather than as writing.
25. **Apple Pencil Pro actions honour the system preference.** §7 names squeeze
    and double-tap; `UIPencilInteraction.preferredSqueezeAction` is what the
    user already told iOS those should do, so Verso does that rather than
    inventing its own mapping.
26. **Documents do not sync, and say so.** §5 describes the `attachment`
    payload as a *file ref* and a page count, so that is taken literally: the
    PDF lives in the app container and the payload points at it. A small
    first-page thumbnail rides in the payload so the block still shows what it
    is on another device, where it reads "Not on this device". Making documents
    sync would be the same `.externalStorage` change made for audio in Phase
    10 — say the word and it is a few lines. It was not taken unasked, because
    unlike `AudioAsset.localOnly`, nothing in §4 or §5 implies documents were
    meant to travel.
27. **The document viewer renders pages itself rather than using `PDFView`.**
    Overlaying an annotation canvas means reaching into `PDFView`'s own scroll
    hierarchy, which is fragile and would not let the Phase 10 ink canvas be
    reused. The cost is that page zoom is scroll-based rather than PDFView's
    pinch-to-zoom.
28. **"Start workout" is the template intent with a parameter, not its own
    intent.** §7 lists it alongside "open template". Giving it a dedicated
    intent would mean naming `strength-session` in Swift, which is the
    `if templateID ==` §2 forbids wearing an Intent's clothes. A user who wants
    "Hey Siri, start my workout" builds that Shortcut in one step, choosing the
    template themselves — and it keeps working when they switch templates.
29. **A dragged note leaves as Markdown, not a link.** A note dropped into Mail
    should arrive as something the recipient can read, not a URL that only
    resolves on the device it came from.
30. **Spotlight is rebuilt, not patched.** Incremental updates drift, and a
    stale index entry for a note that has since been locked is a leak rather
    than an inconvenience — so every refresh deletes the excluded ones by name.
31. **No `UIBackgroundModes: audio`.** §7 specifies `AVAudioSession` + a local
   notification for rest timers. The session here only makes the completion
   sound audible over music and with the ringer switch off. Background delivery
   is the notification's job — claiming the audio background mode for a notes
   app that plays no continuous audio is an App Review rejection waiting to
   happen. `.timeSensitive` interruption level does need the Time Sensitive
   Notifications capability adding in Xcode.

---

## Tests

467 tests in 50 suites, Swift Testing throughout, run on every push by
[ios.yml](.github/workflows/ios.yml). They are the only thing standing in for a
device, so they lean towards asserting the constraints that fail silently — the
CloudKit schema rules, the vault exclusions, the zero-Swift template guarantee —
rather than towards coverage for its own sake.

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
| `RevealEngineTests` | Stagger and progress over time, every style starting hidden and settling fully visible, Reduce Motion flattening all six, word units tiling with no gaps, glyph units being composed sequences in UTF-16 |
| `MarkdownExportTests` | Every block type exporting, pipe escaping in tables, formulas exporting as expressions rather than stale results, unreadable blocks skipped, hostile filenames |
| `VaultCipherTests` | Round-trip, ciphertext leaking nothing, tampering detected, wrong key rejected, unique nonces, idempotent sealing |
| `PassphraseKDFTests` | Deterministic derivation, salts mattering and being random, Unicode normalisation, wrap/unwrap, the synced blob revealing no key material |
| `VaultKeyringTests` | Locked notes storing ciphertext and unlocked ones storing plaintext, a closed vault refusing, and all four §7 exclusions |
| `HeuristicIntelligenceTests` | Titling, tag suggestion staying inside the existing vocabulary, summaries never inventing a claim, actions distinguishing imperatives from the past tense |
| `TextStructuringTests` | Markdown, bullets, numbered lists, quantities and units, years not being quantities, and a capture instantiating through the normal template path |
| `NoteDigestTests` | A locked note digesting to nothing |
| `SemanticIndexTests` | Literal matching, title outranking body, every query word having to appear, locked notes never surfacing |
| `SyncMapTests` | Tapping a word resolving to when it was written, strokes appearing only once finished, both streams independent per block |
| `SyncMapRecorderTests` | Coalescing keeping the furthest offset reached, per-block independence, strokes replaced rather than appended |
| `InkAudioPayloadTests` | Round-trips, height clamping, templates keeping shape and dropping content, AAC mono 32kbps |
| `DocumentAnnotationTests` | Normalised rects surviving a resize, ink per page, clearing leaving nothing behind, highlighted text in reading order |
| `AttachmentPayloadTests` | Round-trip, clamping, highlights being what search and export see, templates dropping the document |
| `VersoURLTests` | Deep links round-tripping, foreign and malformed ones resolving to nothing |
| `ActivityEligibilityTests` | Locked, hidden and trashed notes advertised to neither Handoff nor Spotlight, and their titles not travelling either |
| `NoteTransferTests` | A dragged note carrying readable Markdown; a locked one carrying nothing |
| `SpotlightSourceTests` | Excluded notes coming back as *deletions* rather than omissions |
| `IntentTests` | Shortcuts seeing every template with no template named in Swift; locked notes opaque to intents |

What they cannot reach is listed under [What only a device can
prove](#what-only-a-device-can-prove). The gap worth naming twice: the vault's
*cryptography* is tested and its *storage* is not — `VaultCipherTests` and
`PassphraseKDFTests` exercise the round trips, but Keychain access control, the
biometric prompt and iCloud Keychain sync need hardware.
