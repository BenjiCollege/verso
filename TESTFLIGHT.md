# From this repo to TestFlight

Written to be followed in order. The gates are ordered by what blocks what —
account setup is Gate 3 because there is no point creating identifiers for a
build that does not exist yet.

Nothing in this document has been performed. It was written on Windows, with no
Xcode and no access to an Apple Developer account.

---

## Gate 0 — A Mac with Xcode 26

Not optional and not substitutable. Archiving, signing and uploading all require
it. Xcode Cloud can build, but you still need Xcode locally to get the project
compiling in the first place.

---

## Gate 1 — Make it compile

**This is the gate that matters.** The repo has never been built. Work through
[README.md](README.md)'s porting tables, which are ordered by how much each item
blocks. Expect to spend real time here.

```bash
open Verso.xcodeproj
```

Do not proceed until `Product → Build` succeeds for both the `Verso` and
`VersoWidgets` targets, and `Product → Test` passes. The tests are the fastest
way to find what drifted — `ThemeLoaderTests` and `TemplateLibraryTests` in
particular fail loudly if resources or the package boundary are wrong.

---

## Gate 2 — An app icon

**TestFlight will reject an upload without one.** This is a hard stop, not a
warning.

[AppIcon.appiconset](VersoKit/Sources/VersoKit/../../../Verso/Resources/Assets.xcassets/AppIcon.appiconset)
declares the slots and is empty. You need at minimum:

- 1024×1024 PNG, **no alpha channel, no rounded corners** — Apple applies the
  mask
- Optionally the dark and tinted variants the asset catalogue also declares

Drop it into the asset catalogue in Xcode. Everything else about the launch
experience is already done.

---

## Gate 3 — Apple Developer account, identifiers and capabilities

### 3.1 Enrol

[developer.apple.com/programs](https://developer.apple.com/programs/) — £79/$99
a year. Individual or Organization; Organization needs a D-U-N-S number and
takes longer. Verso needs nothing that depends on which you pick.

Note your **Team ID** (Membership details) — it prefixes everything.

### 3.2 Choose your bundle identifier

`com.verso.notes` is a placeholder and is almost certainly not yours to use.
Pick a prefix on a domain you control, reversed — e.g. `com.example.verso`.

Everything derives from it:

| Thing | Placeholder | Yours |
|---|---|---|
| App bundle ID | `com.verso.notes` | `com.example.verso` |
| Widget bundle ID | `com.verso.notes.widgets` | `com.example.verso.widgets` |
| Test bundle ID | `com.verso.notes.tests` | `com.example.verso.tests` |
| App Group | `group.com.verso.notes` | `group.com.example.verso` |
| iCloud container | `iCloud.com.verso.notes` | `iCloud.com.example.verso` |
| Template UTI | `com.verso.notes.template` | `com.example.verso.template` |
| Handoff activity | `com.verso.notes.open-note` | `com.example.verso.open-note` |
| Keychain service | `com.verso.notes.vault` | `com.example.verso.vault` |
| Spotlight domain | `com.verso.notes.notes` | `com.example.verso.notes` |

The widget bundle ID **must** be prefixed by the app's, or the extension will
not install.

### 3.3 Rename in the repo

One search-and-replace covers every one of them, including the `Logger`
subsystems:

```bash
grep -rl "com\.verso\.notes" --include=*.swift --include=*.plist --include=*.pbxproj --include=*.entitlements . | xargs sed -i '' 's/com\.verso\.notes/com.example.verso/g'
```

That also fixes `iCloud.com.verso.notes` and `group.com.verso.notes`, since both
contain the string. Verify with:

```bash
grep -rn "com\.verso\.notes" --include=*.swift --include=*.plist --include=*.pbxproj --include=*.entitlements .
```

It should print nothing.

### 3.4 Register identifiers

[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
→ **Identifiers** → **+**.

Create these four, in this order — the App IDs reference the other two, so those
have to exist first:

1. **App Group** → `group.com.example.verso`, description "Verso Shared"
2. **iCloud Container** → `iCloud.com.example.verso`, description "Verso"
3. **App ID** (App) → explicit `com.example.verso`, with capabilities:
   - **App Groups** — select the group above
   - **iCloud** → CloudKit — select the container above
   - **Push Notifications** — CloudKit sync needs it, even though Verso sends
     none itself
   - **Time Sensitive Notifications** — rest timers and place reminders use
     `.timeSensitive`; without this iOS silently downgrades them
4. **App ID** (App) → explicit `com.example.verso.widgets`, with:
   - **App Groups** — the same group
   - **iCloud** → CloudKit — the same container

The test target needs no App ID; it is never distributed.

Verso needs **no** Sign in with Apple, **no** Associated Domains, **no** HealthKit
and **no** background audio mode. If you find yourself adding one, something has
drifted from the spec.

### 3.5 Certificates and profiles

**Use automatic signing.** In Xcode, for each of the three targets:
*Signing & Capabilities* → tick **Automatically manage signing** → select your
Team. Xcode creates and renews the development and distribution certificates and
the provisioning profiles for you, and gets the `aps-environment` right per
configuration.

Only do it manually if your organisation requires it. The manual path is:

1. Keychain Access → *Certificate Assistant* → *Request a Certificate From a
   Certificate Authority*, save to disk
2. Developer portal → **Certificates** → **+** → *Apple Distribution* → upload
   the CSR → download and double-click the `.cer`
3. **Profiles** → **+** → *App Store Connect* → one profile per App ID → download
   and double-click
4. Xcode → untick automatic signing → select the profiles

> If CloudKit sync works in Debug but not from TestFlight, look at
> `aps-environment` in [Config/Verso.entitlements](Config/Verso.entitlements)
> first. It reads `development`. Automatic signing normally substitutes
> `production` for a distribution build; if yours does not, split the
> entitlements into per-configuration files.

### 3.6 CloudKit schema

CloudKit has a Development and a Production environment, and **the schema does
not promote itself**.

1. Run the app on a device or simulator signed into iCloud. SwiftData creates
   the record types in Development on first sync.
2. [CloudKit Console](https://icloud.developer.apple.com/) → your container →
   *Schema* → confirm `CD_Note`, `CD_Block`, `CD_MetricEntry`, `CD_Version`,
   `CD_AudioAsset`, `CD_Folder`, `CD_Tag` exist.
3. **Deploy Schema to Production.** TestFlight builds use Production. Skip this
   and testers get an app that never syncs and no error explaining it.

Re-deploy after any schema change. There has been one since §4:
`AudioAsset.recording` — see the README.

---

## Gate 4 — App Store Connect record

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+**
→ *New App*.

| Field | Value |
|---|---|
| Platform | iOS |
| Name | Verso *(must be unique across the store — check early)* |
| Primary language | English (U.K.) or (U.S.) |
| Bundle ID | `com.example.verso` |
| SKU | Anything internal, e.g. `verso-ios` |
| User access | Full Access |

You need **App Privacy** answered before external testing, and it is short:
**Data Not Collected**. There is no server, no analytics SDK and no third-party
dependency. See [SUBMISSION.md](SUBMISSION.md) for the full reasoning — it is
worth putting on the product page.

---

## Gate 5 — Archive and upload

1. Bump the build number. Every upload needs a unique `CURRENT_PROJECT_VERSION`;
   `MARKETING_VERSION` only changes when the version does.
2. Scheme → destination → **Any iOS Device (arm64)**. Archive is disabled for a
   simulator destination.
3. *Product* → **Archive**.
4. Organizer opens → select the archive → **Distribute App** → *TestFlight &
   App Store* → **Upload**.
5. Let Xcode manage signing when prompted. Leave *Upload symbols* ticked so
   crash reports are readable.

Processing takes anywhere from five minutes to an hour. You get an email when
the build is ready, and another if it is rejected — read that one carefully;
most first-upload rejections are a missing icon, a bad entitlement, or an
`Info.plist` usage string.

**Export compliance** is already answered:
`ITSAppUsesNonExemptEncryption` is `false` in
[Config/Info.plist](Config/Info.plist), so you will not be asked per build.
[SUBMISSION.md](SUBMISSION.md) explains the reasoning and flags that you should
confirm the current exemption wording in App Store Connect, because it changes.

---

## Gate 6 — TestFlight

### Internal testing — start here

Up to 100 testers, **no beta review**, available within minutes of processing.

1. App Store Connect → your app → **TestFlight** → **Internal Testing**
2. Create a group, add testers by Apple ID — they must already be **Users** on
   your team (*Users and Access*), with at least Developer or Marketing role
3. Assign the build

Testers install [TestFlight](https://apps.apple.com/app/testflight/id899247664)
and accept the invitation.

### External testing — when you want people outside the team

Up to 10,000 testers. Requires **Beta App Review**, usually a day or two.

You need to provide:

- **Beta App Description** — what it does
- **Feedback email**
- **What to Test** — per build
- **Demo account** — *not applicable*. Verso has no accounts and no login, which
  removes the single most common cause of beta review delay. Say so in the
  review notes.

You can then invite by email, or generate a **public link**.

### What to actually test

§9 and §10 name things that only a real device can answer. Worth putting in
*What to Test* verbatim:

- Haptics — five authored patterns, none of which can be judged in a simulator
- Apple Pencil — ink, hover, and Pro squeeze/double-tap
- Face ID / Touch ID → vault unlock, and **change an enrolled face or finger**
  and confirm the vault falls back to the passphrase
- Place reminders — arrive somewhere, and confirm an inactive reminder explains
  itself
- Rest timers surviving backgrounding, and firing while the app is closed
- Recording, then tapping a word or a stroke to seek playback
- Sync — two devices, one iCloud account
- No iCloud account, iCloud full, airplane mode, and a device with no Apple
  Intelligence: all four must degrade gracefully
- VoiceOver, Dynamic Type at AX5, Reduce Motion, Increase Contrast

---

## Common first-upload failures

| Symptom | Cause |
|---|---|
| *Missing app icon* | Gate 2 |
| *Invalid Bundle Identifier* | Widget bundle ID is not prefixed by the app's |
| *Provisioning profile doesn't include entitlement* | A capability enabled in Xcode but not on the App ID, or vice versa |
| *Invalid Code Signing Entitlements* — app group | The group exists in the portal but is not selected on **both** App IDs |
| App installs, but syncs nothing | CloudKit schema not deployed to Production (3.6) |
| Notifications arrive without the time-sensitive banner | Time Sensitive Notifications capability missing from the App ID |
| Shortcuts is empty | `AppIntentsPackage` conformance — see the README; both targets need it |
| Widget shows no notes | App Group mismatch between the two entitlements files |
