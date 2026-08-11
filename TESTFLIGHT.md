# From this repo to TestFlight

**No Mac required.** The repo holds no `.xcodeproj` — CI generates it, builds on
a macOS runner, and authenticates to Apple with a single App Store Connect API
key that covers both signing and uploading.

Written on Windows. Nothing here has been run.

---

## How it fits together

```
project.yml            source of truth; .xcodeproj is generated and gitignored
  ↓ xcodegen generate
.github/workflows/
  ios.yml              push + PR      no credentials   "does it compile"
  ios-release.yml      manual only    API key          "can we ship it"
Config/ExportOptions.plist            __TEAM_ID__ substituted at runtime
scripts/verify-*.sh                   what was *actually* signed
```

Two workflows, deliberately separated. A signing failure never looks like a
compile failure, and archiving to inspect a build is a different action from
sending it to Apple — `ios-release.yml` takes an `upload` boolean that defaults
to **false**.

---

## Gate 1 — Make it compile

The repo has never been built. Push to a branch and let `ios.yml` tell you what
is wrong; it needs no secrets, so it works before any account setup.

Work through [README.md](README.md)'s porting tables, which are ordered by how
much each item blocks. `ThemeLoaderTests` and `TemplateLibraryTests` fail loudly
if resources or the package boundary are wrong, which is the intended alarm.

Do not proceed until `ios.yml` is green.

## Gate 2 — An app icon

TestFlight rejects uploads without one. A hard stop, not a warning.

`Verso/Resources/Assets.xcassets/AppIcon.appiconset` declares the slots and is
empty. You need a 1024×1024 PNG with **no alpha and no rounded corners** — Apple
applies the mask.

---

## Gate 3 — Apple Developer portal

### 3.1 Enrol and note your Team ID

[developer.apple.com/programs](https://developer.apple.com/programs/), £79/$99 a
year. Team ID is under *Membership details*.

### 3.2 Register one device — the trap that blocks CI-only teams

**Do this even though you are building on CI and may never install locally.**

Automatic signing at archive time wants an App Development profile, and Apple
will not issue one for a team with zero registered devices. Ad-hoc is rejected
by modern SDKs (`not allowed with SDK 'iOS 26.x'`), and an empty signing
identity makes `xcodebuild` skip `codesign` entirely — which is precisely the
silent-no-entitlements failure the verification scripts exist to catch.

*Devices* → **+** → register any UDID. One is enough. Get it from Finder with
the device connected, or from *Settings → General → About*.

### 3.3 Choose your bundle identifier

`com.verso.notes` is a placeholder. Pick a prefix on a domain you control.
Everything derives from it:

| Thing | Placeholder |
|---|---|
| App bundle ID | `com.verso.notes` |
| Widget bundle ID | `com.verso.notes.widgets` |
| App Group | `group.com.verso.notes` |
| iCloud container | `iCloud.com.verso.notes` |
| Template UTI | `com.verso.notes.template` |
| Handoff activity | `com.verso.notes.open-note` |
| Keychain service | `com.verso.notes.vault` |
| Spotlight domain | `com.verso.notes.notes` |
| `Logger` subsystems | `com.verso.notes` |

One replacement covers all of them, including the two that merely contain the
string:

```bash
grep -rl "com\.verso\.notes" --include=*.swift --include=*.plist --include=*.yml --include=*.entitlements . | xargs sed -i '' 's/com\.verso\.notes/com.example.verso/g'
```

Verify with the same `grep` — it should print nothing. The widget bundle ID
**must** stay prefixed by the app's, or the extension will not install.

### 3.4 Register identifiers, in this order

The App IDs reference the other two, so those have to exist first.

1. **App Group** → `group.com.example.verso`
2. **iCloud Container** → `iCloud.com.example.verso`
3. **App ID** → explicit `com.example.verso`, with:
   - App Groups → select the group
   - iCloud → CloudKit → select the container
   - Push Notifications *(CloudKit needs it; Verso sends none itself)*
   - Time Sensitive Notifications *(rest timers and place reminders)*
4. **App ID** → explicit `com.example.verso.widgets`, with:
   - App Groups → the same group
   - iCloud → CloudKit → the same container

Export fails on any capability that is in an entitlements file but not enabled
on its identifier. The two entitlements files are
[Config/Verso.entitlements](Config/Verso.entitlements) and
[Config/VersoWidgets.entitlements](Config/VersoWidgets.entitlements) — they are
the checklist.

Verso needs **no** Sign in with Apple, **no** Associated Domains, **no**
HealthKit and **no** background audio mode. If you find yourself adding one,
something has drifted from the spec.

### 3.5 The API key

*Users and Access* → **Integrations** → **App Store Connect API** → **+**, role
**App Manager**.

You get a `.p8` (**downloadable once**), a Key ID and an Issuer ID.

One key does both jobs — `xcodebuild` uses it to create certificates and
profiles on demand, and `altool` uses it to upload. There is no exporting a
`.p12` and base64-ing it into a secret anywhere in this setup.

### 3.6 Repository secrets

*Settings → Secrets and variables → Actions*:

| Secret | Where from |
|---|---|
| `ASC_KEY_ID` | shown next to the key |
| `ASC_ISSUER_ID` | at the top of the Integrations page |
| `ASC_KEY_P8` | the whole `.p8`, `-----BEGIN` line included |
| `APPLE_TEAM_ID` | Membership details |

---

## Gate 4 — App Store Connect record

**Apps** → **+** → *New App*. Bundle ID `com.example.verso` — the main bundle
**only**. Extensions ship inside the app and get no record of their own.

App Privacy is short: **Data Not Collected**. No server, no analytics SDK, no
third-party dependency. [SUBMISSION.md](SUBMISSION.md) has the reasoning; it is
worth putting on the product page.

---

## Gate 5 — Archive, verify, upload

*Actions* → **iOS Release** → **Run workflow**.

| Input | Notes |
|---|---|
| `build_number` | Must be higher than the last uploaded. Nothing auto-increments it — see below. |
| `marketing_version` | `1.0` unless the version itself changed |
| `upload` | Leave **false** the first time |

Run it with `upload: false` first. You get a `.ipa` artifact and, more usefully,
the verification output — which tells you whether signing actually worked before
you spend a build number finding out.

### Then deploy the CloudKit schema

CloudKit has separate Development and Production environments and **the schema
does not promote itself**.

1. Run the app once against Development so SwiftData creates the record types
2. [CloudKit Console](https://icloud.developer.apple.com/) → your container →
   *Schema* → confirm `CD_Note`, `CD_Block`, `CD_MetricEntry`, `CD_Version`,
   `CD_AudioAsset`, `CD_Folder`, `CD_Tag`
3. **Deploy Schema to Production**

TestFlight builds use Production. Skip this and testers get an app that never
syncs, with nothing explaining why. Re-deploy after any schema change — there
has been one since §4, `AudioAsset.recording`.

**Export compliance** is already answered: `ITSAppUsesNonExemptEncryption` is
`false` in [Config/Info.plist](Config/Info.plist), so App Store Connect will not
ask on every upload.

---

## Gate 6 — TestFlight

**Internal** — up to 100 testers, no beta review, live minutes after processing.
Testers must already be Users on your team. Start here.

**External** — up to 10,000, requires Beta App Review. You need a beta
description, a feedback email, and *What to Test*. **No demo account is
needed**: Verso has no accounts and no login, which removes the single most
common cause of review delay. Say so in the notes.

### What to actually test

Only a device can answer these:

- The five authored haptic patterns
- Apple Pencil ink, hover, and Pro squeeze/double-tap
- Vault unlock — then **change an enrolled face or finger** and confirm it falls
  back to the passphrase
- Place reminders firing on arrival, and inactive ones explaining themselves
- Rest timers surviving backgrounding and firing while the app is closed
- Recording, then tapping a word or a stroke to seek playback
- Sync across two devices on one iCloud account
- No iCloud account / iCloud full / airplane mode / no Apple Intelligence — all
  four must degrade gracefully
- VoiceOver, Dynamic Type at AX5, Reduce Motion, Increase Contrast

---

## Things that will bite

**`CODE_SIGNING_ALLOWED=NO` must never reach an archive.** It is used in
`ios.yml` for the simulator build, where it is correct and costs nothing. In an
archive it is a silent catastrophe: the build succeeds, export re-signs, the
`.ipa` uploads and installs — but `CODE_SIGN_ENTITLEMENTS` is a *build setting*,
and a build that skipped signing never processed it. The archive carries no
entitlements, and export signs with only `application-identifier`,
`team-identifier`, `get-task-allow` and `beta-reports-active`.

For Verso that means App Groups and iCloud quietly gone. The app looks fine; the
widget shows no notes and sync never happens. Nothing complains — App Store
validation only checks entitlements that a *declared capability* requires, and
neither triggers one. `scripts/verify-entitlements.sh` runs on every release for
exactly this reason.

**`altool` exits 0 on failure.** It prints `UPLOAD FAILED with 1 error` and
returns success. The workflow captures the output and greps it; do not "simplify"
that back to trusting the exit status.

**Nothing auto-increments the build number.** `manageAppVersionAndBuildNumber`
is `false` in ExportOptions on purpose — left on, Xcode rewrites `CFBundleVersion`
during export, so the number you dispatched is not the number Apple receives.

**macOS runners bill at ten times Linux.** Both workflows are path-filtered.
Keep them that way.

### First-upload failures, decoded

| Symptom | Cause |
|---|---|
| *Missing app icon* | Gate 2 |
| *No profiles found* / *requires a development team* | No registered device — Gate 3.2 |
| *Invalid Bundle Identifier* | Widget bundle ID not prefixed by the app's |
| *Provisioning profile doesn't include entitlement* | Capability in the entitlements file but not on the App ID |
| `verify-entitlements.sh` reports nothing signed | Signing was disabled during archive |
| `verify-ipa.sh` says the profile does not grant a key | Profile issued before the capability was enabled; toggle it and let CI re-provision |
| Installs but syncs nothing | CloudKit schema not deployed to Production |
| Notifications arrive without a time-sensitive banner | Time Sensitive Notifications missing from the App ID |
| Shortcuts is empty | `AppIntentsPackage` conformance — both targets need it |
| Widget shows no notes | App Group mismatch between the two entitlements files |
