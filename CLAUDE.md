# Verso — working notes for agents

A native iOS/iPadOS notes app. ~23,000 lines of Swift, no third-party dependencies.

**The idea:** a note is a *page*, not a text field. Every note carries a paper stock, a
theme and a typographic scale, and text is laid out through TextKit 2 so ruled lines sit on
real baselines. Blocks are typed and the engine never knows what they mean. Keep that idea
intact — most of the rules below exist to protect it.

> The original specification lived in an external `CLAUDE.md` that is not in this repo. The
> `§` references in `README.md` point at it. This file is the working conventions, not that
> specification.

---

## Build and test

`.xcodeproj` is **generated and gitignored**. `project.yml` is the source of truth.
Regenerate after changing `project.yml`, `Package.swift`, or adding/removing any file:

```bash
xcodegen generate
```

Then build or test against a booted simulator:

```bash
xcodebuild test -project Verso.xcodeproj -scheme Verso -configuration Debug \
  -destination "id=$(xcrun simctl list devices available --json | python3 -c "
import json,sys; d=json.load(sys.stdin)['devices']
print([x for rt in sorted(d) for x in d[rt] if 'iPhone' in x['name']][-1]['udid'])")" \
  CODE_SIGNING_ALLOWED=NO
```

**Warnings are errors in Debug.** Set in both `project.yml` *and* `VersoKit/Package.swift` —
a project-level build setting does **not** reach a package target, and the whole app is the
package. A single warning fails the build you are about to run. Release deliberately stays
permissive so an SDK deprecation can never block a release archive.

**Coverage:** `scripts/coverage.sh`. Do **not** use `xcrun xccov` — it reports per Xcode
target, the app is a package, and it will confidently tell you the project is 14 lines.

---

## Hard rules

Break these and something fails silently rather than loudly.

1. **Decoding goes through `BlockRegistry`.** Never write a `switch` over `BlockType` to
   decode a payload. `Core/Blocks/BlockRenderer.swift` is the one place that switches over
   every case, because it is the view factory. (`FormulaContextBuilder` switches over a few
   cases to gather numbers — that is fine; it is not decoding.) The registry is what keeps
   persistence, templates, export and search content-agnostic.

2. **Adding a template is one JSON file and zero Swift.** `TemplateInstantiationTests`
   invents a template at runtime and builds it through the production path to enforce this.
   Same for themes and paper stocks. If you find yourself naming a template id in Swift,
   stop.

3. **Resources use `.copy`, not `.process`.** `.process` flattens directories into the
   bundle root, and `BundleResourceLoader` tells a stock from a template by its folder.

4. **SwiftData models are `nonisolated`, not `@MainActor`.** `SWIFT_DEFAULT_ACTOR_ISOLATION`
   is deliberately left at `nonisolated`: models are context-confined, not
   main-thread-confined. Put `@MainActor` on UI-facing stores instead. Heavy store work goes
   on a `@ModelActor` (`LinkIndexBuilder`, `SearchIndexSource`, `SpotlightIndexer`).

5. **The CloudKit schema constrains the model.** No `.unique`, everything defaulted or
   optional, every relationship with a declared inverse. `SchemaValidityTests` asserts it so
   a violation fails a test rather than the first sync. Any change to `Core/Models/` is a
   schema change — flag it rather than taking it unasked.

6. **Never `CODE_SIGNING_ALLOWED=NO` in a release archive.** It archives cleanly and export
   re-signs, so it looks right — but `CODE_SIGN_ENTITLEMENTS` is a build setting, and a
   build that skipped signing never processed it. App Groups and iCloud vanish silently.

---

## Design system

Use the tokens. Raw numbers and ad-hoc colours are the fastest way to make this app look
like every other notes app.

- **Spacing** `Layout.Space`: `hair` 2, `tight` 4, `snug` 8, `cosy` 12, `regular` 16,
  `loose` 24, `airy` 32, `vast` 48. Also `Layout.hairline`, `Layout.minimumHitTarget` (44).
- **Radius** `Layout.Radius`: `tight` 6, `regular` 12, `loose` 20, `capsule`.
- **Colour** — from `Theme` only: `stock`, `ink`, `inkSecondary`, `inkTertiary`, `inkMuted`,
  `accent`, `accentAlternate`, `rule`, `edge`, `gilt`, and the elevation tokens `canvas`,
  `card`, `cardBorder`, `inset`. Never a system colour, never a literal.
- **Type** — `.versoText(role)`, never `.font()`. Roles: `display` 34, `title` 26,
  `heading` 20, `body` 17, `callout` 15, `footnote` 13, `metadata` 11, and the chrome trio
  `chromeBody` 17, `chromeLabel` 15, `chromeCaption` 13. It scales with Dynamic Type via
  `@ScaledMetric`, so anything sized next to text must scale too.
- **Cards** — `.versoCard(padding:radius:)` is the only way to make one. `SectionLabel` is
  the heading above a group. Cards are for *chrome* — never for the page.
- **Motion** — `@Environment(\.motion)`, then `motion.animation(token)` or
  `motion.run(token) { }`. Never a bare `withAnimation`: the resolver is what supplies the
  Reduce Motion path, and bypassing it ships an animation that ignores the setting.

Surfaces are **cards on a canvas**. The library, gallery, trash and settings all follow it.
Do not reintroduce a system `Form` or `List` styling.

---

## Testing

- **Swift Testing only.** No XCTest anywhere — `@Test`, `@Suite`, `#expect`, `#require`.
- Test names are sentences describing the behaviour, not the method:
  `@Test("A dropped stroke does not renumber the strokes that survive")`.
- The suite leans towards **asserting the constraints that fail silently** — the CloudKit
  rules, the vault exclusions, the zero-Swift template guarantee — rather than coverage for
  its own sake. Prefer a test that would have caught a real bug.
- `Core/` is well covered and should stay that way. `Features/` is mostly views with no seam
  a unit test reaches; do not fake coverage there with tests that assert nothing.
- Filter with parentheses: `-only-testing:'VersoTests/SuiteName/testName()'`.

---

## Accessibility

Not optional here, and repeatedly the thing that has been missed:

- Every custom control needs a label, a value where it has one, and the right traits.
  `Toggle("", isOn:)` is a switch VoiceOver cannot name.
- Dynamic Type to **AX5** without clipping. Fixed-size elements sitting beside scaling text
  will break — either scale them or cap the scale and let the label wrap.
- Reduce Motion via `MotionResolver`, always.
- Hit targets ≥ `Layout.minimumHitTarget`.
- A `UIViewRepresentable` wrapping a UIKit control that advertises nothing — `PKCanvasView`
  is the example — is invisible to VoiceOver until you describe it yourself.

---

## Gotchas that have actually bitten

- `simctl ui <udid> appearance dark` reports success and frequently does **not** propagate.
  Check the *status bar* in a screenshot before concluding the app ignored an appearance
  change. Toggle from the Simulator menu (Features → Toggle Appearance) to be sure.
- `xcodebuild archive` with automatic signing wants a **development** profile and lets
  `-exportArchive` re-sign for distribution. Forcing `CODE_SIGN_IDENTITY` to
  `Apple Distribution` fights automatic signing and fails.
- `LocalizedStringResource(stringLiteral:)` on a runtime string treats it as a *key to look
  up*, not as text. Use `Text(verbatim:)` for strings that are already localised.
- There is no string catalogue, and that is fine: every string is already a
  `LocalizedStringResource` or a SwiftUI `Text`, and
  `xcodebuild -exportLocalizations` yields ~599 translatable strings today.

---

## Before you say it is done

- `xcodegen generate` then the test command above: green, and **zero warnings**.
- Ran the app in the simulator and looked at the screen you changed, in a light theme and a
  dark one. Screenshots, not assumptions.
- If you changed UI, checked it at AX5 Dynamic Type.
- Docs updated if you changed a count, a capability or a deviation — `README.md` and
  `SUBMISSION.md` state specific numbers and they drift fast.
